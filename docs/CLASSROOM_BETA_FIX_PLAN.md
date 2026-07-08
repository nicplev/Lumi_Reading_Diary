# Classroom Beta Fix Plan

**Date:** 2026-07-07 · Derived from `docs/CLASSROOM_BETA_READINESS_REVIEW.md` after product triage.

## STATUS: ALL SHIPPED (merged to main 2026-07-07/08, deploys pending)

| WS | PR | Notes |
|---|---|---|
| WS1 timezones (functions) | #278 | |
| WS2a term-dates streaks (functions) | #279 | |
| WS2b term-dates shape/UI | #284 | Discovery: portal already had the termDates editor (`{termNStart,termNEnd}` map) — functions now parse that shape; **no new UI needed, no migration** |
| WS3a books awards retired (functions) | #280 | |
| WS3b books ladder hidden (app) | #287 | |
| WS4 portal school-tz boundaries | #281 | analytics follow-up CLOSED by #291 (school-tz periods/day-keys/weekday filters, hardened resolvePeriod + getSchool, 30 runtime assertions incl. DST days) |
| WS5 portal dashboard timeframes | #283 | |
| WS6 class report v2 | #285 | |
| WS7 portal MFA login | #286 | ⚠️ needs manual test with a real MFA account post-deploy |
| WS8 kiosk exit PIN (app) | #288 | |
| WS9 app dashboard timeframes | #289 | |

**Remaining to go live:** `firebase deploy --only functions` (carries #278/279/280/284) · portal deploy (carries #281/283/284/285/286) · next Flutter release (carries #287/288/289). Post-deploy: enter/verify Term Dates per beta school in Settings, verify school `timezone` fields, manual portal-MFA login test.

## Decisions honoured (deliberately NOT being built)

- **No parent backdating** — nightly logging is the accountability mechanism; a date picker would recreate the Friday-morning batch-logging failure of paper diaries.
- **No teacher push notifications for parent replies** — teachers must not be pinged outside school hours; comment discovery stays pull-only (dashboard widget / per-student view).
- **No bulk whole-class logging** — deferred; not a problem for the majority of classes.
- **In-app (Flutter) class reports stay dev-gated** — they need more development at a later date; the portal is the reporting surface.

## Workstreams (in implementation order)

### WS1 — fix(functions): timezone correctness — branch `fix/functions-timezone-defaults`
The AU product currently defaults schools without a `timezone` field to **Europe/London**, and the Top Reader week is measured in Sydney time for every school.

1. Default `timezone` → `DEFAULT_TIMEZONE` (`Australia/Sydney`, exported by `access.ts:16`) at every read site:
   - `index.ts:199` (legacy `aggregateStudentStats`), `index.ts:1033` (`processSchool` for reminders), `stats_aggregation.ts:123` + `:204`, plus any other `Europe/London` grep hits.
2. `sendReadingReminders` "logged today" window (`index.ts:1098-1104`) currently uses **UTC midnight**. Replace with the school-local day using the same generous-UTC-window + in-memory `localDateString` filter pattern `topReaderAward` already uses (add `date` to the `.select()`).
3. `topReaderAward`: compute `previousWeek` and the query window **per school** using `school.timezone ?? DEFAULT_TIMEZONE` (currently a single Sydney-tz week for all schools, `top_reader_award.ts:84-85`). Cron stays Mon 05:00 Sydney (all-AU beta; by then it is Monday everywhere in AU).
4. Tests: extend `functions/test/*` where the affected helpers are covered; verify with `npm run lint` + `tsc` + unit tests.

### WS2a — feat(functions): term dates + streak fixes — branch `feat/term-dates-streaks`
**Data model:** `schools/{id}.termDates: [{start: "YYYY-MM-DD", end: "YYYY-MM-DD", label?}]` — inclusive school-local calendar ranges. Absent/empty ⇒ current behaviour (every day counts).

1. `dateUtils.ts`:
   - `TermRange` type + `buildIsCountingDay(termDates)` (defensive parsing; malformed entries ignored).
   - `computeGentleStreak(..., isCountingDay)`: **non-counting (holiday) days are skipped entirely** — they never consume rest days and never break a streak; reads ON holiday days still count toward the streak (holiday reading is rewarded, never required).
   - **Liveness fix** (also fixes the weekend quirk where a Fri-reader's streak displays 0 on Sun/Mon): replace the "read today or yesterday" gate with *live iff the number of counting days after the last reading day, up to today, ≤ `MAX_REST_DAYS + 1`* — exactly the window in which the streak is still bridgeable. Bounded walk (≤ ~400 days) for safety.
   - `computeLongestStreak` stays as-is (conservative across holidays is fine — it is monotonic via the `priorLongest` guard and gets fed by live `currentStreak`).
2. Wire `termDates` through all three streak call sites (`reconcileStudentStats`, `applyStudentStatsDelta`, legacy `aggregateStudentStats`) — each already reads the school doc.
3. `topReaderAward`: when `termDates` is configured and the previous week contains **no counting day**, skip the class entirely (holder keeps gold through the break; no award for an empty holiday week).
4. Unit tests in `functions/test/dateUtils.test.js`: holiday bridging, liveness across weekend/holiday, holiday reads counting, empty-termDates back-compat.
5. Reminders during term breaks intentionally unchanged (holiday reading stays encouraged); revisit after beta feedback.

### WS2b — feat(portal): term-dates settings UI — branch `feat/portal-term-dates`
Admin-only Settings card: list of terms (label, start, end date pickers), add/remove, validation (start ≤ end, no overlap), saved to the school doc via the portal's existing settings API route pattern. Follows the New Lumi Design Guide section theming.

### WS3a — feat(functions): retire books-based achievements — branch `feat/awards-minutes-not-books`
Books-read is untrackable (title-instances per night, free-text titles), so it must not drive rewards.

1. `achievements.ts`: stop awarding `BOOKS_TIERS` (delete the `checkTiers(BOOKS_TIERS, ...)` call in `computeAwardableAchievements:125`), mirroring how streak tiers were retired — legacy earned books badges remain on student docs and still render. Keep exports/thresholds for back-compat.
2. Update `functions/test/achievements.test.js` expectations.
3. Top Reader is already minutes-based — no change.

### WS3b — feat(app): hide books ladder in achievements UI — branch `feat/app-awards-minutes-not-books`
Mirror the server: the achievements page stops showing locked/upcoming books tiers (earned legacy ones still render); the near-miss nudge never suggests a books tier. Keep in sync with `AchievementThresholds` mirror comment in `achievement_model.dart`.

### WS4 — fix(portal): school-timezone day/week boundaries — branch `fix/portal-school-tz`
1. New `school-admin-web/src/lib/school-time.ts`: `localDateString`, local-midnight instant for a `YYYY-MM-DD` in an IANA tz (Intl-based, no new deps), Monday-anchored week bounds, plus a cached `getSchoolTimezone(schoolId)` (default `Australia/Sydney`).
2. Replace every server-local `new Date()` boundary: `dashboard.ts:230-235, 263-271, 321-328, 461-462, 678-681` and `api/reports/route.ts:16-31`.
3. Gate: `tsc --noEmit` (+ `next build` only if no dev server is running).

### WS5 — feat(portal): teacher dashboard timeframe selector — branch `feat/portal-dashboard-timeframes`
**This week / Last week / Last 4 weeks** selector on the teacher dashboard driving the weekly chart + engagement summary (fixes the Monday-9am-empty-dashboard problem). Selection persisted (localStorage). Boundaries via WS4's utility.

### WS6 — feat(portal): class report v2 — branch `feat/portal-class-report-v2`
1. **Full per-student roster table** (every student, sortable): sessions, minutes, reading days, avg min/session, met-target %, last read — replaces the silent top-10/needs-support-10 caps (`reports.ts:150,161`); keep the summary lists but complete.
2. **CSV export** of the per-student rows for the selected range (client-side blob download).
3. **This week / Last week presets** added to the existing 7/30/90/year/custom presets; all boundaries school-tz correct (WS4).
4. PDF includes the full roster (paginated); "Books" headline metric replaced with **Reading days** (books counts are title-string instances — untrustworthy, per WS3 rationale).

### WS7 — fix(portal): MFA-aware login — branch `fix/portal-mfa-login`
Handle `auth/multi-factor-auth-required` in `login/page.tsx`: `getMultiFactorResolver` → invisible `RecaptchaVerifier` → `PhoneAuthProvider.verifyPhoneNumber(mfa hint + session)` → SMS code input step → `PhoneMultiFactorGenerator.assertion` → resolver.resolveSignIn → existing session-cookie mint. Includes resend + error states. **Verification requires a real MFA-enrolled account** — flag for manual test before deploy.

### WS8 — feat(app): optional kiosk exit PIN — branch `feat/kiosk-exit-pin`
Per-teacher 4-digit PIN stored in `flutter_secure_storage` (key scoped by teacher uid, device-local). On kiosk launch with no PIN configured: one-time "Set an exit PIN (recommended)" sheet with Skip. Exit dialog requires the PIN when set; "Forgot PIN?" → full sign-out (safe: re-login required). Manage (change/remove, requires current PIN) from the kiosk entry flow.

### WS9 — feat(app): dashboard weekly-chart timeframe toggle — branch `feat/app-dashboard-timeframes`
This week / Last week toggle on the Flutter teacher dashboard's time-scoped widgets (weekly chart first), persisted per teacher.

## Deploy / release sequencing

| Surface | Carries | Action (manual, confirm with Nic first) |
|---|---|---|
| Cloud Functions | WS1, WS2a, WS3a | `firebase deploy --only functions` once all three merge |
| School portal | WS2b, WS4, WS5, WS6, WS7 | `pnpm install --ignore-workspace` then `FIREBASE_CLI_EXPERIMENTS=webframeworks firebase deploy --only hosting:school` |
| Flutter app | WS3b, WS8, WS9 | next release via `./scripts/flutter-build.sh` |

**Post-deploy ops:** set `termDates` for each beta school (new portal UI); verify each school doc has `timezone`; manual MFA-login test on the deployed portal.

## Verification gates per PR
- functions: `npm run lint` + `npx tsc --noEmit` + `npm test` (unit suites; emulator-dependent rules tests excluded as usual).
- portal: `npx tsc --noEmit`; `next build` only when the dev server is not running.
- app: `flutter analyze` (touched files clean); targeted `flutter test` where suites exist (~38 pre-existing emulator-dependent failures are not regressions).
