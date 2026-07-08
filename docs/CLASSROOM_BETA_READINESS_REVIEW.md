# Lumi — Classroom Beta Readiness Review (harsh-critic edition)

**Date:** 2026-07-06
**Method:** five parallel deep code audits (teacher workflows, reading-log lifecycle, reliability/failure modes, setup & lifecycle, portal & reporting) across `lib/`, `functions/`, `school-admin-web/`, `firestore.rules`, plus the existing parent-UX research (`docs/parent-ux-research.md`).
**Bar being judged against:** reliable, easy/convenient, better than a physical reading diary, an add-on to the classroom — not a burden.

---

## 1. Verdict

**The home-reading leg (parent logs at home, teacher monitors) is close to beta-ready and genuinely better than a diary. The classroom leg is not.** The teacher-facing product loses to a paper diary on the four things teachers actually do with diaries — tick a column for the whole class in one pass, sight-and-sign so families know it was seen, track that the levelled reader comes back, and produce a per-child record at reporting time. None of those four exist yet.

Beyond feature gaps, there are **two categories of beta-ender**:

1. **A Day-1 setup landmine**: CSV-imported students have no `access` entitlement, the entitlement is fail-closed on the parent logging path, and there is no self-serve way to activate a class for the *current* year. If the ops script isn't run first, every parent hits a lock screen on night one.
2. **A silent-data-loss cluster** on school wifi and shared iPads: the main write path bypasses the app's excellent offline queue, shows full success while the write sits only in Firestore's local cache, and those pending writes are silently dropped when a different teacher signs into the same device.

Both are fixable before beta. The feature gaps (bulk logging, returns, reporting, term dates) determine whether teachers *keep using it* after week three.

---

## 2. What the deployment actually is (implementation summary)

| Actor | Surface | Daily job |
|---|---|---|
| Parent/carer | Flutter app (mobile) | Log the night's reading (wizard, quick-log, iOS widget); view streaks/achievements; reply to teacher comments |
| Teacher | Flutter app (4 tabs: Dashboard · Class · Library · Settings) | Monitor dashboard nudges, allocate books (scanner/manual), proxy-log for non-app families, manage groups/awards, reply to comments |
| Teacher | School portal (web) | Class view, groups (DnD), allocations, class report PDF, log reading via modal — no scanner/kiosk |
| Class (kids) | iPad "kiosk" inside the teacher's app session | Tap your name → scan the barcode of the book you're taking home |
| School admin | School portal | Classes, staff, student CSV import, parent link codes, renewals, analytics, comms campaigns |
| Lumi (you) | Super-admin portal + ops scripts | School creation, subscriptions, `config/academicYear`, access backfill, data export |
| Server | Cloud Functions | Stats aggregation on every log, weekly Top Reader (Mon 05:00 Sydney), reminders (hourly), Sunday reconcile, 25 Jan rollover |

**The intended weekly rhythm:** teacher allocates books (scan or portal) → kids take books home → parents log nightly → dashboard/nudges show who's reading → Monday the Top Reader is crowned → teacher follows up stragglers and replies to comments. **The yearly rhythm:** Jan 25 rollover advances the academic year; access hard-expires ~Jan 31; class assignment is redone manually; renewals are opt-in per student.

---

## 3. Day-1 landmines — fix before any school touches it

### 3.1 The access-entitlement cliff (P0, the biggest one)
- `createStudent` and `importStudents` never write `access` (`school-admin-web/src/lib/firestore/students.ts:89,469`). Fail-closed rules deny parent log-creates without a live `access` (`firestore.rules:109-112, 442-449`).
- The auto-grant on parent linking (`functions/src/parent_linking.ts:367-389`) requires **both** an active `schoolSubscriptions/{schoolId}_{year}` row **and** `config/academicYear` to exist — otherwise it **silently no-ops** and the parent lands on the lock screen ("contact your school office") with no self-fix.
- The portal's "Mark Subscribed" writes `enrollmentStatus` only — **never** `access` (`api/students/[studentId]/enrollment/route.ts:27`). An admin will believe they've activated a class when they haven't.
- The only bulk grant is `functions/scripts/backfill-access.cjs` (ops script) or renewing into *next* year; there is **no "activate my class for this year" button anywhere**.

**Beta consequence:** night one, 25 families install the app, link their child, and every single one is locked out. The teacher gets 25 complaints and the school's first impression is "it doesn't work."
**Fix:** run the backfill script per beta school AND build a portal self-serve "activate class" action; unify `enrollmentStatus` with `access` or remove the misleading button.

### 3.2 Timezone defaults are wrong for an AU product (P0, config-level fix)
- Stats/streak day-bucketing and reminder scheduling default a school with no `timezone` field to **Europe/London** (`functions/src/index.ts:199, 1033`). An AU school without the field gets corrupted streaks (a Sydney morning read lands on the previous day) and reminders that fire **around 3am**.
- The portal computes "today"/"this week" from the **server's local clock**, not the school timezone (`school-admin-web/src/lib/firestore/dashboard.ts:230-235, 461-462`; `api/reports/route.ts:16-31`) — the portal and the streak engine can disagree about what day it is.
- `topReaderAward` measures the week in **Sydney time for every school regardless of location** (`functions/src/top_reader_award.ts:77-85`) — a Perth school's Sunday-evening reads fall into next week's award.
**Fix now:** verify/set `timezone` on every beta school doc; make school-creation require it. Fix the portal boundaries and per-school award tz before expanding beyond one timezone.

### 3.3 Hidden prerequisite: `config/academicYear`
If absent, parent-link grants silently no-op and `annualRollover` aborts (`functions/src/renewals.ts:191-194`). No UI creates it. **Add to the beta ops checklist and bootstrap it in code.**

### 3.4 Portal MFA lockout
The portal login is bare `signInWithEmailAndPassword` with **no `auth/multi-factor-auth-required` handler** (`school-admin-web/src/app/login/page.tsx:39-68`). Any teacher who enrolled MFA in the app **cannot log into the portal at all**. Since app signup pushes MFA enrolment, this may already affect every beta teacher.

### 3.5 No force-update mechanism
`minAppVersion` is decoded from the status worker payload and **never read** (`lib/core/models/remote_message.dart:38-39` — no consumer). Rules/functions deploys are manual; an old app against new rules becomes a `permission-denied` storm with no "please update" path. Cheap insurance: wire a version gate before beta.

### 3.6 Startup can black-screen brick
`main()` awaits `Firebase.initializeApp`, `CrashReportingService.initialize`, and `FirebaseService.initialize` (which rethrows) with **no try/catch and no fallback UI** (`lib/main.dart:58-89`) — any throw means `runApp` never executes. Also: a validly-signed-in teacher on throttled wifi who hits the splash screen's 10s `getUser` timeout is **dumped to the login screen** (`splash_screen.dart:81-115`) and into MFA SMS friction.

---

## 4. Reliability — what will burn a teacher mid-class

The repo's best code (`OfflineService`: never-drop queue, server read-back receipts, backoff, integrity hashes) is **bypassed by the main write path**:

1. **Success can be a lie.** `writeLog` gates on `canWriteToFirebase` (= "status probe said healthy up to 30s ago", `service_status.dart:73`) and then does a raw `set()`. With persistence enabled, that `set()` acks against the **local cache** — the parent/teacher sees the full success celebration while the write sits in Firestore's hidden pending queue, invisible to the app's `needsAttention`/sync UI (`reading_log_service.dart:286-310`).
2. **Shared-iPad silent data loss.** `signOut()` never calls `clearPersistence()` (`firebase_service.dart:159-176`). Pending writes survive sign-out; when the **next teacher** signs in on the same iPad they flush under the new UID, fail the ownership rules, and Firestore **silently drops them**. Teacher A's logs are gone, no error anywhere. This is the classic shared-device-trolley scenario.
3. **The eternal spinner.** When the probe still says healthy but the network is actually dead (the classic school-wifi state), the interactive `set()` has **no `.timeout()`** — the save spinner hangs forever, never erroring, never falling back to the offline queue (`reading_log_service.dart:292-297`).
4. **Every callable is a 70s cliff.** School-code verify, parent linking, SMS verify, campaign send, audio URL fetch — none have timeouts (except one 30s), none retry, none queue (`parent_linking_service.dart:28`, `school_code_service.dart:60`, etc.). On filtered school wifi these are 70-second spinners ending in a generic error.
5. **The connectivity probe itself can be blocked by school IT.** The internet-check is hardcoded to `https://1.1.1.1/cdn-cgi/trace` (`service_status_controller.dart:38`) — commonly blocked on school networks — producing a misdiagnosed "offline" banner while Firebase is actually fine (or vice versa under SSL inspection).
6. **No mid-session auth handling.** Nothing listens for token revocation; a revoked/expired session becomes silent write failures with generic snackbars, no re-login prompt (grep: no `authStateChanges` guard in the running app). The kiosk runs on the teacher's session, so a session death **stops the whole class's scanning** with no recovery path.
7. **Error hygiene:** ~110 swallowing catch blocks; awards/kiosk/registration collapse every failure into one canned string; kiosk roster spins forever on a stalled stream (`classroom_kiosk_screen.dart:192-198`).
8. **Aggregation backlog under classroom burst.** Stats triggers run with `concurrency: 1` (`functions/src/index.ts:141`); when a whole class logs at once, "On Streak" and "Needs attention" (which read aggregated docs) lag behind the raw-log widgets on the same dashboard — the teacher sees the app disagree with itself.

---

## 5. The daily classroom loop — friction inventory

### 5.1 No bulk logging — the headline gap vs paper
The only teacher proxy-log entry point is **one student's detail screen**: Class tab → student → Log → book+minutes → save, with a network fetch per student (`teacher_log_reading_sheet.dart`, reachable only from `student_detail_screen.dart:1059`). There is **no "mark these 25 as read", no roster multi-select, no tick-column equivalent**. For the stated use case (families who can't use the app; teacher logs in-class reading), that's ~25 × 4-5 taps + 25 screen loads where a diary is one pass down a column. Teachers will simply not do it.

### 5.2 Parents cannot backdate, edit, or delete — ever
- Both parent flows hardcode `date: DateTime.now()` — **no date picker** (`reading_log_service.dart:113, 208`). "Kids read Mon–Wed, parent logs Thursday" collapses three nights into one, undercounting streaks/days — the app punishes exactly the honest catch-up behaviour diaries handle trivially.
- **No edit UI exists at all**, and no delete is wired outside the 5-minute iOS-widget undo (rules allow parent deletes, `firestore.rules:492-496`, but no screen uses it). Typo'd minutes / wrong-child-selected is permanent and already counted into the wrong child's streak and awards. This will be beta support ticket #1.
- Same-parent double-logging is never warned (the "already logged" notice only fires for a *different* guardian, `log_reading_screen.dart:290`), and a retried quick-log mints a **new doc id** → duplicates that double-count minutes/books.

### 5.3 The Monday-morning ritual is broken
The diary ritual Lumi must replace is "Monday: check who read over the week." But the dashboard's weekly chart is Monday-anchored and **resets that morning** — at 9am Monday it's empty; there is **no "last week" view** anywhere and no persisted weekly snapshot (`dashboard.ts:230-235`, `teacher-dashboard.tsx:80-84`). To see last week, the teacher opens the class report and sets a custom date range. Also, "who hasn't read" exists as three widgets with **three different definitions** (3-day nudge, 7-day at-risk, range-based needs-support) that will contradict each other on the same morning.

### 5.4 Allocations: "weekly" isn't recurring
New allocations are written `isRecurring: false`; a "weekly" cadence just sets an end date 7 days out (`new_allocation_tab.dart:429, 570-586`). The teacher must **re-create allocations every week** (or renew per-student). That's a recurring 10-minute weekly tax the label doesn't advertise.

### 5.5 No-ISBN books break the flagship workflows
The scanner and kiosk react only to detected barcodes — **no manual ISBN entry, no "book without ISBN" path** (`isbn_scanner_screen.dart:168-185`). Levelled readers and decodables — the exact books that go home in K-2 book bags — frequently have no barcode. For those schools the scan/kiosk story collapses into the slower manual by-title flow. Also: **no bulk library import** (`api/books/` has no import route); a school's existing library is entered one book at a time.

### 5.6 There is no book-circulation model at all
No checkout/return, no due dates, no overdue, no lost/damaged, no copy counts — grep finds nothing; the book action sheet is Swap/Keep/Remove (`student_detail_screen.dart:343-399`); the `Book` type has no copies/condition (`school-admin-web/src/lib/types/book.ts`). "Who has which book" is derived from allocations, not physical possession. **Tracking that the reader comes back is half the point of a home-reading system** — right now Lumi cannot answer "which of my 6 copies of *PM Red 4* are still out and who's had one for 3 weeks?"

### 5.7 The kiosk is not a kiosk
- It runs inside the **teacher's fully-authenticated session**; exit is a PIN-less confirm dialog — a child is **two taps from the teacher's entire account** (proxy-logging, awards, parent messaging, student data) (`classroom_kiosk_screen.dart:66-93`). Safety rests on iOS Guided Access, which the app neither enforces, detects, nor documents.
- Kiosk identity is "tap your name" — any child can scan as any other child.
- `TODO(kiosk): real HID scanner connect/disconnect detection` is still in shipping code (`kiosk_scan_session_screen.dart:559`).
- A discovered-by-a-school "kids can get into the teacher account" incident is a **reputational beta-ender** independent of actual harm.

### 5.8 Messaging: pull-only for teachers, void-like for parents
- Teachers get **no push for parent replies** (server explicitly only notifies when `authorRole === "teacher"`; teachers never register FCM tokens — `functions/src/index.ts:2714-2716`). Discovery is a dashboard widget the teacher must keep and check. Conversations will silently stall, and the parent's read of that is "the teacher ignores me."
- Threads are **per-reading-log**, not per-family — no unified inbox; replying across several nights means opening each log's thread.
- **No read receipts surfaced anywhere**: campaign inbox items carry `isRead` but the UI never shows "X of N read" (`communication-page.tsx:176-208`); comment threads never show the parent saw the reply.
- **Nothing tells a parent the teacher saw their child's log.** The diary's weekly signature is evidence of being seen; Lumi has no acknowledgement gesture at all. This is the single biggest *emotional* parity gap with paper — logging into a void kills parent engagement.

---

## 6. Data integrity & fairness — kids and parents will notice

1. **"Books read" is meaningless.** `totalBooksRead` = Σ `bookTitles.length` over logs (`functions/src/index.ts:215`) — one novel read across 10 nights counts as **10 books**; books badges (5/10/25/50/100) are farmable by re-logging. Strictly worse than a diary, where a book finishes once.
2. **Server validation is cosmetic.** `validateReadingLog` flags 1–240-min violations as `validationStatus:'invalid'` — **but aggregators never read that field**; invalid logs still count toward stats and awards (`index.ts:1566-1619` vs `:191`). Rules validate nothing on content — a modified client can write `minutesRead: 99999` and it counts (`firestore.rules:442-449`).
3. **Top Reader = most minutes, no plausibility guard** (`top_reader_award.ts:35-50`). The weekly gold award is decided by the most gameable unguarded number in the system. Expect inflation within weeks — kids compare notes.
4. **Streaks break on real life.** Gap > 2 days resets the streak (`dateUtils.ts:16, 81`) — every school holiday, camp week, and bout of tonsillitis zeroes the visible streak for the whole class. **No term/holiday model exists anywhere.** (Credit: badges key off cumulative nights, `longestStreak` is monotonic, rest-days copy is shame-free — the design intent is right, the calendar-blindness undoes it.)
- Corollary: **Top Reader is crowned every Monday including through holidays**, over near-zero data.
5. **Weekend display quirk:** a Mon–Fri reader's streak displays **0 on Sunday and Monday daytime**, then jumps back after Monday's log — confusing "the app lost my streak" reports incoming.
6. **Edits/deletes leave stats stale until Sunday.** Deleting a log deliberately leaves `lastReadingDate` for the weekly reconciler (`stats_aggregation.ts:273-283`) — a teacher who fixes a wrong log watches the dashboard stay wrong for up to 6 days. The reconciler also caps at 5000 students/run, beyond which drift never self-heals.
7. **The aggregation flag is a raw Firestore doc with no admin UI and no audit trail** — a fat-fingered edit silently changes how all stats are computed.

---

## 7. Coverage blind spots — whole-class participation is the metric schools judge

- **Non-app parents are invisible and unreachable.** Comms delivery is keyed on the parent doc, which only exists after app onboarding; families who never install receive nothing, are excluded from recipient counts, and **nothing tells the teacher a chunk of the class is uncovered** (`functions/src/index.ts:589-799`). No SMS/email fallback for announcements or reminders (SMS exists only for phone verification). The teacher believes they messaged everyone; they didn't.
- **The fallback for non-app families is the teacher proxy-logging every night forever** — through the 25×-taps flow of §5.1.
- **English-only, everywhere.** No i18n in app, portal, or emails (no `.arb`, no l10n framework). EAL/D families — often exactly the families schools most need reading engagement from — are unsupported. (Already flagged as descoped in the parent-UX research; it will bite at whole-class-participation time.)
- **A parent with children at two different schools cannot see both in one account** (`active_child_provider.dart:55-63` — single `schoolId`).
- **Students can never log their own reading.** No student identity exists. Fine for K-2; but upper-primary independence (Year 5/6 kids who own their diary today) has no story, and every log costs an adult's authenticated device.

---

## 8. Reporting — the diary-parity scorecard

| Diary function | Lumi today |
|---|---|
| Tick a column for the class in one pass | ❌ no bulk logging (§5.1) |
| Teacher signs weekly → family knows it was seen | ❌ no acknowledgement gesture (§5.8) |
| Pages / "read to p. 47" | ❌ minutes only — no pages field in the model |
| Reader comes back or gets chased | ❌ no circulation/returns/lost model (§5.6) |
| Hand a parent the child's record at parent-teacher night | ❌ no per-student printable/PDF; on-screen history only |
| Data for report cards / principal | ❌ **no CSV export of reading data anywhere** (import only); class PDF exists but silently caps top-readers/needs-support at 10 rows (`reports.ts:150, 161`); analytics page has no export |
| Zero setup, works during a wifi outage | ❌ see §3, §4 |
| History that survives the bag going through the wash | ✅ Lumi wins |
| Aggregated trends, nudges, streaks, multi-child, comprehension audio | ✅ Lumi wins — paper can't do any of it |

Also: the in-app teacher **Class Reports screen is dev-gated** (`teacher_settings_screen.dart:428-434`) — in the app teachers have *no* reporting at all; everything reporting-shaped lives in the portal, forcing the two-surface juggle.

---

## 9. Lifecycle, staffing, and privacy

- **Relief/substitute teachers have no path.** Adding cover requires an admin to edit `teacherIds` in the portal before the lesson; no temporary/time-boxed role. Casual relief is a *weekly* event in primary schools.
- **Teacher deactivation doesn't cascade** — a deactivated teacher stays on `class.teacherIds` (`users.ts:280`); no class-transfer flow.
- **Class moves half-work:** student moves update rosters, but allocations snapshot `studentIds` and never follow — the moved kid keeps the old class's book assignment and gets none of the new one.
- **Two inconsistent student-delete paths** (portal vs callable) leave different residue; **neither deletes the child's reading logs** — erasure of child data is incomplete (`functions/src/index.ts:2303` vs `students.ts:195`). The callable also leaves stale `class.studentIds`/`studentCount`. Deleting a last-child student deletes the parent's entire Auth account.
- **A departing school cannot export its own data** — export exists only in the super-admin portal and omits parents/comments/achievements.
- **Session hygiene in the staffroom:** the portal cookie is silently re-minted forever from persisted Firebase auth (`auth-context.tsx:60-81`) — on a shared staffroom PC, whoever sits down *is* that teacher; no idle lock, no portal MFA (§3.4).
- **January:** rollover is solid in design (idempotent, opt-in renewals, year-level bumping) but class assignment is fully manual each year, and the 31 Jan hard expiry is a fail-closed cliff timed exactly at AU back-to-school if renewals slip (§3.1).
- Genuinely good privacy answers for a principal: AU region (`lumi-ninc-au`), no ads/tracking, audio retention cleanup, third-party lookups send no student data.

---

## 10. What's genuinely good — do not rip out

- `OfflineService` queue: receipts, backoff, integrity hashes, needs-attention parking — the best reliability code in the repo. It just needs to actually be *in* the main write path (§4).
- Three-layer connectivity probe + Firebase-independent status banner (Cloudflare worker) — right architecture.
- Gentle-streak design intent: rest days, no streak badges, monotonic `longestStreak`, rolling 30/50-day windows, shame-free copy. The research doc's philosophy made it into the code.
- Comprehension as optional async audio the teacher reviews later — pedagogically sane, never gates the log.
- Parent wizard draft-preservation across interruption; multi-child support (the Beanstack wedge); co-parent invites; teacher-proxy logs correctly tagged `loggedByRole` so they don't pollute parent-engagement metrics.
- Student CSV import is genuinely well-built (RFC-4180, header aliases, upsert, auto-class-creation).
- Award automation is near-zero teacher effort; opt-in per class.
- DST-hardened day math (noon-UTC anchors) in `dateUtils.ts`/`access.ts`.

---

## 11. Prioritized punch list

### P0 — before any classroom (mostly small)
1. **Provision access for every beta class** (run `backfill-access.cjs`; seed `config/academicYear`) and build/plan a portal "activate class for this year" action. Fix or hide the misleading "Mark Subscribed" button. (§3.1, §3.3)
2. **Set `timezone` on every school doc**; make it required at school creation; default the functions fallback to `Australia/Sydney`, not London. (§3.2)
3. **Add `.timeout()` + offline-queue fallback to `writeLog`'s interactive path**, and route "healthy-but-hanging" writes into `OfflineService`. (§4.1, §4.3)
4. **Call `clearPersistence()` (or wait for pending writes) on sign-out** to kill the shared-iPad silent-drop. (§4.2)
5. **Kiosk exit PIN** + a one-page Guided Access setup doc for teachers. (§5.7)
6. **Handle `auth/multi-factor-auth-required` in the portal login** (or confirm no beta staff have MFA). (§3.4)
7. **Make aggregators skip `validationStatus:'invalid'` logs** and add minutes bounds to the create rules. (§6.2)
8. **Wire the `minAppVersion` force-update gate** and guard the `main()` init chain with a retry screen. (§3.5, §3.6)

### P1 — before scaling past the pilot (these decide retention)
9. **Bulk/whole-class teacher logging** — roster multi-select, one save. The single highest-leverage teacher feature. (§5.1)
10. **Parent backdate (± a few days) + edit/delete a log** — kills support ticket #1 and the undercounting. (§5.2)
11. **Teacher acknowledgement gesture** (one-tap "seen 👀/⭐" on logs, batched) — the diary-signature replacement, and the parent-retention engine. (§5.8)
12. **Teacher push for parent replies** (staff FCM tokens) + surface read receipts. (§5.8)
13. **"Last week" dashboard view / persisted weekly snapshot** + one consistent "hasn't read" definition. (§5.3)
14. **Recurring allocations** (true auto-renew for weekly cadence). (§5.4)
15. **Per-student printable/PDF + CSV export of reading data**; uncap the class-report lists. (§8)
16. **Term dates model** → streak freezing over holidays, pause Top Reader in holiday weeks. (§6.4)
17. **Fix `totalBooksRead`** (count distinct finished books, or rename the stat). (§6.1)
18. **Manual-ISBN/no-ISBN path in scanner + kiosk**; bulk library import. (§5.5)
19. **Non-app-family visibility**: show the teacher which students have no linked/active parent; per-campaign "not reachable" count. (§7)

### P2 — roadmap / watch during beta
20. Book circulation (checkout/return/lost) — decide deliberately whether Lumi is a diary replacement or a diary+reader-crate replacement; schools will ask in week one. (§5.6)
21. Relief-teacher access model (time-boxed class access). (§9)
22. Unified per-family message inbox. (§5.8)
23. i18n + SMS/email fallback channel (the descoped equity layer — revisit after measuring whole-class participation). (§7)
24. Consolidate the two student-delete paths; delete logs on cascade; school self-serve export. (§9)
25. Token-revocation → re-auth UX; error-message triage (kill the generic strings on the top 10 surfaces). (§4.6, §4.7)
26. Reconcile-budget + aggregation-flag admin UI. (§6.6, §6.7)

### Beta ops checklist (manual, per school, until productized)
- Run `backfill-access.cjs`; verify `config/academicYear`; verify `schoolSubscriptions/{school}_{year}` active.
- Set `timezone` on the school doc; confirm school is in a Sydney-equivalent tz for Top Reader fairness (or accept the boundary skew).
- Ask school IT to allowlist Firebase/Firestore endpoints **and** note the app's connectivity probe uses `1.1.1.1` (§4.5).
- Enable Guided Access on kiosk iPads; document the passcode with the teacher.
- Confirm no beta staff have MFA enabled until the portal handles it.
- Pre-agree the "wrong log" fix path (teacher/portal delete) since parents can't self-fix.
- Crashlytics + a feedback channel wired before day one (per `PUBLIC_BETA_PLAN.md` §3).

---

## 12. Unknown-unknowns — classroom events vs what Lumi does today

| Real classroom event | What happens in Lumi right now |
|---|---|
| Relief teacher walks in Monday 8:40am | No access path; admin must edit `teacherIds` in the portal first; kiosk dies if the regular teacher's session isn't live |
| Whole class logs/scans at 9am | Stats trigger backlog (`concurrency:1`) → dashboard widgets disagree; "hasn't read" flags kids who just read |
| School wifi drops mid-save | Spinner hangs forever (no timeout); or success shows while the write sits in local cache |
| iPad trolley: next teacher signs in | Previous teacher's pending writes silently dropped |
| Child taps Exit on the kiosk | Two taps to the teacher's full account (no PIN) |
| Levelled reader with no barcode | Scanner/kiosk unusable; manual by-title flow only |
| Reader never comes back | Untracked — no returns/lost model |
| Kid sick for a week / school camp / term break | Streak resets to 0; Top Reader still crowned for the empty week |
| Parent logs Thursday for Mon–Wed reading | Impossible — collapses to one Thursday log, undercounts |
| Parent logs on the wrong child | Permanent; already counted; teacher must delete via rules-only path (no parent UI) |
| Parent messages the teacher | No push to teacher; sits in a dashboard widget until noticed |
| Teacher messages the class | Non-app families silently excluded; no read receipts; teacher assumes delivered |
| Parent-teacher night | No per-student printout; screen-share the history section |
| Principal asks "how's it going, show me data" | Class PDF only (capped at 10 rows/list); no analytics export, teachers can't see analytics at all |
| Report-card season | No CSV/export of reading data |
| Student moves from 3A to 3B in week 3 | Roster updates; old class's allocation follows them; new class's doesn't |
| School didn't finish renewals by Jan 31 | Every parent locked out at back-to-school (fail-closed hard expiry) |
| Staffroom shared PC | Portal session re-mints forever; anyone at the keyboard is that teacher |
| EAL/D family | English-only app, portal, emails |
| Family with no smartphone | Teacher proxy-logs them by hand, one at a time, forever |
| Kid discovers Top Reader = most minutes | Inflated minutes win gold; no plausibility guard; invalid-flagged logs still count |

---

*Compiled 2026-07-06 from five parallel code audits. File references are to the working tree at commit `a6d1bc9`.*
