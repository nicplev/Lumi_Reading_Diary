# Plan: CASES21 export kit + SIS import support (rollover & first-time onboarding)

## What the real export actually looks like

Profiled from the consulting school's return file (structure only — no row data read
into the build, and none of it is reused anywhere in this kit):

| Fact | Value | Consequence |
|---|---|---|
| Header | `STUDENT ID,FIRST NAME,LAST NAME,CLASS NAME,YEAR LEVEL,PARENT EMAIL` | **UPPERCASE** — the CASES21 SQL worksheet uppercases `AS [alias]` names |
| Line endings | CRLF | already handled |
| Blank row | one fully-empty record (`,,,,,`) sits *between* header and data | already dropped by `parseCSV` |
| `STKEY` | `AAA9999` (3 alpha + 4 digits) | fine as an external ID |
| `HOME_GROUP` | `99A` — Prep home groups are numeric-prefixed (e.g. `00A`) | class names import verbatim; fine |
| **`ROUND(SCHOOL_YEAR,0)`** | renders **`0.0`** — and **Prep is year `0`** | 🔴 breaks the year ladder |
| Parent email | repeats across siblings (family-level `DF` join) | expected; not an error |

## The four real gaps

1. **🔴 Year levels are destroyed.** The ladder is `['Prep','1',…,'6']`. CASES21 emits
   `0.0`, `1.0`, `4.0`. None are ladder rungs, so *every row* trips
   `unknownYearLevel` ("isn't a standard level (Prep–6)") and saves `"0.0"` verbatim
   into `additionalInfo.yearLevel`. That poisons downstream: rollover's created-class
   `yearLevel`, the school's-own-top-year graduating detection (`topYearIdx`), the
   renewals ladder bump, and app display.
2. **🔴 First-time onboarding drops Year Level entirely.** `/api/students/import` and
   `importStudents` have no `yearLevel` field at all, and create classes with no
   `yearLevel` — so a school onboarded from CASES21 has no year data for next year's
   rollover to reason about.
3. **No SIS awareness.** No format detection, no raw CASES21 column names
   (`STKEY`/`SURNAME`/`HOME_GROUP`/`SCHOOL_YEAR`), no junk-rows-above-header tolerance,
   no `STATUS` filtering.
4. **Input is file-only.** No paste box, no `.xlsx` — despite the kit guide ending at
   "export to Excel".

## Changes

### A. Year ladder — accept numeric SIS levels
`school-admin-web/src/lib/year-ladder.ts` · `normalizeYearLevel`
- strip trailing `.0`/`.00` (SQL `ROUND()` decimal rendering)
- strip leading zeros (`00`, `01`, `04`)
- **`0` → `Prep`** (CASES21 Foundation)
- accept `Year 4`, `Yr 4`, `Y4`, `Grade 4`
- unknown values still pass through verbatim (existing contract preserved)

Mirror into `functions/src/access.ts` (the documented keep-in-sync twin).
This one change is what makes a raw CASES21 file classify correctly.

### B. SIS adapter — `school-admin-web/src/lib/sis/` (new)
- `parseDelimited(text)` extracted from `parseCSV` so the adapter can scan the first
  few records and pick the **real header row** (tolerates title/blank rows above it).
- `detect.ts` — signature match returning
  `{ format: 'cases21' | 'cases21_raw' | 'generic', headerRowIndex, columnMap, notes }`:
  - **kit output** (aliased, uppercase) — drives the "Detected CASES21" badge
  - **raw table columns** — `STKEY`, `SURNAME`, `FIRST_NAME`, `HOME_GROUP`,
    `SCHOOL_YEAR`, `E_MAIL_A`/`E_MAIL_B`, `STATUS`, `FAMILY`
- `adapt.ts` — per-format row shaping: `STATUS` filter (drop non-`ACTV` when the
  column is present), `E_MAIL_A` → `E_MAIL_B` fallback, year-level normalisation,
  reporting what was dropped and why.
- Extend `HEADER_ALIASES` in `csv.ts` with the raw CASES21 names so the generic path
  works even without detection.

### C. Input surfaces — file · paste · xlsx
Shared `sis-import-input.tsx`:
- file picker (`.csv,.tsv,.txt,.xlsx`)
- **paste box** — pasting from Excel yields TSV, which `parseCSV` already tokenizes
- **`.xlsx`** via `await import('xlsx')`, dynamic so the normal bundle is unchanged;
  first non-empty sheet → CSV → existing parser
- detection banner: format, row count, and an explicit list of what was skipped
Wired into **both** the rollover wizard upload step and the Students-page CSV dialog.

### D. First-time import gains Year Level
`CSVRow` + zod schema + `importStudents`: accept `yearLevel`, write
`additionalInfo.yearLevel`, and set a created class's `yearLevel` from the modal year
of its rows (mirroring rollover). Closes gap 2.

### E. The kit
- `docs/cases21/Lumi_Student_Export_v1.1.sql` — refined query:
  - `CAST(... AS INTEGER)` so Year Level is `4` not `4.0`
  - `CASE WHEN SCHOOL_YEAR = 0 THEN 'Prep'` so Foundation exports as `Prep`
  - `UPPER(ST.STATUS) = 'ACTV'` (case-safety)
  - drop blank `STKEY` / `HOME_GROUP` rows (the observed empty record)
  - `TRIM()` on names and home group
  - commented optional blocks: include `FUT` future enrolments, campus filter,
    rollover-only variant (no parent email)
- `docs/cases21/README.md` — full guide, supersedes the thin docx (which still carried
  a "final SQL TBC" placeholder). CASES21 navigation path, the Excel→CSV step, column
  contract, troubleshooting keyed to the errors the importer actually emits.
- `school-admin-web/public/kit/` copies + a **"CASES21 export kit"** panel in the
  rollover wizard that downloads them.

### F. Tests
- `scripts/sis-detect.test.ts` — fixtures replicating the **real header layout**
  (uppercase, CRLF, blank row, `0.0` years) with **entirely synthetic rows**
- `scripts/year-ladder.test.ts` — numeric/`Prep`/unknown normalisation
- extend `scripts/rollover-classify.test.ts` for numeric year levels
- `tsc` + `next build` (with the dev server stopped) — the portal has no CI/ESLint gate

## Out of scope
Compass and other SIS vendors — the adapter is shaped so each is a new signature +
column map, but only CASES21 has a confirmed real sample.
