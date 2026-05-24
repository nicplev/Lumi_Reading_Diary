# Lumi — Parent UX Research, Recommendations & Implementation Roadmap

> **Purpose.** Lumi is a children's reading tracker deployed in schools; parents log/confirm
> their child's at-home reading each day. The biggest adoption risk is **parent friction** —
> if the daily logging interaction is not seamless and convenient, schools perceive the
> rollout as a failure and abandon it. This document gathers external UX research, maps it
> against Lumi's current parent-facing code, and lays out a file-level implementation
> roadmap to make parent logging genuinely fast.
>
> **Scope note.** Two further recommendations — age-adaptive logging vocabulary and a
> multilingual/SMS equity layer — were researched but **descoped** for this round. They are
> summarised briefly in the appendix for future reference.

---

## Part 1 — Research Synthesis

A note on evidence quality: peer-reviewed research on parent-facing *reading-app* UX
specifically is thin. The strongest evidence base sits in three adjacent areas — literacy
research on home reading, HCI research on cognitive load / habit formation / notifications,
and industry reporting on school-communication app adoption. Practitioner sources are
flagged as such; where evidence is genuinely mixed (notably gamification), that is stated.

### 1.1 Parent behaviour & context

**Parents use phone apps in fragmented micro-sessions, not focused sittings.** Wellness apps
have standardised around this: Headspace and peers deliberately condense activity into
"snack-size" 3–10 minute segments because parents "are not expected to sit in perfect
silence." A logging interaction must complete inside a real parenting window — the
school-run queue, a nap, bedtime wind-down — and survive interruption mid-task. Assume the
parent is one-handed and may be interrupted before finishing.
*(Sources: [Declutter The Mind — apps for busy parents](https://declutterthemind.com/blog/best-app-for-busy-parents); [Willo — organization apps for working moms](https://meetwillo.app/blog/best-organization-apps-for-busy-working-moms-in-2024/))*

**Cognitive load and decision fatigue are the central enemy.** UX research consistently
identifies *Hick's Law* — decision time grows with the number of choices — as a primary
friction source. The best-supported mitigations are *progressive disclosure* (show only the
key action first, reveal more on demand), minimalist interfaces, and removing redundant
inputs. Airbnb reported a 30% reduction in checkout completion time in 2024 simply by
removing redundant date pickers. For a tired parent at 8pm, every extra field, screen, or
decision is a place the task gets abandoned.
*(Sources: [Aufait UX — Cognitive Load Theory in UI Design](https://www.aufaitux.com/blog/cognitive-load-theory-ui-design/); [Six design principles for reducing cognitive load](https://medium.com/@zhouandi0318/six-design-principles-for-reducing-cognitive-load-in-ux-e4ee7e3fa62e); [16 Mobile App UI/UX Trends 2025](https://spdload.com/blog/mobile-app-ui-ux-design-trends/))*

**Demographic differences are real.** USAA's analysis of 579,000+ youth accounts (2024–25)
found millennial parents adopt digital tools roughly twice as readily as Gen-X parents, and
that millennials are also more *intentional and skeptical* about tech. Practically: younger
parents tolerate (and expect) more polish and gamification; older parents want it to "just
work" and distrust anything manipulative.
*(Source: [USAA Gen Alpha report](https://newsroom.usaa360.com/news/gen-alpha-report))*

### 1.2 School–parent communication apps — what works, what fails

**The best-documented failure mode is app overload.** The 2025 *App Overload* report
(Cornerstone Communications + Edsby; ~275 educators, administrators, parents, surveyed
Dec 2024–Jan 2025) found schools without a unified platform make families juggle **10–15
separate educational apps**, and **85% of surveyed parents rated their satisfaction with
using multiple school apps at 5/10 or below**. Lumi must minimise what it asks and batch
communication — a standalone reading app that adds a 16th icon is fighting the dominant
frustration in the category.
*(Sources: [App Overload report PDF](https://cornerstonepr.net/wp-content/uploads/2025/03/AppOverloadReport_bg.pdf.pdf); [eSchoolNews — "Too many apps for that"](https://www.eschoolnews.com/digital-learning/2025/04/28/too-many-apps-for-that-in-schools/))*

**Beanstack — the closest comparable** (it *is* a reading-log app) loses parents on
**execution friction**, per App Store / Google Play reviews:
- **Multi-child handling is broken** — parents "have to log out and log in to switch
  between students." For a school product where most families have multiple children, this
  is a top-priority requirement, not an edge case.
- **Logging glitches at volume** — "the program glitches substantially when logging more
  than 2 or 3 books"; ISBN scan often fails.
- **What's praised:** it's free, has badges, and parents concede "it encourages their kids
  to read."

Beanstack proves the *concept* but loses parents on execution — exactly the risk Lumi
names. **Lumi's competitive wedge is a genuinely seamless multi-child logging flow.**
*(Sources: [Beanstack Tracker — Google Play](https://play.google.com/store/apps/details?id=com.beanstack&hl=en_US); [Beanstack Tracker — App Store](https://apps.apple.com/us/app/beanstack-tracker/id1360324277))*

### 1.3 Friction reduction — making logging seamless

**One-tap logging with sane defaults is the gold standard.** Habit-tracker UX guidance is
explicit: BJ Fogg's *Tiny Habits* argues "friction is the biggest sign of whether a habit
will stick — if logging takes more than a few seconds, you'll skip it." **Home-screen
widgets** that let a parent mark "read today" *without opening the app at all*, and
**actionable notifications** with an inline log button, are repeatedly cited as the
highest-leverage friction reducers. The default logging action should be a single
confirmation, pre-filled with today's date and the expected book/minutes; detail should be
optional and progressively disclosed.
*(Sources: [Reclaim — Best Habit Tracker Apps 2026](https://reclaim.ai/blog/habit-tracker-apps); [Courier — Reduce Notification Fatigue](https://www.courier.com/blog/how-to-reduce-notification-fatigue-7-proven-product-strategies-for-saas))*

**Notifications: inform without annoying.** Best-practice consensus (2024–25): batch into
digests rather than per-event drips; respect quiet hours; trigger on user context (e.g.
only on un-logged days) rather than a fixed clock; make notifications actionable; favour
high value over high frequency.
*(Source: [MoEngage — Push Notification Best Practices](https://www.moengage.com/learn/push-notification-best-practices/))*

### 1.4 Engagement & emotional design

**Don Norman's three levels** map onto Lumi: *visceral* (warm first impression — soft
colours, mascot, inviting empty state), *behavioural* (the logging flow must be fast,
predictable, forgiving — where most apps win or lose parents), *reflective* (the parent
should feel "I'm a good parent who supports my child's reading" — the retention engine).
*(Source: [NN/g — 3 Levels of Emotional Processing](https://www.nngroup.com/videos/3-levels-emotional-processing/))*

**Habit formation: prioritise Ability over Motivation.** BJ Fogg's model (B = MAP) and Nir
Eyal's Hook Model converge: increasing *Ability* (making the behaviour easier) is more
effective and sustainable than pumping up *Motivation*. You cannot reliably motivate a
tired parent; you can make logging take two seconds.
*(Sources: [Behavioral Scientist — Fogg Behavior Model](https://www.thebehavioralscientist.com/articles/fogg-behavior-model); [The Hook Model explained](https://medium.com/@omforux25/the-hook-model-explained-how-to-build-habit-forming-products-f261abb3fb03))*

**Gamification — evidence is genuinely mixed.** A 2023 meta-analysis (*ETR&D*) found
gamification enhances intrinsic motivation, autonomy, and relatedness but has *minimal*
impact on competency; a UPenn study found it boosted short-term engagement ~40% but
**reduced learning autonomy and sometimes decreased intrinsic motivation over time**.
*Implication:* reward the **behaviour of reading together / logging consistently** rather
than dangling prizes for *reading itself* (which can crowd out a child's intrinsic love of
reading). Keep competitive/leaderboard elements optional and de-emphasised.
*(Sources: [Springer ETR&D meta-analysis](https://link.springer.com/article/10.1007/s11423-023-10337-7); [GoLexic — Is Gamification Effective in Learning to Read?](https://golexic.com/blog/is-gamification-effective-in-learning-to-read/))*

**Streaks: powerful, but design them shame-free.** Duolingo's streak exploits *loss
aversion*, but "Duo anxiety" is a documented, meme-level phenomenon — and **Duolingo's own
data showed that *reducing* streak anxiety increased long-term engagement**. The
"streaks without shame" playbook: provide **streak freezes** and **earn-back / grace
periods**; **reframe lapses around long-run trends** ("You've read 47 of the last 50 days —
amazing!") instead of "You broke your streak"; reject confirmshaming. For Lumi this is
doubly important — a guilt-inducing app punishes the *parent* for a *child's* off-day
(illness, travel), which is exactly the resentment that makes a parent delete a school app.
*(Sources: [UX Magazine — Hot Streak Game Design Without Shame](https://uxmag.com/articles/the-psychology-of-hot-streak-game-design-how-to-keep-players-coming-back-every-day-without-shame); [DuoOwl — Why Duolingo Is Scary](https://duoowl.com/why-duolingo-is-scary/))*

**Mascots help children strongly and adults conditionally.** They create "emotional
anchors" and appear at emotional moments — celebrations, errors, empty states — but annoy
when they interrupt or nag. Rule for Lumi: the mascot is a **celebration and warmth
device, never a gate**, and "missing you" messaging must stay encouraging, never
guilt-laden.
*(Source: [Raw.Studio — How Mascots Improve UX](https://raw.studio/blog/how-mascots-improve-user-experience/))*

### 1.5 Accessibility (WCAG 2.2, mobile)

- **Touch targets:** minimum 24×24 CSS px (WCAG 2.5.8 AA); for a one-handed, in-motion,
  varied-age parent audience, **target the 44×44 px AAA standard** for primary actions.
- **Contrast:** minimum 4.5:1 normal text, 3:1 large text (1.4.3 AA); mobile is used in
  glare, so headroom matters.
- **Type:** support OS-level dynamic font scaling; layouts must reflow at large sizes.
- **Gestures:** every gesture needs a simple tap alternative (WCAG 2.2).
*(Sources: [W3C — WCAG2Mobile 2.2](https://www.w3.org/TR/wcag2mobile-22/); [W3C WAI — Target Size Enhanced](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html))*

### 1.6 Why this matters — child age 4–11

Home reading and parental involvement have strong, well-replicated literacy effects;
children with engaged parents show stronger vocabulary, comprehension, and reading
achievement, and a review of 19 parent-child reading interventions found benefits for the
parent-child relationship and parenting competence too. **The behaviour Lumi tracks is
genuinely high-value — the design job is to make logging it effortless.**
*(Sources: [Neuhaus — Parental Involvement Boosts Literacy](https://neuhaus.org/how-parental-involvement-boosts-literacy-in-early-learners/); [PMC — Home Literacy Environment as Mediator](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7396561/))*

---

## Part 2 — Lumi's Current Parent-Logging Flow (Baseline)

Established from a code audit of the repository:

- **Logging entry point:** [log_reading_screen.dart](../lib/screens/parent/log_reading_screen.dart) —
  a **3–4 step wizard**: (1) book selection + minutes picker, (2) child feeling
  (`ReadingFeeling`), (3) parent comment (configurable per school), (4) confirmation. The
  write path (`_saveReadingLog` + `_updateStudentStats`) lives **only inside this screen** —
  there is no shared reading-log write service.
- **Home dashboard:** [parent_home_screen.dart](../lib/screens/parent/parent_home_screen.dart) —
  greeting, child-selector dropdown, notification bell, and a `_TodayCard` driven by a
  `StreamBuilder` on today's `readingLogs`; it already computes `hasLoggedToday`,
  `activeAllocations`, `targetMinutes`, and assigned book titles.
- **Post-log celebration:** [reading_success_screen.dart](../lib/screens/parent/reading_success_screen.dart) —
  confetti, streak, milestone badges; auto-dismisses after 3s.
- **Reminders:** `NotificationService.scheduleReminders()` uses `flutter_local_notifications`
  `zonedSchedule`; taps just open `/parent/home` — no notification actions.
- **iOS widget:** `WidgetDataService` + the Swift `LumiWidget` target — **display-only**,
  no App Intents.
- **Offline:** `OfflineService.saveReadingLogLocally()` exists but is **currently unused** —
  the wizard writes straight to Firestore.
- **Design system:** Riverpod, Go Router, Nunito type, 8pt grid; rose-pink `#FF8698` primary.

**Friction diagnosis.** The core daily action is gated behind a multi-screen wizard with
several decisions — the single most common reason parents abandon school reading apps
(§1.2–1.3). The fix is a one-tap default with everything else made optional.

---

## Part 3 — Recommendations & Implementation Roadmap

Effort is graded **S / M / L**. The phase order makes the foundation refactor and the
one-tap log the first things shipped, then resilience/engagement, then the
highest-platform-risk items last.

| Phase | Items | Theme |
|---|---|---|
| 0 | `ReadingLogService` extraction | Foundation (prerequisite) |
| 1 | Recs 1, 2, 10 | One-tap log + progressive disclosure + accessibility |
| 2 | Recs 5, 6, 7 | Wizard resilience, multi-child, shame-free streaks, habit gamification |
| 3 | Recs 3, 4 | Actionable reminders + interactive iOS widget (highest platform risk) |

### Phase 0 — Foundation refactor (prerequisite for Recs 1, 3, 4, 5a)

The write path is currently trapped inside [log_reading_screen.dart](../lib/screens/parent/log_reading_screen.dart).
The one-tap log, notification action, and widget intent all need it — without extraction
the logic gets triplicated and drifts.

- **Create `lib/services/reading_log_service.dart`** — a `ReadingLogService` singleton
  (mirroring `OfflineService` / `NotificationService` style):
  - `logReading({student, parent, allocations, minutesRead, bookTitles?, feeling?, commentSelections?, freeText?, quickLog = false})`
    — builds the `ReadingLogModel`, writes to Firestore, runs the stats transaction, calls
    `WidgetDataService.updateAfterLog`. Move the `_saveReadingLog` + `_updateStudentStats`
    bodies here verbatim.
  - `buildQuickLog(...)` — constructs a default log from allocations (target minutes, first
    assigned book or `['Reading']`, `status: completed`, `metadata.quickLog: true`).
  - `attachFeeling(logId, feeling)` / `attachComment(...)` — post-hoc `update()` patches.
  - Offline-aware: try Firestore `.set()`; on failure / when offline, fall back to
    `OfflineService.saveReadingLogLocally()` and skip the transaction (recompute on sync).
- [log_reading_screen.dart](../lib/screens/parent/log_reading_screen.dart) `_saveReadingLog`
  becomes a thin call into the service.
- **Effort: M.** Pure refactor, no behaviour change — a precondition, ship first.

### Rec 1 — One-tap log as the default action — Phase 1, Effort M

- **Modify `_TodayCard` in [parent_home_screen.dart](../lib/screens/parent/parent_home_screen.dart):**
  replace the single full-width CTA with a primary `LumiPrimaryButton`
  *"✓ Did {firstName} read today?"* (new `onQuickLog` callback) plus a secondary
  `LumiTextButton` *"Add detail"* (keeps the existing wizard navigation). Show
  *"{target} min · {bookTitle}"* inline so the parent sees what one tap records. Pre-fill
  from the already-computed `activeAllocations` / `allTitles`.
- `onQuickLog` calls `ReadingLogService.logReading(... quickLog: true)`, then navigates to
  `reading-success` (reuse the existing `extra` map shape). The home `StreamBuilder`
  auto-rebuilds `hasLoggedToday`.
- Add an in-card loading state via `LumiPrimaryButton(isLoading:)`; guard double-taps.
- **Firestore:** no schema change — `metadata.quickLog: true` inside the existing nullable
  `metadata` map (no migration).
- **Edge cases:** no allocation → default 20 min / `['Reading']`; already logged today →
  primary button becomes *"Log another session"* → wizard; offline → service Hive fallback.
- **Depends on:** Phase 0. Feeds Recs 2, 3, 4, 5b.

### Rec 2 — Progressive disclosure of feeling + comment — Phase 1, Effort M

- **Modify [reading_success_screen.dart](../lib/screens/parent/reading_success_screen.dart):**
  when `metadata.quickLog == true` and `childFeeling == null`, render an optional collapsed
  prompt *"How did it go for {firstName}? (optional)"* with a compact `BlobSelector`. On
  tap → `attachFeeling(logId, ...)` patches the existing doc. If
  `ParentCommentSettings.enabled`, add an optional *"Add a note"* expansion with
  `CommentChips`.
- **Cancel the 3 s `_autoNavigateTimer`** the moment the parent interacts, so they are not
  rushed; require an explicit *"Done"* thereafter.
- Optionally surface the same prompt inline on `_TodayCard`'s post-log "Reading Complete!"
  state.
- **Firestore:** none structural — feeling/comment fields already exist on
  `ReadingLogModel`, now patched via `update()` instead of set at create time. Offline
  patches route through `OfflineService` as a `SyncAction.update`.
- **Depends on:** Rec 1 (the `quickLog` flag drives whether the prompt shows).

### Rec 10 — Accessibility headroom — Phase 1, Effort S–M

- **Confirmed defect:** white text on `#FF8698` ≈ **2.3:1 — fails WCAG AA**. In
  [app_colors.dart](../lib/core/theme/app_colors.dart) add a `rosePinkAccessible`
  (~`#D9536A`, ≥ 4.5:1 on white) used for **buttons / CTAs only**, keeping `#FF8698` for
  decorative fills and badges. Mirror the value in
  [LumiWidgetEntryView.swift](../ios/LumiWidget/LumiWidgetEntryView.swift) (`lumiRosePink`).
  Get design sign-off that it still reads as "Lumi pink."
- The `mintGreen #D2EBBF` "logged" badge with white text also fails — use `charcoal` text
  on mint (the colour file comment already says so).
- **Touch targets:** `LumiPrimaryButton` is `height: 56` (OK); ensure the new one-tap
  button is full-width 56 h; audit icon-only controls (notification bell, blob items) for
  ≥ 44×44.
- **Dynamic type:** confirm no `textScaler` clamp in `main.dart` / `app_theme.dart`; wrap
  text in fixed-height rows (`_TodayCard`, `StatsCard`, success-screen badges) in
  `Flexible` / `IntrinsicHeight` so it does not clip at 200%.
- Add `Semantics` labels to icon-only controls and `BlobSelector` items (currently bare
  `GestureDetector`s).
- **Do this in Phase 1** so the new one-tap button ships accessible from day one.

### Rec 5 — Wizard state preservation + fast multi-child logging — Phase 2, Effort L combined

**5a — Wizard survives interruption (Effort M).**
- Make `_LogReadingScreenState` a `WidgetsBindingObserver`; on `paused` / `inactive`
  serialize a draft (`_currentStep`, selected books, minutes, feeling, comments, notes) to
  Hive; restore in `initState` if a draft exists for `widget.student.id`.
- **Modify [offline_service.dart](../lib/services/offline_service.dart):** add a
  `log_drafts` Hive box with `saveLogDraft / getLogDraft / clearLogDraft(studentId)`; clear
  on successful save.
- **Edge cases:** re-validate restored book titles against current allocations (drop stale
  ones); one draft per studentId; prompt *"Discard draft?"* on explicit close.

**5b — Fast multi-child logging (Effort M).**
- **Modify [parent_home_screen.dart](../lib/screens/parent/parent_home_screen.dart):** when
  `_children.length > 1`, render one compact `_TodayCard` per child (a vertical stack for
  2–3, a horizontal `PageView` for 4+), each with its own quick-log button. Convert the
  child selector to a horizontal `StudentAvatar` row. Streams are already per-`studentId` —
  instantiate N.
- **Risk:** N children → 3N concurrent `snapshots()` listeners; cap rendered live cards /
  lazy-load below the fold.
- **Depends on:** Rec 1 (`_TodayCard` quick-log). Directly fixes Beanstack's most-cited
  failure (§1.2) — Lumi's competitive wedge.

### Rec 6 — Shame-free streaks — Phase 2, Effort M

- **Modify `StudentStats` in [student_model.dart](../lib/data/models/student_model.dart):**
  add `streakFreezesAvailable` (default 2), `streakFreezesUsed`,
  `streakFreezeLastEarnedDate`, optional `last50DaysCount`. Null-safe defaults in `fromMap`
  → backward compatible, no migration.
- **Modify the stats transaction (now in `ReadingLogService`):** when one day is missed and
  a freeze is available, consume the freeze and **keep `currentStreak`** instead of
  resetting; earn a freeze every ~7 consecutive logged days up to a cap. Freeze accounting
  must run **inside the same Firestore transaction** for multi-guardian consistency.
- **Modify [reading_success_screen.dart](../lib/screens/parent/reading_success_screen.dart):**
  remove all "streak broken" framing; show a *"47 of the last 50 days"* trend and
  *"Freeze used — streak protected!"* when a freeze fired. Add a "❄️ {n} freezes" indicator
  on `parent_home_screen.dart` / `StatsCard`.
- **Firestore:** new fields under `students/{id}.stats`, all backward compatible.
- **Tech debt to flag:** streak logic is client-side in a transaction; long-term it belongs
  in a Cloud Function `onCreate(readingLogs)`.
- **Depends on:** Phase 0.

### Rec 7 — Gamify the habit, not the reading — Phase 2, Effort S

- [reading_success_screen.dart](../lib/screens/parent/reading_success_screen.dart)
  milestones already key on `totalReadingDays` ("Nights") — **mostly already correct**.
  Audit copy to celebrate *showing up* (*"Night 25 — you logged 25 times!"*), not minutes
  or books.
- In `_AchievementNearMissCard` ([parent_home_screen.dart](../lib/screens/parent/parent_home_screen.dart)),
  **de-emphasize `minutes` / `books` achievement types** in the parent-facing nudge; prefer
  `streak` / `days`. Adjust `AchievementThresholds` defaults toward consistency-type
  achievements.
- **No leaderboard exists** in `lib/screens/parent/` — recommend explicitly *not* adding
  one; if ever added, keep it behind a profile toggle, off by default.
- Confirm `quickLog` logs count identically toward habit milestones.
- **Depends on:** pairs with Rec 6 (same files).

### Rec 3 — Actionable reminder notification — Phase 3, Effort L

- **Modify [notification_service.dart](../lib/services/notification_service.dart):** define
  an `AndroidNotificationAction('log_reading', 'Log reading ✓')` and a
  `DarwinNotificationCategory('lumi_reminder', ...)` registered in
  `DarwinInitializationSettings(notificationCategories:)`; attach the category/action in
  `_scheduleOne`. Encode `studentId` / `schoolId` / `parentId` / `targetMinutes` / first
  book into the notification **payload** at schedule time.
- Handle `response.actionId == 'log_reading'` in `_handleNotificationTap`: build a quick log
  via `ReadingLogService` **in the background, no navigation**; show a confirmation
  notification (*"Logged ✓ — {n} day streak!"*). Wire
  `onDidReceiveBackgroundNotificationResponse` (`@pragma('vm:entry-point')`) — the
  background isolate must init Firebase + minimal services.
- **Context-aware firing:** keep the recurring `zonedSchedule`, but add
  `NotificationService.refreshReminderForToday()` that cancels today's reminder per child
  when a log already exists; call it on app foreground and after each log; re-arm at
  midnight.
- **Hardest part:** background notification actions — Android background-isolate init; iOS
  action constraints (a silent action requires `.foreground` false; some require unlock).
  Offline taps fall back to Hive; the confirmation says *"Saved — will sync."*
- **Depends on:** Phase 0, Rec 1.

### Rec 4 — Log from the iOS home-screen widget — Phase 3, Effort L

- **Create `ios/LumiWidget/LogReadingIntent.swift`** — an `AppIntent` with a `studentId`
  parameter; its `perform()` records the intent into the App Group
  (`UserDefaults(suiteName:)`, key `lumi_pending_widget_logs`). It **cannot call Firestore
  directly** — the widget extension has no Firebase SDK.
- **Modify [LumiWidgetEntryView.swift](../ios/LumiWidget/LumiWidgetEntryView.swift):**
  replace the CTA capsule with `Button(intent: LogReadingIntent(studentId:))` on iOS 17+
  (`if #available`), keeping the `Link` / `widgetURL` fallback for iOS 14–16; show
  optimistic *"✓ Logged"* via `WidgetKit.reloadAllTimelines()`.
- **Bridge intent → Dart:** add `drainPendingWidgetLogs()` to `widget_data_service.dart`
  that reads the App Group and, for each pending entry, calls
  `ReadingLogService.logReading(... quickLog: true)`. Drain on app launch and resume
  (`widget_channel_handler.dart` / `main.dart`).
- **Honest constraint:** a true headless offline write is not possible on iOS — the widget
  extension cannot reach Firestore. The deliverable is an **optimistic queue-and-reconcile**
  model: the widget tap is queued and the widget optimistically flips to "logged"; the
  actual Firestore/Hive write happens on the next app activation. Tightening this would
  require a Background App Refresh task.
- **Edge cases:** the pending queue dedupes by date; `OfflineService` last-write-wins
  resolves conflicts; iOS < 17 falls back to the deep link; verify the App Group
  entitlement on both targets.
- **Depends on:** Phase 0, Rec 1. Build last — highest platform risk.

---

## Part 4 — Cross-Cutting Architectural Risks

1. **Triplicated write logic** — mitigated by Phase 0; do not skip it.
2. **Client-side streak/stats in a Firestore transaction** — works now, but freeze
   accounting (Rec 6) raises complexity; concurrent multi-guardian logging is the stress
   case. Long-term, move to a Cloud Function.
3. **`OfflineService.saveReadingLogLocally` is currently unused** — Recs 1/3/4 are its
   first real consumers; expect to harden it (the stats transaction must be skipped offline
   and recomputed on sync, or it will hang).
4. **The iOS widget cannot write to Firestore** — Rec 4 is queue-and-reconcile, not a
   headless write. Set expectations accordingly.
5. **Background notification actions** (Rec 3) — the riskiest single piece.
6. **`#FF8698` AA failure** affects every primary CTA, including the new one-tap button —
   fix in Phase 1.
7. **N-child live streams** (Rec 5b) — cap concurrent listeners.

## Part 5 — Recommended Validation

Moderated, one-handed, time-boxed usability tests with parents across the millennial /
Gen-X split. Run a small pilot in 1–2 schools and measure **whole-class participation
rate** — the metric the school actually cares about — before wider rollout. Track the share
of logs made via the one-tap path vs the detail wizard (the `metadata.quickLog` flag) as
the friction-reduction KPI.

---

## Appendix — Descoped recommendations (for future reference)

These were researched and judged not needed for this round:

- **Age-adaptive logging vocabulary.** Children 4–11 span three involvement modes —
  parent-reads-aloud (4–6), child-reads-to-parent (7–9), parent-confirms (10–11). Logging
  copy ("minutes read together" vs "book finished" vs "reading confirmed") and gamification
  tone could adapt by reading stage to avoid feeling babyish to older children.
- **Multilingual UI + SMS fallback (equity).** EdTech-equity research flags language and
  connectivity as barriers for ESL and lower-income families; a school judges a rollout by
  *whole-class* participation. Full localization of parent UI/notifications, plus an SMS
  reminder/confirm channel for non-app households, would close that gap.

---

*Compiled May 2026. Research synthesised from external UX/literacy sources (cited inline)
and a code audit of the Lumi repository.*
