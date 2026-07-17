/**
 * State term-dates fallback.
 *
 * Streak protection treats days outside the school's configured termDates as
 * school holidays, so a school that never finishes entering its dates (the
 * prod case that triggered this: Term 1 entered, Terms 2-4 forgotten) makes
 * every day after Term 1 a protected holiday and freezes streaks forever.
 *
 * The applyStateTermDates cron closes that hole: for every school it resolves
 * the Australian state from the school's address, looks up the official
 * government term dates for the school's current local year, and fills in any
 * term slot the school hasn't (validly) entered for this year — without ever
 * touching a slot the school customised for the current or a future year, so
 * schools that deliberately differ from state dates by a few days keep their
 * own calendar. Because it re-runs daily, each January the previous year's
 * entries go stale and are rolled forward to the new year's official dates
 * automatically.
 *
 * Date sources: the bundled AU_STATE_TERM_DATES table, overridable per year
 * without a deploy via the platformConfig/stateTermDates doc (same shape:
 * {"2028": {"VIC": [{term, start, end}, ...], ...}}).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {coerceTermDateStr, localDateString} from "./dateUtils";
import {
  AU_STATE_TERM_DATES,
  StateTermEntry,
  StateTermTable,
} from "./state_term_dates_data";
import {DEFAULT_TIMEZONE} from "./access";

const STATE_TERM_DATES_OVERRIDE_DOC = "platformConfig/stateTermDates";

/** Postcode → state, per Australia Post allocations. */
const POSTCODE_RANGES: Array<{min: number; max: number; state: string}> = [
  {min: 200, max: 299, state: "ACT"},
  {min: 800, max: 999, state: "NT"},
  {min: 1000, max: 2599, state: "NSW"},
  {min: 2600, max: 2618, state: "ACT"},
  {min: 2619, max: 2899, state: "NSW"},
  {min: 2900, max: 2920, state: "ACT"},
  {min: 2921, max: 2999, state: "NSW"},
  {min: 3000, max: 3999, state: "VIC"},
  {min: 4000, max: 4999, state: "QLD"},
  {min: 5000, max: 5799, state: "SA"},
  {min: 6000, max: 6797, state: "WA"},
  {min: 7000, max: 7799, state: "TAS"},
  {min: 8000, max: 8999, state: "VIC"},
  {min: 9000, max: 9999, state: "QLD"},
];

const STATE_NAMES: Array<{re: RegExp; state: string}> = [
  {re: /\bvictoria\b/i, state: "VIC"},
  {re: /\bnew south wales\b/i, state: "NSW"},
  {re: /\bqueensland\b/i, state: "QLD"},
  {re: /\bsouth australia\b/i, state: "SA"},
  {re: /\bwestern australia\b/i, state: "WA"},
  {re: /\btasmania\b/i, state: "TAS"},
  {re: /\bnorthern territory\b/i, state: "NT"},
  {re: /\baustralian capital territory\b/i, state: "ACT"},
];

/**
 * Resolves the Australian state for a school from its address (an explicit
 * `state` field wins if one is ever added to signup). Tries, in order: the
 * uppercase abbreviation as its own word ("... Beaumaris VIC 3193"), the
 * spelt-out state name, then the postcode. Abbreviations are matched
 * case-sensitively so address words like "Sale" or "Nt" can't false-match.
 * @param {FirebaseFirestore.DocumentData} schoolData The school doc data.
 * @return {string | null} "VIC" | "NSW" | ... | null when undetectable.
 */
export function detectSchoolState(
  schoolData: FirebaseFirestore.DocumentData,
): string | null {
  const explicit = String(schoolData.state ?? "").trim().toUpperCase();
  if (/^(VIC|NSW|QLD|SA|WA|TAS|NT|ACT)$/.test(explicit)) return explicit;

  const address = String(schoolData.address ?? "");
  if (!address) return null;

  const abbrev = address.match(/\b(VIC|NSW|QLD|SA|WA|TAS|NT|ACT)\b/);
  if (abbrev) return abbrev[1];

  for (const {re, state} of STATE_NAMES) {
    if (re.test(address)) return state;
  }

  // Last 4-digit token that fits a known allocation — "last" so a street
  // number like "2600" can't shadow the trailing postcode.
  const tokens = address.match(/\b\d{4}\b/g) ?? [];
  for (const token of tokens.reverse()) {
    const n = parseInt(token, 10);
    const hit = POSTCODE_RANGES.find((r) => n >= r.min && n <= r.max);
    if (hit) return hit.state;
  }
  return null;
}

/**
 * Decides which termNStart/termNEnd fields to fill for one school.
 *
 * A slot is kept when both its dates parse AND its start year is the current
 * local year or later (a future-year entry a school typed in December is
 * custom too). Anything else — missing, half-entered, unparseable, or left
 * over from a previous year — is filled from the state's official dates.
 * @param {unknown} termDatesRaw The school's raw termDates map.
 * @param {StateTermEntry[]} stateTerms Official dates for state + year.
 * @param {number} currentYear The school's current local calendar year.
 * @return {{fields: Record<string, Date>, filledTerms: number[]} | null}
 *   Firestore update field paths (termDates.termNStart/...) with UTC-midnight
 *   Dates (the portal's own storage convention), plus which term numbers were
 *   filled — or null when every slot is the school's own.
 */
export function planTermDatesFill(
  termDatesRaw: unknown,
  stateTerms: StateTermEntry[],
  currentYear: number,
): {fields: Record<string, Date>; filledTerms: number[]} | null {
  const raw = (typeof termDatesRaw === "object" && termDatesRaw !== null) ?
    termDatesRaw as Record<string, unknown> :
    {};

  const fields: Record<string, Date> = {};
  const filledTerms: number[] = [];

  for (const entry of stateTerms) {
    const start = coerceTermDateStr(raw[`term${entry.term}Start`]);
    const end = coerceTermDateStr(raw[`term${entry.term}End`]);
    const startYear = start ? parseInt(start.slice(0, 4), 10) : 0;
    const keep = start !== null && end !== null &&
      start <= end && startYear >= currentYear;
    if (keep) continue;

    fields[`termDates.term${entry.term}Start`] =
      new Date(`${entry.start}T00:00:00Z`);
    fields[`termDates.term${entry.term}End`] =
      new Date(`${entry.end}T00:00:00Z`);
    filledTerms.push(entry.term);
  }

  return filledTerms.length > 0 ? {fields, filledTerms} : null;
}

/**
 * Merges the bundled term-date table with the platformConfig override doc
 * (override years win wholesale — simplest mental model for ops).
 * @param {FirebaseFirestore.DocumentData | undefined} overrideData The
 *   platformConfig/stateTermDates doc data, if the doc exists.
 * @return {StateTermTable} The effective year → state → terms table.
 */
export function mergeStateTermTables(
  overrideData: FirebaseFirestore.DocumentData | undefined,
): StateTermTable {
  const merged: StateTermTable = {...AU_STATE_TERM_DATES};
  for (const [year, states] of Object.entries(overrideData ?? {})) {
    if (!/^\d{4}$/.test(year)) continue; // skip updatedAt etc.
    if (typeof states !== "object" || states === null) continue;
    merged[year] = states as StateTermTable[string];
  }
  return merged;
}

/**
 * Runs the fill across all schools. Reads: 1 override doc + the schools
 * collection (already O(schools)); writes: only schools with slots to fill.
 * @return {Promise<object>} Pass counters + a note when the coming year's
 *   dates are missing (surfaced on the cron heartbeat from 1 October).
 */
export async function runStateTermDatesFillPass(): Promise<{
  schools: number;
  filled: number;
  noState: number;
  noDates: number;
  missingYearsNote: string | null;
}> {
  const db = admin.firestore();
  const overrideSnap = await db.doc(STATE_TERM_DATES_OVERRIDE_DOC).get();
  const table = mergeStateTermTables(overrideSnap.data());
  const schoolsSnap = await db.collection("schools").get();

  let filled = 0;
  let noState = 0;
  let noDates = 0;
  const statesInUse = new Set<string>();
  let maxLocalYear = 0;

  for (const schoolDoc of schoolsSnap.docs) {
    const schoolData = schoolDoc.data();
    const state = detectSchoolState(schoolData);
    if (!state) {
      noState++;
      continue;
    }
    statesInUse.add(state);

    const tz = String(schoolData.timezone ?? DEFAULT_TIMEZONE);
    const today = localDateString(new Date(), tz);
    const year = parseInt(today.slice(0, 4), 10);
    maxLocalYear = Math.max(maxLocalYear, year);

    const stateTerms = table[String(year)]?.[state];
    if (!stateTerms || stateTerms.length === 0) {
      noDates++;
      continue;
    }

    const plan = planTermDatesFill(schoolData.termDates, stateTerms, year);
    if (!plan) continue;

    await schoolDoc.ref.update({
      ...plan.fields,
      termDatesAutoFill: {
        state,
        year,
        terms: plan.filledTerms,
        appliedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
    filled++;
    functions.logger.info("termDates auto-filled from state dates", {
      state, year, terms: plan.filledTerms,
    });
  }

  // From October, nag (via the heartbeat note) when next year's dates are
  // missing for a state we actually serve — the summer-holiday rollover in
  // January must not land on an empty table.
  let missingYearsNote: string | null = null;
  const month = parseInt(
    localDateString(new Date(), DEFAULT_TIMEZONE).slice(5, 7), 10);
  if (month >= 10 && maxLocalYear > 0) {
    const nextYear = String(maxLocalYear + 1);
    const missing = [...statesInUse]
      .filter((s) => !table[nextYear]?.[s]?.length).sort();
    if (missing.length > 0) {
      missingYearsNote =
        `missing ${nextYear} term dates for: ${missing.join(", ")}`;
      functions.logger.warn("state term dates missing for coming year", {
        year: nextYear, states: missing,
      });
    }
  }

  return {
    schools: schoolsSnap.size,
    filled,
    noState,
    noDates,
    missingYearsNote,
  };
}
