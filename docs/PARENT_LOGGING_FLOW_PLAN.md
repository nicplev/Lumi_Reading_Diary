# Parent/Guardian Logging Flow — Implementation Plan & UI/UX Spec

**Status:** APPROVED v2 — Open Decisions answered by Nic 2026-07-24 (§9); Phase 0 skipped, implementation in progress
**Date:** 2026-07-24
**Inputs:** Persona simulation findings (Mia / Alex & Jordan / Riley), 4-agent codebase audit (2026-07-24), `docs/parent-ux-research.md`, `docs/CLASSROOM_BETA_READINESS_REVIEW.md` §5.2, `docs/LUMI_SCALE_TEST_PLAN.md`, `functions/test/reading_log_rush.integration.test.js`
**Convention:** Claude keeps the workstream status tables and the change log at the bottom current as PRs merge, same as `docs/ST4S_REMEDIATION_PLAN_2026-07-22.md`.

---

## 1. Non-negotiable principles (from the persona findings)

1. The green tick must not behave or look like a reversible checkbox.
2. The action must state exactly what will be saved.
3. Undo targets one exact session (by log ID), never the child's whole day.
4. Recovery stays available after any temporary confirmation disappears.
5. The app never silently guesses a book, duration, child, or date.

Plus three structural invariants:

- **Layout stability** — logging one child never moves or resizes another child's row, and never relocates an untouched control.
- **Ownership & provenance** — every session says who recorded it; only its creator can change it.
- **No silent conflict resolution** — concurrent or offline duplicates are surfaced and resolved by the guardian, never merged/discarded automatically.

---

## 2. Current-state audit (what the code does today)

### 2.1 What already works (build on, don't rebuild)

| Capability | Where | Notes |
|---|---|---|
| Client-generated 128-bit hex log ID as idempotency key | `reading_log_service.dart:95-100`, offline replay pre-check `offline_service.dart:1098-1124` | Retries re-`set()` the same doc; rules reject reconstructed replays (`createdAt == request.time`). Verified by `functions/test/reading_log_rush.integration.test.js`. **This ID is our "mutation ID" — no new mechanism needed.** |
| Hive outbox with priority, backoff, server read-back receipts | `offline_service.dart:849-963, 1142-1146` | Reading-log create is priority 0; permanent-vs-transient error classification exists. |
| Fail-closed access entitlement on log **create** | `firestore.rules:134-138, 892-894` (`studentAccessLive`) | Missing/expired `access` ⇒ denied. Not yet re-checked on update/delete (§5.3). |
| Ownership rules | `firestore.rules:914-921, 951-955` | Content edits and deletes require `resource.data.parentId == request.auth.uid` (or staff). A co-guardian already cannot touch the other guardian's log. |
| Stats handle deletes and edits in both aggregation modes | `stats_aggregation.ts:342-383, 476-509`; regression test `stats_concurrency.integration.test.js:150-192` | Delete decrements minutes/books, recomputes `lastReadingDate`, floors at 0. Weekly reconciler self-heals. |
| `loggedByRole ∈ {parent, teacher}` + denormalised `loggedByName/Label` | `reading_log_model.dart`, `firestore.rules:744-745` | Provenance display already exists in history ("Logged by …"). |
| School-TZ date math (server) | `functions/src/dateUtils.ts` (`localDateString`, `localDateUtcRange`, term-date holiday logic) | Pure, unit-tested, DST-correct. Port to Dart, don't reinvent. |
| Cross-guardian "already logged" notice (informational) | `log_reading_screen.dart:295-321` | Non-blocking banner; keep as the detailed-flow companion to the new slot. |
| Cascade deletion patterns to reuse | `functions/src/deletion.ts:221-239` (`deleteReadingLog`: audio ×2 + AI eval artifacts + `recursiveDelete` comments) | Exists only in the whole-student pipeline today. |
| platformConfig kill-switch pattern | `stats_aggregation.ts:64-101`, client `platform_config_service.dart:28` | Use for `parentQuickLogV2`. |

### 2.2 Gaps, mapped persona issue → code

| # | Persona requirement | Current reality | Ref |
|---|---|---|---|
| G1 | Labelled action, not a checkbox | Multi-child rows use `_LogCircle`: an unlabelled 44×44 hollow-ring→spinner→filled-green-check | `parent_home_screen.dart:2010-2064` |
| G2 | Undo one exact session | No parent-facing undo at all; only the legacy iOS-widget `WidgetUndoBanner` (normally renders nothing since #312) | `widget_undo_banner.dart` |
| G3 | Durable edit/remove | **No edit UI exists**; session detail sheet is read-only; no delete outside the widget path. Readiness review predicted this as "beta support ticket #1" | `session_detail_sheet.dart`; review §5.2 |
| G4 | Never fabricate a book | Quick log with no assignment writes `bookTitles: ['Reading']`; with assignments it writes the **union of every assigned title** | `reading_log_service.dart:721-748` |
| G5 | Query order must never choose book/duration | Title and `targetMinutes` come from `allocations.first` | `reading_log_service.dart:121-123`, `parent_home_screen.dart:975-990` |
| G6 | School-local dates, rollover, Yesterday | `date: DateTime.now()` (device TZ), no client school-TZ utility, no midnight rollover timer, no backdating. Client `SchoolModel.timezone` even defaults to `'UTC'` while the server defaults to `Australia/Sydney` | `reading_log_service.dart:120,135`; `school_model.dart:32`; `access.ts:16` |
| G7 | Canonical home-quick slot | None. Same-guardian double-tap is only guarded by transient widget state; two guardians can both create the default session; the co-parent notice is informational only | `parent_home_screen.dart:1855` |
| G8 | Home vs classroom context | No `context` field. Teacher proxy logs count identically toward streaks/stats and would flip the Home row to "all done" | `stats_aggregation.ts:119-133` |
| G9 | Removal must clean dependents | Plain log delete orphans the comments subcollection, both Storage audio objects, `comprehensionEvals/{logId}` and `aiEvalJobs/…` — there is **no `onDocumentDeleted` trigger for readingLogs** | audit Q5 |
| G10 | Revocation blocks queued/historical writes | Rules re-check access on **create only**, not update/delete; no child-scoped cache purge on unlink/sign-out | `firestore.rules:914-955` |
| G11 | Accessibility as definition, not polish | Two `Semantics` usages in all parent flows; no Reduce Motion handling (unconditional `flutter_animate` chains + confetti); no text-scale accommodation; several sub-44pt targets (32–36pt) | UI audit §7 |
| G12 | Offline pending must be explicit per-row | Global `ServiceStatusBanner` + Offline & Sync page exist, but the child row itself never shows pending/conflict state | `service_status_banner.dart` |

---

## 3. Home screen UX spec

### 3.1 Row anatomy (applies to `_TonightRow` rows and the single-child `_TodayCard` quick-log region — one shared component, two densities)

```
┌────────────────────────────────────────────────────────────────┐
│ (avatar)  Lincoln                              ┌─────────────┐ │
│           The Bad Guys · usual 15 min          │ Log 15 min  │ │
│           ─ status/action line ─               └─────────────┘ │
└────────────────────────────────────────────────────────────────┘
   row body = opens detailed flow        trailing slot = fixed-width
                                         labelled button OR static
                                         summary chip (never both roles)
```

- **Keys & order:** each row `ValueKey(childId)`. Order = the parent doc's `linkedChildren` array order (today's behaviour — already stable). Ordering is computed once per build from that array and **never** re-sorted by logged state. Widget test locks this in.
- **Height stability:** the row always reserves two text lines (name + status line) and the trailing slot. State changes replace the *content* of the status line and trailing slot; nothing is inserted or removed. (Height may differ *across* text-scale settings — see §3.6 — but never *within* one.)
- **Trailing slot:** fixed width (~128pt regular density), min 44pt height, always a **labelled** control or a static chip. Never a bare icon, never a check-circle.
- **Row body tap** always opens the detailed flow (unchanged behaviour), with `Semantics` separated from the trailing action (§3.6).

### 3.2 Row state machine (child-keyed; single source of truth)

State is derived per child from: today's home-context sessions stream (school-local day, §6) + outbox pending entries + slot doc + allocations/current book + guardian prefs + access.

| State | Status line | Trailing slot | Behaviour |
|---|---|---|---|
| **Ready** | `The Bad Guys · usual 15 min` (multiple assigned: `The Bad Guys +1 more · usual 15 min`) | `[ Log 15 min ]` | Tap → §3.3 submit. Body opens detailed flow. Multiple assigned books log as the union (D3). |
| **Needs book** | `No current book` | `[ Choose book ]` | Opens picker (§4). **No write happens.** After choosing/pinning, returns to Ready. |
| **Submitting** | `Logging…` | `[ Logging… ]` disabled | Locked synchronously on tap, before any async. Row body inert too (cannot open a second flow). |
| **Offline pending** | `Saved on this phone · not yet shared` | `[ Review ]` | Review sheet shows the pending entry with `Edit pending` / `Cancel pending` (§7.2). |
| **Just created by me** | `15 min logged · The Bad Guys` + inline text buttons `Undo my quick log · Edit this log` | `15 min ✓-less static chip` (non-interactive) | Undo/Edit live on the status line, **away from the trailing rect** (§3.3). |
| **Logged by someone else** | `20 min logged by Jordan` | `[ Review ]` | View-only detail; **no Undo anywhere**. |
| **Multiple sessions** | `2 sessions · 35 min` | `[ Review sessions ]` | Opens Today's sessions sheet (§5.1). Aggregate state never exposes Undo. |
| **Classroom only** | `Read at school today · 15 min` | `[ Log 15 min ]` | Classroom sessions display but do **not** satisfy the home slot; home quick log stays available. |
| **Conflict / error** | `Needs review` | `[ Resolve ]` (or `[ Retry ]` for transient errors) | Opens the conflict prompt (§7.3) or retries the same log ID. |
| **Access unavailable** | `Logging is paused — contact your school office` (neutral grey) | *(empty)* | No affordance, no local write. Suspended-school variant reuses `AccessGateReason` copy. |
| **Quick log disabled by school** | `The Bad Guys` | *(empty; body still opens detailed flow)* | Existing `school.settings.quickLogging.enabled` gate; the row never dangles a dead button. |

### 3.3 Tap → save lifecycle (the trust-critical path)

1. **On tap:** synchronously set `Submitting` (button + row inert), generate the log ID (`generateLogId()` — this *is* the mutation ID), snapshot the exact payload the button described: child, resolved book set (§4.1), minutes, `occurredOn` (school-local today), context `home`.
2. **Write:** one `WriteBatch` = log create + slot create (§6.2). 15s ack timeout → falls through to the offline queue as one atomic pending unit (row → Offline pending).
3. **On receipt:** row → **Just created by me**. The trailing slot becomes a *static* summary chip — the button's screen region is inert for the rest of this state, so a rapid second tap on the same spot does nothing. `Undo my quick log` renders on the status line, ≥8pt from the former button rect. **Never morph the button into Undo in place.**
4. **Slot taken (batch rejected):** row → **Logged by someone else** with a transient notice: `Jordan logged 20 min moments ago. No new session was added.` Actions: `Review` · `Add another session` (creates a fresh non-slot session). The loser's tap must produce **zero** writes.
5. **Undo my quick log:** confirmation-free; batch-deletes exactly `{logId, slot}`; announces `Log removed`; row → Ready. Available while the state holds (until day rollover or a second session appears); after that, recovery moves to the durable path (§5).
6. **Preview = payload:** the string on the button and status line is rendered from the same snapshot struct that is serialised into the write. One code path, asserted in a widget test (no "says 15, saves 20" drift possible).

### 3.4 Single-child `_TodayCard`

Same state machine, larger canvas:

- Primary `Log reading` button → detailed flow (unchanged).
- Secondary quick action becomes the same labelled component: `Quick log 15 min — The Bad Guys` (the existing helper caption `Quick log records …` is absorbed into the label; keep the caption at smaller sizes).
- Post-save: `Lincoln — all done!` block stays, gains `Undo my quick log` and `Edit this log`; `Add another session` keeps its current meaning (a genuinely separate entry) — **rename audit:** nothing on this screen may read "Add details" for an existing session; post-save additive actions on the success screen (feeling/comment/recording) re-label to `Edit this log`.

### 3.5 Copy inventory (hardcoded literals today; keep literals, centralise the new flow's strings in one `parent_logging_copy.dart` so QA can diff copy in one place)

| Key | String |
|---|---|
| ready.status | `{book} · usual {n} min` |
| ready.status.multi | `{book} +{k} more · usual {n} min` |
| ready.status.goal | `School goal: {n} min · {book}` (when guardian usual ≠ allocation target, show both: usual on the button, goal in the status line) |
| ready.action | `Log {n} min` |
| needsBook.status | `No current book` |
| needsBook.action | `Choose book` |
| submitting | `Logging…` |
| pending.status | `Saved on this phone · not yet shared` |
| created.status | `{n} min logged · {book}` |
| created.undo | `Undo my quick log` |
| created.edit | `Edit this log` |
| other.status | `{n} min logged by {name}` |
| multi.status | `{k} sessions · {n} min` |
| multi.action | `Review sessions` |
| classroom.status | `Read at school today · {n} min` |
| conflict.status | `Needs review` |
| slotLost.notice | `{name} logged {n} min moments ago. No new session was added.` |
| undo.done | `Log removed` |
| remove.lastSession.warn | `This is {child}'s only reading tonight. Removing it will change minutes, reading-night progress and may change the streak.` |
| dateMismatch.note | `Saving as {weekday d MMM} (school time)` |

### 3.6 Accessibility (part of the definition of done for every Phase-1 PR)

- **Semantics:** row body = one `MergeSemantics` node: `"Lincoln, The Bad Guys, usual 15 minutes. Opens reading details."` Trailing action = a separate `Semantics(button: true)` node: `"Quick log 15 minutes for Lincoln, The Bad Guys."` Logged: `"Lincoln, reading recorded, two sessions, review."` No overlapping/nested tap semantics.
- **Announce once, move focus:** on save, `SemanticsService.announce('Saved 15 minutes for Lincoln')`; focus moves to the confirmation (the status line node). Undo announces `Log removed`.
- **Targets:** every interactive element ≥44×44pt — includes the status-line Undo/Edit text buttons (padded hit areas) and fixes the existing 32/36pt steppers and banner buttons touched by this work.
- **Not colour-alone:** every state pairs colour with words. The filled-green-check-as-sole-signal pattern is retired.
- **Text scale:** no fixed row heights; at large accessibility sizes the trailing action wraps to a full-width line *below* the status line (same order for every row, decided by text-scale bucket, not by logging state — so stability is preserved). Nothing (child, duration, title, Review, Undo) is ever elided at max scale. Widget-test at `textScaler: 2.0`.
- **Reduce Motion:** gate all `flutter_animate` chains, confetti, and the milestone shake behind `MediaQuery.disableAnimations` via a small `context.motionAllowed` helper (pattern exists in `login_screen.dart:1449`; parent flows currently ignore it).
- **Caches:** current/recent-book caches and drafts are child-scoped in Hive and purged on sign-out and on child unlink/access revocation (§7.4).

---

## 4. Book resolution & picker

### 4.1 Resolution rules (updated per D3: union behaviour retained)

- **Quick log requires at least one explicitly resolved book.** Resolution order: the union of effective assigned books across active allocations (`effectiveAssignmentItemsForStudent`, deduped — current behaviour, kept per D3) → else the guardian-pinned current book → otherwise the row shows `Choose book`. `allocations.first` is never used as a *duration* tiebreak (§6.4 governs duration).
- **The `['Reading']` fabrication is deleted** (`_resolveBookTitles` fallback). No generic title string is ever persisted, from any path.
- **Union display honesty:** when the union has >1 title the status line says so (`The Bad Guys +1 more`) and the review/success surfaces list every credited title — the action still states exactly what will be saved.
- **Pinning:** a guardian may set a current book for a child independent of school allocation (free-choice reader, library book, comic, audiobook). Stored per guardian×child (§6.4); pinning never writes a session.
- **Unresolved title (detailed flow only):** `Title not known — add later` produces `bookTitles: []` + `titleUnresolved: true` — a structured state, never a placeholder string. Unresolved sessions count minutes/streaks but are excluded from books-completed analytics (automatic: empty `bookTitles` contributes 0 to `totalBooksRead`). The session row shows `Title to add` with an inline resolve affordance.

### 4.2 Picker (bottom sheet; used by `Choose book`, the detailed flow, and pinning)

```
┌──────────────────────────────────────┐
│ Choose a book for Lincoln            │
│ CURRENT   ◉ The Bad Guys   Assigned  │
│ RECENT    ○ Dog Man        Logged    │
│           ○ Zog                      │
│           ○ WeirDo         Assigned  │
│ ─ Search or add a title ──────────── │
│ [ 🔍 type a title…            ]      │
│ ( Title not known — add later )      │  ← detailed flow only
└──────────────────────────────────────┘
```

- Order: current/pinned → three recents → assigned → search/manual. One list, deduped by case-insensitive title; a single entry carries source badges (`Assigned` / `Logged` / `Pinned`) rather than appearing twice.
- **Manual entry auto-commit:** keyboard `Done` already commits (`onSubmitted: _addCustomBook`) — extend so that pressing the flow's primary button (`Continue` / `Save reading log`) with un-committed text in the field commits it first. The red `+` becomes optional, never required. Widget test: typed-but-not-plussed text is retained.
- Removing a recent suggestion edits only the recents cache, never historical sessions.
- Recents source: last N distinct titles from this child's sessions (any guardian), cached child-scoped in Hive.
- **Format** (`print / ebook / audiobook / read-aloud`) is a separate chip on the entry, stored per book entry, not part of the title (Phase 2, §6.1 `books[]`).
- Multi-book detailed sessions: allowed; **duration remains the session total** (already true — stats count `minutesRead` once per log; locked by an acceptance test).

---

## 5. Review, edit, remove (durable recovery layer)

### 5.1 Today's sessions sheet (from `Review` / `Review sessions` / history rows)

```
┌──────────────────────────────────────────────┐
│ Tonight — Thursday 24 July (school time)     │
│ ● 15 min · The Bad Guys                      │
│   Logged by you · 7:42 pm                    │
│   [ Edit this log ]  [ Remove my session ]   │
│ ● 20 min · Zog                               │
│   Logged by Jordan · 6:03 pm      (view)     │
│ ● 15 min · class reading with Ms Lee (view)  │
│ ( + Add another session )                    │
└──────────────────────────────────────────────┘
```

- Owner-scoped: `Edit this log` / `Remove my session` render only when `session.parentId == myUid` (mirrors the existing rules — no rules change needed for edit). Other-guardian and teacher records are view-only; a correction-request route is Phase 3.
- `Assigned by Ms Lee` (allocation) and `Logged by Jordan` (session provenance) stay visually distinct concepts.

### 5.2 Edit this log

- Editable: minutes, books, notes, feeling, parent comments — exactly the field set `contentUpdateIsValid` already allows (`firestore.rules:748-775`). **Date is not editable** (not in the allowed set; keeps accountability and avoids cross-day stats surgery). Wrong-day fix = remove + re-log.
- Stats react automatically (both aggregation modes diff before/after).
- Edited sessions carry `editedAt` display (`Edited 8:01 pm`) — Phase 2 provenance polish.
- Editing a session never changes the guardian's usual duration; after 3 consecutive same-value divergences the app may *ask*: `Make 15 minutes Lincoln's usual quick-log time?` (§6.4).

### 5.3 Remove my session

- Removing one of ≥2 sessions: light confirm.
- Removing the only qualifying session: warning copy `remove.lastSession.warn` (§3.5) before delete.
- Delete = client deletes the log doc (+ slot doc if it holds the slot); the **new `onReadingLogDeleted` trigger** (§6.3) guarantees dependent cleanup for *every* delete path (app, widget-undo, portal/admin): comments subcollection, both Storage audio objects, `comprehensionEvals/{logId}`, `aiEvalJobs/{schoolId}_{logId}`, and any slot doc pointing at the log. All idempotent (safe under the student-cascade path which pre-cleans).
- System Back / `Done` only navigate — no implicit reversal anywhere in the flow.

---

## 6. Data model & backend design

### 6.1 `readingLogs` schema additions (all **optional** in rules until app adoption saturates — `createSchemaIsValid` uses `hasAll`, so a new *required* field would brick old clients)

| Field | Type | Meaning |
|---|---|---|
| `occurredOn` | string `YYYY-MM-DD` | School-local occurrence date, stamped client-side at tap time. Canonical stats bucketing key when present (fallback: derive from `date` + school TZ, current behaviour). Preserves the offline-before-midnight day. |
| `context` | `'home' \| 'classroom'` | Missing ⇒ `home` (all legacy parent logs; legacy teacher proxies were home-reading proxies per #39). Classroom sessions never satisfy the home slot or flip the Home row. |
| `titleUnresolved` | bool | Structured "title not known" state; only valid with `bookTitles: []`. |
| `editedAt` | timestamp | Set on content updates (Phase 2 provenance). |
| `books` | array of `{title, bookId?, source: assigned\|library\|manual\|pinned, format: print\|ebook\|audiobook\|readAloud}` | Phase 2. `bookTitles` stays as the denormalised/back-compat projection; stats keep counting from `bookTitles`. |

The log **ID remains the mutation ID** (client-generated, retained across retries) — unchanged.

### 6.2 Canonical home-quick slot

- **Path:** `schools/{schoolId}/students/{studentId}/quickSlots/{occurredOn}` (e.g. `…/quickSlots/2026-07-24`). Subcollection under the student so `recursiveDelete(studentRef)` in the deletion pipeline cleans it for free.
- **Fields:** `{ logId, byUid, createdAt }` only — no denormalised minutes/title (the reader fetches the log; nothing to go stale after edits).
- **Write:** quick log = one `WriteBatch`: log create + slot create. If the slot exists, the whole batch is rejected → the loser created **nothing** (exactly the persona requirement). First atomic write wins.
- **Rules:**
  - `create`: signed-in ∧ `writeAllowedForSchoolContent` ∧ (`byUid == request.auth.uid`) ∧ `createdAt == request.time` ∧ `getAfter(...readingLogs/$(logId))` exists in the same batch with `parentId == request.auth.uid` (or the teacher branch) ∧ `context != 'classroom'`. No update.
  - `delete`: `resource.data.byUid == request.auth.uid` (undo/remove) or school admin.
  - `read`: linked guardians of the student + staff of the class/school.
- **What the slot governs:** only the *default home quick session* dedupe. It does **not** gate `Add another session`, does not feed streaks, and classroom logs never touch it. A teacher explicitly logging *home* reading on behalf of the child claims it like a guardian would.
- **Transition:** old app versions don't write slots, so during rollout the slot only arbitrates between updated clients; the existing informational co-parent banner remains the backstop. Acceptable and self-resolving.

### 6.3 Functions changes

| Change | File | Notes |
|---|---|---|
| **New** `onReadingLogDeleted` cascade | new `functions/src/reading_log_cleanup.ts` | Reuse `deletion.ts` helpers: `deleteStorageFile` ×2 audio paths, `deleteAiEvalArtifacts`, `recursiveDelete` comments, delete matching quickSlot. Idempotent; skip-guard when the student-cascade (`pendingDeletion`) already ran. **Closes G9 for the *existing* widget-undo path too.** |
| Stats bucketing honours `occurredOn` | `stats_aggregation.ts` (`extractCountedFields`), `index.ts` legacy path, `class_daily_reading.ts` | `occurredOn ?? localDateString(date, tz)`. Reconciler + `streak_refresh` unchanged (they operate on the derived `readingDates` set). |
| `validateReadingLog` consistency checks | `index.ts:2150` | `occurredOn` must equal school-local-day(`date`) or that day − 1 (Yesterday backdating window); flag `context`/`titleUnresolved` misuse; telemetry counter for any legacy `'Reading'` title still arriving (measures old-client tail). |
| (Later, post-adoption hardening) rules require `occurredOn`+`context`; quick-log creates require `bookTitles.size() >= 1 \|\| titleUnresolved == true` (no empty/fabricated titles) | `firestore.rules` | Same coordination pattern as prod-hardening 1.3/1.6 — needs app-release saturation first. |

Streak semantics are **unchanged in Phase 1** (teacher/classroom logs keep counting toward streaks — Open Decision D2); only the *Home row/slot* distinguishes context.

### 6.4 Guardian×child preferences

- **Path:** `schools/{schoolId}/parents/{parentId}.preferences.quickLog.{studentId} = { usualMinutes, pinnedBook: {title, bookId?, format?}, updatedAt }` — rides the existing `UserModel.preferences` map and its existing write path/rules; separated households naturally diverge because it's keyed by guardian.
- Display: button shows the guardian's usual; status line shows `School goal: 20 min · The Bad Guys` when allocation target ≠ usual. Teacher target and parent-reported actual time are never conflated.
- Never changed silently: only via the explicit `Make {n} minutes {child}'s usual quick-log time?` prompt (after 3 consecutive divergent sessions) or a settings row.

### 6.5 Dates & school time (client)

- New `lib/core/utils/school_time.dart`: Dart port of `localDateString` / `localDateUtcRange` / next-school-midnight (use the already-bundled `timezone` package; `tz.initializeTimeZones()` already runs). Fix `SchoolModel.timezone` default `'UTC'` → `'Australia/Sydney'` to match `access.ts:16`.
- A `schoolTodayProvider` recomputes on a timer armed for the next school-local midnight → Home queries, row states, and the slot date roll over without an app restart.
- Quick log: always Today (school time), and *says* so when device date ≠ school date (`dateMismatch.note`).
- Detailed flow: `Today / Yesterday` segmented control (default Today) — the **only** backdating window (D1: approved). Rules already allow it (`date` window is −366d..+1d; the constraint was purely client-side).
- **Backdating kill-switch (D1 condition):** the Yesterday option is gated on `platformConfig/parentBackdating` (absent ⇒ enabled, house convention) from the day it ships, so it can be turned off without an app release based on real-school evidence. **Follow-up for Nic:** add the on/off toggle to the super-admin portal Operations section (client + flag doc will already honour it) — reminder due when this plan's phases complete.
- Today-stream: keep the timestamp-range query but compute the range with `localDateUtcRange(schoolToday)`, and bucket client-side by `occurredOn ?? derived` so legacy same-day logs from an old-client co-parent still appear during transition.
- Index check before merge: review sheet query (`studentId ==`, `occurredOn ==`, orderBy `createdAt`) likely needs a composite — follow the dump-remote-first rule (`firebase firestore:indexes` → merge into `firestore.indexes.json`) so the deploy can't drop stray indexes.

### 6.6 Rules changes summary (`firestore.rules`)

1. `quickSlots` block (§6.2).
2. Extend `createSchemaIsValid` `hasOnly` with the new optional fields; extend `metadata.keys().hasOnly(['quickLog'])` if any metadata key is added (prefer top-level fields; the `hasOnly` pin is why).
3. **Access re-check on mutation (G10):** add `studentAccessLive(...)` to the content-update rule and the delete rule, so a formerly linked or lapsed guardian cannot modify/remove queued-or-historical data after revocation. (Security-review P0 alignment.) Watch the rules expression budget — the scale plan flags parent update rules near the 1000-expression ceiling; the rush test + `load-tests/` cover regression.
4. `contentUpdateIsValid` gains `titleUnresolved`, `editedAt`, (Phase 2) `books` in its allowed-fields list; `date`/`occurredOn` deliberately stay immutable.

### 6.7 Rollout & deploy order

1. **PR-A (rules)** deploy `firestore:rules` — additive, old clients unaffected. Must land **before** any app build that writes slots.
2. **PR-B (functions)** deploy functions — cascade + bucketing are backward-compatible. Predeploy lint gate applies; post-deploy `./scripts/audit-function-health.sh` runs via hook.
3. **App PRs** ride the next release train. Client kill-switch: `platformConfig/parentQuickLogV2` (absent ⇒ enabled, house convention); when off, the app falls back to the pre-existing row widget and skips slot writes for one release cycle of insurance.
4. Post-adoption hardening PR (rules tightening) — separate, later, coordinated like prod-hardening 1.3/1.6.

---

## 7. Offline, conflicts, and revocation

### 7.1 Pending state (explicit, per row)

- The quick-log batch enqueues as **one atomic outbox unit** (new `SyncType.quickLog`: log + slot replayed in a single `WriteBatch`), keeping the existing receipt/read-back pattern. Row shows **Offline pending** from the outbox, not from Firestore snapshot metadata (the codebase deliberately doesn't use `hasPendingWrites`).
- `Edit pending` mutates the outbox payload in place (same log ID). `Cancel pending` deletes the outbox entry + local optimistic record — nothing ever reaches the server.
- An offline log made before midnight keeps its stamped `occurredOn` after syncing (G6 closed by construction).

### 7.2 Replay & conflict on reconnect

Outbox drain, per pending quick log:

1. Log doc already on server (receipt) → dequeue, done (existing behaviour).
2. Slot free → replay batch → row becomes Just created by me (or Multiple).
3. Slot taken by **another guardian** → do **not** write. Row → Conflict; prompt:
   - `Jordan logged reading while you were offline. Was yours the same session?`
   - `[ Same session — discard mine ]` → drop outbox entry, no write.
   - `[ Different session — add mine ]` → replay the log create **without** the slot (a genuinely separate session).
4. Slot taken by **my own uid** (my other device) → same prompt with copy `You already logged {n} min for {child} on another device.`
5. Never: silent overwrite, silent merge, silent discard, or double-count.

### 7.3 Errors

- Transient (timeout/unavailable): existing backoff; row stays Pending.
- `permission-denied` on replay (access revoked while queued): stop retrying (existing permanent-classification), row → Access unavailable, pending entry surfaced in Offline & Sync with `Logging is paused…` explanation. The server-side rules re-check (§6.6-3) is the authority; the client honours it instead of fighting it.

### 7.4 Revocation & cache hygiene

- On sign-out, child unlink, or `access.isActive` flipping false: purge that child's Hive-cached logs, drafts, recents, pinned book, and drop that child's queued outbox entries (they would be rules-rejected anyway; don't leave PII in the queue).
- Quick-log enqueue is also gated client-side on `student.hasActiveAccess` (no local write that could later bypass revoked access).

---

## 8. Delivery plan

### Phase 0 — Spec & prototype (this doc + prototype)

| # | Item | Status |
|---|---|---|
| 0.1 | Product sign-off on §9 Open Decisions | ✅ 2026-07-24 (see §9 resolutions) |
| 0.2 | Clickable prototype of the row state machine | ⏭️ SKIPPED per Nic — straight to Phase 1 |
| 0.3 | Test with 5–8 real parents across the three household types | ⏭️ Deferred to TestFlight builds during first-round school testing |

### Phase 1 — P0 trust & correctness (PR-sized workstreams)

| PR | Scope | Key files | Deploy | Status |
|---|---|---|---|---|
| A | Rules: `quickSlots`, optional log fields, access re-check on update/delete; rules tests incl. slot contention (two guardians, one slot, loser writes nothing) in a **new** test file (`reading_log_rush.integration.test.js` is uncommitted work from a concurrent session — do not touch it) | `firestore.rules`, `functions/test/firestore.rules.test.js`, new `functions/test/quick_slot.rules.test.js` | `firestore:rules` (manual, prod-confirm) | ✅ **#555** merged 2026-07-24; 196 rules tests green; live prod ruleset verified pre-slot (created 08:38 AEST, #520 content) — deploy still pending |
| B | Functions: `onReadingLogDeleted` cascade (+slot cleanup), `occurredOn` bucketing (stats/summaries/feelings/award/reminders + bucket-aware drop-probe), `validateReadingLog` occurredOn window ±1d + legacy-title telemetry | new `reading_log_cleanup.ts` + `reading_log_cleanup.integration.test.js`, `stats_aggregation.ts`, `class_daily_reading.ts`, `student_view_aggregates.ts`, `top_reader_award.ts`, `dateUtils.ts`, `deletion.ts` (helper exports), `index.ts` | `functions` (manual; health-audit hook) | ✅ **#558** merged 2026-07-24; 260 unit + 9 integration tests green — deploy pending |
| C | Client foundation: `school_time.dart` (Dart port of dateUtils.ts) + TZ default fix (`'UTC'`→`'Australia/Sydney'`) + `schoolTodayProvider` rollover; `ReadingLogService` — `'Reading'` fallback killed (union kept per D3; empty ⇒ `NoCurrentBookException`), `occurredOn`/`context` stamping, slot pre-check + atomic batch, `QuickSlotTakenException` w/ winner info, `StudentAccessInactiveException` guard, `deleteOwnLog` (frees held slot); `OfflineService` — `claimQuickSlot` payload flag, atomic batch replay, `QuickSlotConflictException` parking + `resolveQuickSlotConflict` (discard/keep-mine), `enqueueReadingLogDelete` (queued-create cancellation), `purgeChildData` | `reading_log_service.dart`, `offline_service.dart`, `reading_log_model.dart`, `school_model.dart`, new `core/utils/school_time.dart`, new `data/providers/school_time_provider.dart` | app release | ✅ merged 2026-07-24; 25 + 40 client tests green |
| D | Home rows: `ChildLogRow` + pure `deriveChildLogRowState` state machine (11 states) replacing `_LogCircle`; labelled `Log N min` button; constant-height status strip (no-morph undo, §3.3); `ValueKey(childId)` rows; school-today query window (occurredOn-bucketed, ±1d, midnight rollover via `schoolTodayProvider`); `_TodayCard` gains Choose-book affordance + post-save `Undo my quick log`; `parent_logging_copy.dart` copy file; a11y: Merge/separate semantics, `sendAnnouncement` on save/undo, ≥44pt, Reduce Motion gate (`context.motionAllowed`), 2.0-scale reflow | `parent_home_screen.dart`, new `widgets/child_log_row.dart` + `parent_logging_copy.dart` + `core/utils/motion.dart`, `school_settings_provider.dart` (`schoolTimezoneProvider`), `test/screens/parent/child_log_row_test.dart` | app release | ✅ merged 2026-07-24; 19 new widget tests; suite 625/625 |
| E | Tonight's-sessions review sheet (Row `Review` action; provenance rows, owner-scoped Edit/Remove, Add another session), owner Edit sheet (contentUpdate field set; date immutable + explains why; §4.2 auto-commit; 44pt steppers; offline ⇒ "reconnect to edit"), Remove with last-qualifying-session warning (via `countHomeSessionsOn`), owner actions on history's session detail sheet; `updateOwnLog` service primitive stamping `editedAt`. Success-screen rework confirmed Phase 2 (no "Add details" literal exists to relabel). | new `widgets/today_sessions_sheet.dart` + `widgets/edit_reading_log_sheet.dart`, `session_detail_sheet.dart`, `reading_log_service.dart`, `offline_service.dart` (`saveReadingLogCacheOnly`), `parent_home_screen.dart` | app release | ✅ merged 2026-07-24; +7 tests; suite 632/632 |
| F | Offline UX: `RowOfflinePending`/`RowConflict` states (outbox-fed, never snapshot metadata); pending sheet (Edit pending via `editPendingReadingLog` mutating the queued payload under the same log ID w/ claim preserved, Cancel pending); §7.2 conflict dialog (Same session — discard mine / Different session — add mine → `resolveQuickSlotConflict`); `pendingReadingLogsFor`; `purgeChildData` wired at child unlink | `offline_service.dart`, `child_log_row.dart`, new `widgets/pending_session_sheet.dart`, `edit_reading_log_sheet.dart` (isPending), `parent_home_screen.dart`, `parent_linking_service.dart` | app release | ✅ merged 2026-07-24; +11 tests; suite 643/643 |
| G | Teacher context: `Where did the reading happen?` toggle on the teacher log sheet (Home reading default — preserves #39 proxy semantics; Class reading explicit) → `context` stamped by `logReadingAsTeacher`; classroom rows on parent Home + slot rules shipped earlier (PR-D/PR-A). Teacher slot-claim allowed by rules but not auto-attempted (backdated proxies would race the family's evening log — revisit with Phase 2 data). | `teacher_log_reading_sheet.dart`, `reading_log_service.dart` | app release | ✅ merged 2026-07-24; +1 test; suite 644/644 |

Gate: full `flutter test` demo-readiness suite (pinned 3.44.6) + rules tests (Java 21) + functions integration tests green per PR.

### Phase 2 — P1 usability

| Batch | Scope | Status |
|---|---|---|
| P2-1 | **Yesterday backdating (D1)**: Today/Yesterday segmented control in the detailed flow (school-time day math), Review step gains a "Reading day" row with school-time disclosure; gated on `platformConfig/parentBackdating` (absent ⇒ ENABLED; super-admin portal toggle owed by Nic). **Guardian×child prefs (§6.4)**: `preferences.quickLog.{studentId}` (usualMinutes / pinnedBookTitle / divergence tracking) via new `GuardianQuickLogPrefsService`; row button uses guardian usual, status shows `School goal: N min · book` when differing, pinned book fills the no-allocation gap; quick-log payload passes the SAME resolved titles/minutes as the label (preview==payload); D5 "make usual?" prompt after 3 consecutive divergent detailed saves | ✅ merged 2026-07-24; suite 647/647 |
| P2-2 | Book picker sheet (Choose book): pinned → recents (last 3 distinct from any guardian's sessions) → assigned, case-insensitive dedupe with `Pinned`/`Assigned`/`Logged` badges, manual entry w/ keyboard-Done auto-commit, "Make this the current book" pin persistence (choosing never writes a session; row flips to Ready instantly via session-local pin mirror). `books[]` entries `{title, source: assigned\|manual, format}` with a session-level format chip row (Print/eBook/Audiobook/Read aloud) in the detailed flow; rules extended (`books` optional ≤20 on create + contentUpdate — rides the pending rules deploy; slot tests re-green 20/20) | ✅ merged 2026-07-24; suite 647/647 |
| P2-3 | `editedAt` provenance + edited display · detailed success screen with `Done / Edit this log / Remove my session` · notes-and-audio audience disclosure line (`Shared with {teacher}` — dovetails with ST4S consent work) | ☐ |

### Phase 3 — P2 refinement

Canonical title matching + household aliases · optional barcode/voice title entry · correction-request flow for another guardian's entry · shared-device app-lock option · neutral opt-in co-parent notifications ("Reading was logged for Lily") · analytics: slot-rejection count, undo rate, edit rate, chooser usage, unresolved-title rate, legacy-title tail.

---

## 9. Open product decisions — RESOLVED by Nic, 2026-07-24

| # | Decision | Resolution |
|---|---|---|
| D1 | **Yesterday backdating** (reverses beta "No parent backdating", `CLASSROOM_BETA_FIX_PLAN.md:25`) | ✅ **Approved, Yesterday-only**, shipping ON for first-round school testing — **conditional on a platform kill-switch**: client honours `platformConfig/parentBackdating` from day one; Nic to add the super-admin portal Operations toggle later based on evidence gathered over the coming months. **Reminder owed to Nic at end of all phases.** |
| D2 | Classroom/teacher logs and **streaks** | ✅ **Keep counting** in Phase 1; Home row/slot separation only. Revisit with data in Phase 2. |
| D3 | Quick-log book attribution | ❌ Recommendation rejected — **keep union behaviour**: quick log continues crediting all effective assigned titles (books-read counts unchanged). Persona protections retained regardless: no fabricated `'Reading'` title ever; no assignments ⇒ `Choose book`, never a silent guess. The "ambiguous assignments open a chooser" rule is dropped (moot under union). |
| D4 | Old row widget behind `parentQuickLogV2` for one release | ✅ Yes (default accepted). |
| D5 | Usual-duration prompt threshold | ✅ 3 consecutive divergent sessions (default accepted). |

---

## 10. Acceptance matrix (pre-release verification)

| # | Scenario | Verified by |
|---|---|---|
| 1 | Logging three children out of order never moves or resizes untouched rows | Widget test (golden + key-position assertions), PR-D |
| 2 | Rapid double tap / retry / app resume ⇒ one session, one stats contribution | Widget test (synchronous lock) + rush-test same-ID replay + `stats_concurrency` test |
| 3 | Two guardians tap concurrently ⇒ one home-quick session; loser told nothing was added and wrote nothing | Rules test + extended `reading_log_rush` slot-contention case, PR-A |
| 4 | Offline conflict never overwrites/silently duplicates another guardian's record | `offline_service` unit tests for §7.2 branches, PR-F |
| 5 | Saved child/book/duration/date exactly match the preview | Single snapshot struct + widget test asserting serialisation equality, PR-D |
| 6 | No-book quick log cannot persist `Reading` or any invented title (union of real assigned titles is fine per D3) | Service unit test + `validateReadingLog` telemetry, PR-C/B |
| 7 | Manual text retained without tapping `+` | Widget test on commit-on-primary-action, Phase 2 picker PR (interim: existing `onSubmitted` covered) |
| 8 | One 30-min two-book session contributes 30 minutes | Existing stats semantics locked by a functions test assertion, PR-B |
| 9 | Undo/edit/remove affect exactly one session; dependents cleaned | Emulator integration test on `onReadingLogDeleted` (comments/audio/evals/slot gone), PR-B |
| 10 | Teacher classroom reading doesn't mark home reading complete | Widget test (row state) + rules test (classroom can't claim slot), PR-G/A |
| 11 | Revoked access stops queued uploads and purges child-scoped cache | `offline_service` test + rules test on update/delete re-check, PR-F/A |
| 12 | School-time rollover, travel, offline-after-midnight keep the correct day | `school_time` unit tests + provider test with fake clock, PR-C |
| 13 | VoiceOver and max text size fully operable | Semantics widget tests (labels/actions) + 2.0-scale layout tests + manual VoiceOver pass on device, PR-D |

---

## 11. Change log

- **2026-07-24** — v1 drafted from persona findings + 4-agent codebase audit. Awaiting §9 sign-off.
- **2026-07-24** — v2: §9 decisions resolved by Nic (D1 approved with platformConfig kill-switch condition + portal-toggle reminder; D3 rejected → union behaviour kept, §3.2/§4.1/§6.3 updated; D2/D4/D5 defaults accepted). Phase 0 prototype/testing skipped → straight to Phase 1. PR-A test plan moved to a new `quick_slot.rules.test.js` (concurrent session owns the uncommitted rush test).
