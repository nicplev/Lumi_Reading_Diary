# Teacher comprehension recordings screen — refinement plan

**Status:** Implemented in workspace; deployment and physical-device QA pending
**Date:** 21 July 2026
**Primary surface:** Flutter teacher app
**Recommended user-facing name:** **Comprehension recordings**

## 1. Decision summary

Lumi already has most of the required foundations, but the existing class-wide
screen is the wrong way around for production use:

- Teachers can already play and permanently delete an individual comprehension
  recording from a student's reading-history/comment sheet.
- A class-wide `ComprehensionReviewScreen` also exists, but it is an AI-only
  surface. It reads `comprehensionEvals`, shows AI filters and summaries, and is
  hidden behind both dev access and the AI entitlement.
- Consequently, a normal teacher at an audio-enabled school has no dedicated
  class-wide recording inbox unless AI evaluation is also enabled.

The recommended change is to make the existing route a **recording-first class
inbox** backed by `readingLogs`. Audio recording access becomes the permanent
product. AI evaluation becomes a separately gated, optional enhancement joined
onto a recording by `logId` only when its legal, platform and school gates are
all valid.

This is a refinement, not a new audio-storage design. The current canonical
Storage object, signed-URL playback, class authorization, server-side deletion,
retention and audit paths should remain authoritative.

### Approved workflow decisions

- Default to a **To review** inbox, with Recent and Reviewed views.
- Mark a recording reviewed automatically after at least 80% has played.
- Store review status on the reading log and share it across co-teachers; bind
  it to the current audio object generation so replacement audio becomes
  pending again.
- Offer **Reply to family** only as a quiet secondary action. It must open the
  existing reading-log comment thread
  `schools/{schoolId}/readingLogs/{logId}/comments`, exactly as Student detail
  does, rather than creating an inbox-specific conversation.
- Keep permanent teacher deletion, with server authorization, canonical path
  derivation, confirmation and audit logging unchanged.
- Show only a compact numeric to-review badge at the Class-tab entry, capped at
  `99+`; do not show a sentence such as “8 recordings to review” in the header.
- Provide a **Next recording** action for efficient review without autoplay.
- Keep any future AI evaluation collapsed until the teacher explicitly chooses
  **View AI summary**.

## 2. Current-state audit

| Area | Current implementation | Assessment |
| --- | --- | --- |
| Class-wide screen | `lib/screens/teacher/comprehension_review_screen.dart` | Exists, but lists AI evaluations rather than recordings. |
| Teacher entry point | Class header “Review” and Settings “Comprehension Review” | Both are dev-gated; the class-header entry also requires AI to be on. |
| Individual playback | `TeacherCommentsSheet` + `ComprehensionAudioPlayer` | Production-shaped and already independent of AI. |
| Recording source | `schools/{schoolId}/readingLogs/{logId}` audio receipt fields | Correct source of truth for the base screen. |
| AI source | `schools/{schoolId}/comprehensionEvals/{logId}` | Correct as an optional left join; must never determine whether a recording appears. |
| Teacher data scope | Firestore rules require the teacher to be assigned to `resource.data.classId` | Strong class-level isolation already exists. |
| Audio byte access | Direct Storage reads denied; callable returns a 15-minute generation-bound signed URL | Strong existing boundary; retain it. |
| Deletion | Callable derives the canonical path, checks class assignment, clears receipt fields and audit-logs | Strong existing boundary; retain it. |
| School audio gate | Platform recording switch + school `settings.comprehensionRecording.enabled` | Server-authoritative playback gate exists. Client presentation needs a non-flashing state model. |
| AI gate | Platform flag + client `enabled` check; server pipeline additionally requires a current authority version and confirmation | Client and server checks are not currently equivalent. |
| Retention | Automatic per-school 30/90/365-day cleanup, with legacy handling | No change required for this screen. |

### What should be reused

- `ComprehensionAudioService` and its `getComprehensionAudioUrl` /
  `deleteComprehensionAudio` callables.
- The canonical `schools/{schoolId}/comprehension_audio/{logId}.m4a` derivation
  on the server. Never trust a client-supplied Storage path.
- `ReadingLogSnapshot` parsing patterns and the existing class-scoped Firestore
  rule shape.
- Lumi tokens, typography, filter chips, student avatars, inline stream errors,
  skeletons and toast behavior.
- The current AI model and evaluation detail components, after separating them
  from the recording base.

## 3. Product contract

### Base capability: comprehension recordings

The screen is available to an authenticated teacher when all of the following
are true:

1. the teacher belongs to the school;
2. the teacher is assigned to the selected class;
3. the platform comprehension-recording switch permits playback;
4. the school's comprehension-recording setting is enabled; and
5. this is not a demo-preview-only configuration.

The dev-access allowlist and every AI flag are irrelevant to the base screen.

The screen shows every retained, server-confirmed recording for the selected
class. A recording appears when its reading log has:

```text
classId == selected class
comprehensionAudioUploaded == true
comprehensionAudioUploadedAt != null
```

The screen does not show pending client uploads because they are untrusted and
not playable. Existing student-level surfaces may keep their current pending
copy for legacy/offline states.

### Optional capability: AI evaluation

AI content is absent—not teased, labelled “coming soon”, or queried—unless the
complete AI gate is valid:

```text
platformConfig/aiEvaluation.enabled == true
school.settings.aiEvaluation.enabled == true
authorityVersion == current required version
authorityConfirmedAt exists
```

When valid, the evaluation for the same `logId` augments the recording card and
detail sheet. It never replaces the recording, changes the recording's
visibility, or blocks playback when evaluation is missing/failed.

### Explicit non-goals for the first release

- Enabling AI evaluation or changing any AI legal/authority setting.
- Backfilling AI evaluations for historical recordings.
- Downloading, sharing, exporting or bulk-playing child audio.
- Parent-facing transcripts, summaries, scores or flags.
- A new audio file format, storage namespace or retention policy.
- Manual per-teacher “heard/unheard” state. The approved state is a shared,
  generation-bound reviewed marker set automatically after 80% playback.
- A waveform generated from or persisted alongside the audio. A progress bar is
  sufficient and avoids another child-data derivative.

## 4. Information architecture and navigation

### Primary entry

Place a standard **Recordings** action in the selected class area of the Class
tab whenever the effective audio gate is on. It should use the microphone /
waveform icon and the Class section's established green accent.

The current class header already carries “Assign books” and “Question”. Keep the
recording entry as a compact waveform icon with a numeric badge and an
accessible semantic label; avoid another long text action on small devices.

```text
┌──────────────────────────────┐
│ Prep                         │
│ [ Assign books ] [ Question ]│
├──────────────────────────────┤
│ Review                       │
│ [ waveform  ●12 ]            │
└──────────────────────────────┘
```

The count is live, class-scoped and capped at `99+`. The visible bubble contains
only the number; screen-reader semantics may say how many are to review.

### Secondary entry

Replace the dev-gated Settings row with a gate-aware **Comprehension
recordings** row only if Settings remains a useful cross-class launcher. It can
reuse the existing class picker. The Class tab is the daily-workflow entry and
must not depend on Settings.

### Route

- Preferred path: `/teacher/comprehension-recordings`.
- Keep `/teacher/comprehension-review` as a temporary alias/redirect so existing
  internal links and resumed navigation do not break.
- Continue resolving the signed-in `UserModel` through `_userScopedRoute`.
- Reject a missing class, a class whose `schoolId` differs from the signed-in
  teacher's school, or a stale/unassigned class with a not-found/access state.
  Firestore rules and the playback callable remain the security boundary.

## 5. Screen layout: Lumi bento style

Use `LumiTokens.cream` for the page, flat `LumiTokens.paper` compartments,
`LumiTokens.rule` borders, `radiusLarge`/`radiusXL`, and no decorative shadow on
ordinary list cards. Use only tokenized spacing and `LumiType` styles.

### Recommended mobile layout

```text
┌──────────────────────────────────┐
│ ‹  Comprehension recordings      │
│    Class 3B                      │
├──────────────────────────────────┤
│  🎙  Listen to recent responses  │
│  18 recordings · 9 students      │
│  Audio is available for the      │
│  school's retention period.      │
├──────────────────────────────────┤
│ [Recent] [7 days] [30 days]      │
│ [All students ▾]                 │
│ [Needs review]  ← AI only        │
├──────────────────────────────────┤
│ TODAY                            │
│ ┌──────────────────────────────┐ │
│ │ avatar  Ava Patel       0:42 │ │
│ │ The Paper Bag Princess      │ │
│ │ “What was the main problem?”│ │
│ │ [▶ Listen] [AI summary]*    │ │
│ └──────────────────────────────┘ │
│                                  │
│ YESTERDAY                        │
│ ┌──────────────────────────────┐ │
│ │ avatar  Noah Chen       0:31 │ │
│ │ Free reading                │ │
│ │ [▶ Listen]                  │ │
│ └──────────────────────────────┘ │
└──────────────────────────────────┘
* Only when the complete AI gate is valid and an evaluation exists.
```

### Header bento

Keep the header factual and compact:

- title: `Comprehension recordings`;
- subtitle: selected class name;
- helper copy: `Listen to spoken responses from home reading.`;
- counts derived from the currently loaded window, clearly labelled (for
  example, `18 in the last 30 days`) rather than implying all-time totals.

Do not put an AI disclaimer in the header while AI is off.

### Filter bento

Base filters:

- To review (default), Recent and Reviewed;
- newest received first.

AI-only filters are inserted only when AI is enabled:

- needs review;
- level bands;
- flagged.

Keep filters horizontally scrollable on narrow devices and expose a clear
`Reset` when more than one filter is active.

### Recording card

Each card should include:

- student avatar and full name;
- reading date and, where useful, received date;
- book title(s), with `Free reading` fallback;
- captured comprehension question, clamped to two lines;
- duration;
- microphone/play affordance with an explicit `Listen` label;
- optional AI status chip in a separate trailing area.

Tapping the card opens the detail sheet. Do not instantiate an audio player or
mint a signed URL merely because the card scrolled on screen.

### Detail sheet

The recording is always first:

1. student, reading date and book context;
2. question asked;
3. large play/pause control, seek/progress bar and elapsed/total time;
4. a subtle `Use headphones in shared spaces` privacy hint;
5. destructive overflow action: `Delete recording`;
6. optional AI section below a divider.

The AI section remains a collapsed **View AI summary** disclosure. Expanding it
is the first point at which the matching evaluation document may be queried.
Its content contains the current disclaimer and qualitative decision support,
never a grade.

Only one player may be active at a time. Closing the sheet, changing account,
changing class, or backgrounding the app pauses and disposes playback.

## 6. Empty, loading and failure states

| State | Expected UI |
| --- | --- |
| Gate loading | Bento skeleton; do not show the entry or query recording rows until access is resolved. |
| Audio disabled | Entry hidden. If disabled while open, stop playback and show `Comprehension recordings have been turned off for this school.` with Back. |
| No recordings | Friendly empty bento: `No recordings yet` / `Spoken responses will appear here after families submit them.` |
| Filter has no matches | Keep filters visible and show `No recordings match these filters.` plus Reset. |
| First page error | `InlineStreamError` in a bento container with Retry; no raw Firebase message. |
| Older page error | Preserve loaded rows and show an inline `Couldn't load more` retry action. |
| URL authorization expired | Clear only that cached URL, re-authorize once, then show `Recording unavailable` with Retry. |
| Recording removed by retention/delete | Remove it through the Firestore stream; if the sheet is open, stop playback and show `This recording is no longer available.` |
| Offline | Show already-loaded metadata if available, but disable playback with `Connect to listen`; signed URLs must not be treated as an offline archive. |
| AI disabled/unavailable | Recording UI remains unchanged and contains no AI empty state. |

## 7. Data and provider design

### New recording row model

Introduce an audio-specific read model rather than making the screen depend on
`ComprehensionEvalModel`:

```dart
class TeacherComprehensionRecording {
  final String schoolId;
  final String classId;
  final String studentId;
  final String logId;
  final DateTime readingDate;
  final DateTime uploadedAt;
  final int durationSec;
  final List<String> bookTitles;
  final String? questionText;
}
```

Do not expose or accept an arbitrary playable URL in this model. The app sends
only `schoolId` and `logId` to the callable; the server derives the canonical
object path and recorded generation.

### Recording query

Create a provider keyed by `{schoolId, classId, date window, page cursor}`:

```dart
readingLogs
  .where('classId', isEqualTo: classId)
  .where('comprehensionAudioUploaded', isEqualTo: true)
  .orderBy('comprehensionAudioUploadedAt', descending: true)
  .limit(50)
```

Use a live stream for the first page so new recordings/deletions appear without
refreshing. Load older pages with bounded one-shot queries and
`startAfterDocument`; keep page 1 live while older pages remain stable.

Add and deploy the collection-scope composite index:

```text
readingLogs:
  classId ASC
  comprehensionAudioUploaded ASC
  comprehensionAudioUploadedAt DESC
```

An existing index covers `classId + comprehensionAudioUploaded + date`; do not
silently switch the proposed query to reading date just to avoid the new index.
`uploadedAt` is the reliable “arrived in the teacher inbox” order.

### Roster join

Move/reuse `classStudentNamesProvider` outside the AI provider file. It should
remain a class-scoped student query and return the small display model needed by
cards (name + avatar fields), not entire student documents where unnecessary.

Handle a deleted/moved student as `Former student` without leaking another
class's roster or dropping a still-retained recording.

### AI join seam

The recording provider is always primary. Put AI watching in a separate child
widget/provider that is not constructed until the full AI gate is true.

Join evaluations by `logId`:

```text
TeacherComprehensionRecording(logId) LEFT JOIN ComprehensionEvalModel(logId)
```

Keep every AI class query constrained by `classId`. For paged rows, choose one
of these safe patterns during implementation:

1. keep the existing bounded class evaluation stream and join matching loaded
   recording IDs locally; or
2. load evaluation details on card/sheet demand using an authorized document
   read, while keeping only coarse status on the list.

Do not create a second denormalized “review rows” collection for v1. The current
collections already provide an idempotent `logId` relationship, and another
projection would add retention/deletion consistency risk.

## 8. Security and privacy review

### Existing controls to preserve

- Firestore teacher reads are scoped to classes they teach; a teacher query
  without a provable `classId` constraint is denied.
- Parents cannot read `comprehensionEvals`.
- Canonical audio objects deny all direct client reads/writes in Storage Rules.
- The signed-URL callable checks auth, same-school staff role, class assignment,
  platform switch, school playback setting, validated receipt and object
  generation before returning a 15-minute read URL.
- Deletion is server-side, class-authorized, canonical-path-derived and audited;
  the reading log itself is retained.
- New audio collection requires current school audio authority and an approved
  retention choice; upload confirmation validates ownership, metadata, bytes,
  media duration and generation before publication.
- Retention and account/student deletion already cover audio and AI artifacts.

No critical or high-severity issue was found in the reviewed audio playback and
deletion path.

### Resolved — AI data watch and client authority mismatch

**Files:** former `lib/screens/teacher/comprehension_review_screen.dart`,
`lib/data/models/school_model.dart`,
`lib/data/providers/comprehension_eval_providers.dart`

Resolved by removing the AI-only class screen, matching the client gate to the
server's current authority version and confirmation requirement, and placing
the single-evaluation provider below the collapsed **View AI summary** action.
No evaluation document is watched before the teacher explicitly expands it.

Previous shape:

```dart
final enabled = ref.watch(aiEvaluationEnabledProvider(schoolId));
final evalsAsync = ref.watch(classEvalsProvider(lookup));
return !enabled ? const DisabledState() : EvaluationList(evalsAsync);
```

Implemented design:

```dart
final gate = ref.watch(aiEvaluationAvailabilityProvider(schoolId));
return switch (gate) {
  AiAvailability.enabled => AiEvaluationAddon(lookup: lookup),
  _ => const SizedBox.shrink(),
};
// AiEvaluationAddon is the only widget that watches classEvalsProvider.
```

Mirror `AI_EVAL_AUTHORITY_VERSION` and `authorityConfirmedAt` in the client
availability model. Add tests proving no evaluation provider subscription is
created when any AI gate is absent, malformed, stale or disabled.

### Resolved — signed-URL cache was not scoped to the authenticated session

**File:** `lib/core/widgets/audio/comprehension_audio_player.dart`

Resolved by removing the process-wide signed-URL cache. The player now requests
a fresh URL only after an explicit Play action and retains it only in that
widget/player instance, which is disposed when the sheet closes.

Previous shape:

```dart
static final Map<String, _CachedUrl> _urlCache = {};
final cached = _urlCache[widget.storagePath];
```

Implemented option:

```dart
// Preferred: authorize lazily for the open detail sheet and discard on close.
await audioService.getAudioUrl(schoolId: schoolId, logId: logId);

// If caching is retained, bind it to the authenticated principal and clear it
// on auth changes/sign-out.
final key = (uid: currentUid, schoolId: schoolId, logId: logId);
```

The new list must not pre-mint URLs. Add a shared-device regression test that
signs out, changes UID and proves the prior cached capability is not reused.

### Low / known rollout control — App Check enforcement defaults off

**File:** `functions/src/comprehension_retention.ts`

Authentication, class authorization and receipt validation are the primary
controls and are present. App Check replay-resistant tokens are wired into all
three audio calls, but server enforcement remains controlled by
`COMPREHENSION_AUDIO_APP_CHECK_ENFORCED` and defaults off. This is an existing,
documented rollout item rather than a regression caused by this screen.

After store-signed App Attest/Play Integrity traffic is verified and old clients
are accounted for:

```text
COMPREHENSION_AUDIO_APP_CHECK_ENFORCED=false
→ staged canary
→ COMPREHENSION_AUDIO_APP_CHECK_ENFORCED=true
```

Monitor denials and retain a tested rollback. Do not couple this configuration
flip to the UI PR if store-attestation evidence is still blocked.

### Additional implementation rules

- Do not log signed URLs, raw audio, questions, transcripts, summaries or child
  names to Analytics, Crashlytics, debug/error telemetry or audit metadata.
- Avoid auto-play. Require an explicit teacher action and pause audio when the
  app backgrounds; this matters on shared classroom devices.
- Display only bounded, teacher-facing callable errors. Never render raw
  Firebase exception data.
- Keep delete behind a destructive overflow action and include student/date in
  the confirmation. The server remains authoritative and the audit log remains
  content-free.
- When the audio gate turns off, stop playback immediately. Existing retention
  continues and school-admin deletion remains available through the admin
  workflow; do not expose a hidden playback bypass for cleanup.
- Never make AI output a prerequisite for finding, playing or deleting audio.

## 9. Implementation slices

### Slice 1 — feature state and data foundation

1. Add an async/equatable audio availability model with explicit loading,
   enabled, disabled and error states.
2. Exclude demo-preview-only schools from the teacher recording inbox.
3. Add `TeacherComprehensionRecording` and tolerant Firestore parsing.
4. Add the class-scoped, uploaded-only, paged recording provider.
5. Extract the class roster display provider from the AI-specific file.
6. Add/deploy the `comprehensionAudioUploadedAt` composite index.
7. Add provider/model/index tests before UI work.

### Slice 2 — recording-first Bento screen

1. Refactor/rename `ComprehensionReviewScreen` to
   `ComprehensionRecordingsScreen`.
2. Build header, filters, grouped cards, skeleton, empty, error and pagination
   states using flat bordered Bento compartments.
3. Build a recording-first detail sheet using the existing audio service.
4. Make URL resolution lazy; coordinate one active player and pause on lifecycle
   changes.
5. Keep delete server-confirmed; let the live query remove the row.
6. Add semantic labels, 48px minimum touch targets, text-scale resilience and
   non-color status labels.

### Slice 3 — navigation and production availability

1. Add the standard Class-tab Recordings action behind only the audio gate.
2. Remove `hasDevAccess()` and AI entitlement from the recording entry.
3. Rename the Settings row if retained and keep the class picker.
4. Add the new route plus old-route alias/redirect and class/school sanity
   checks.
5. If the gate changes while the route is open, stop playback and render the
   disabled state.

### Slice 4 — isolate and reattach AI

This slice may land structurally while AI remains globally off.

1. Make the client AI gate mirror current server authority requirements.
2. Move AI provider watches into a child subtree created only when enabled.
3. Left-join evaluation status by `logId` onto loaded recording rows.
4. Move existing level/flag filters into an AI-only filter extension.
5. Refactor `ComprehensionEvalSheet` into an optional AI section under the
   recording-first detail sheet.
6. Preserve disclaimers, qualitative-only display and audio-replaced warnings.
7. Add tests proving recordings remain complete and usable with zero eval docs,
   failed evals, removed transcripts and expired AI data.

### Slice 5 — hardening and release evidence

1. Add Firestore Rules query-shape tests and rerun class-isolation suites.
2. Add callable tests for assigned/unassigned/cross-school playback and delete;
   retain canonical-path injection tests.
3. Add signed-URL auth-session cache tests.
4. Run Flutter analysis and targeted widget/provider/service suites.
5. Test real playback on physical iOS and Android builds, including URL expiry,
   backgrounding, headset/speaker changes and account switching.
6. Verify deployed index/rules parity before beta.
7. Keep AI globally/per-school off until the separate legal and release gates
   are approved; do not use this screen release as implicit AI approval.

## 10. Test matrix

### Flutter unit/provider tests

- Audio gate: school off, platform off, missing school setting, loading, error,
  enabled, demo preview-only.
- Recording parser: missing optional context, invalid duration, deleted student,
  future unknown fields.
- Query always includes selected `classId` and `comprehensionAudioUploaded`.
- Paging de-duplicates rows when page 1 changes.
- Sorting uses uploaded timestamp and handles equal timestamps deterministically.
- AI provider is not listened to when any AI authority gate is invalid.

### Widget tests

- Non-dev teacher at audio-enabled school sees and opens Recordings.
- Audio-disabled teacher sees no entry.
- Recording-only card/sheet contains no AI language.
- Empty, filtered-empty, loading, first-page error and load-more error states.
- Detail requires explicit Play; scrolling cards causes zero URL calls.
- Only one recording plays; close/background/account change disposes it.
- URL expiry retries once; denied/unavailable errors stay bounded.
- Delete confirmation includes context, cancel is safe, success removes row and
  failure preserves it.
- AI on/off transition adds/removes only the optional AI section.
- 320px width, tablet width and 200% text scaling produce no overflow.
- Semantics announce student, date, duration, playback state and button purpose.

### Rules and callable tests

- Assigned teacher can run the exact uploaded-recordings class query.
- Same-school unassigned teacher and cross-school teacher cannot query/read the
  other class.
- Teacher query without `classId` is denied.
- Parent cannot read another child's logs or any AI evaluation.
- Direct canonical Storage read remains denied.
- Playback rejects disabled platform/school, unvalidated receipt, wrong class,
  wrong school, absent audio and stale/missing generation.
- Delete remains canonical-path-derived and auditable; injected stored paths are
  never followed.

### Device and operational checks

- Signed iOS and Android builds play real AAC/M4A recordings.
- Shared-device teacher A → sign out → teacher B never reuses A's URL/player.
- Turn platform or school playback off while audio is playing; playback stops
  and subsequent URL minting is denied.
- Delete while another client has the screen open; both reconcile cleanly.
- Recording expires under retention while its detail sheet is open.
- Slow/filtered school Wi-Fi gives a bounded recoverable state, not an endless
  spinner.
- Monitor signed-URL callable latency/errors and Storage egress without logging
  child identifiers or content.

## 11. Release order and rollback

1. Merge and deploy the new Firestore indexes; wait for `READY`.
2. Deploy the Cloud Functions changes so new/replacement uploads start pending
   and every deletion path clears review state.
3. Deploy the Firestore Rules hardening with the current app still compatible.
4. Preview the legacy migration with
   `node functions/scripts/backfill-comprehension-review-state.cjs --school ID`,
   then rerun with `--apply` after checking the counts.
5. Ship the recording-first Flutter UI with AI still globally off.
6. Run one audio-enabled beta class through class isolation, playback, deletion,
   retention-toggle and shared-device checks.
7. Expand to other audio-enabled schools after error/egress metrics remain
   normal.
8. Treat future AI visibility as a separate release decision requiring its own
   legal evidence, production gates and rollback.

Rollback is an app release/config action; do not loosen Storage Rules or callable
authorization to recover from a UI problem. The existing per-student audio path
can remain available during a rollback if its gate is still enabled.

## 12. Acceptance criteria

The recording-first release is complete when:

- a standard non-dev teacher at an audio-enabled school can find the screen from
  the Class tab, select a class and browse its retained recordings;
- the same screen is absent when school audio playback is disabled;
- cards are sourced from reading logs and appear whether or not an AI evaluation
  exists;
- opening/list-scrolling does not eagerly mint URLs, and playback requires an
  explicit action;
- only assigned teachers can query the rows or obtain playback URLs;
- direct Storage reads remain denied;
- deleting audio permanently removes the canonical object and receipt fields,
  preserves the reading log and creates the existing audit entry;
- the AI platform/school/authority gate being off results in zero AI UI and zero
  AI evaluation reads;
- when AI is later enabled, its summary augments the matching `logId` without
  changing recording availability or ordering;
- loading, empty, offline, expired, deleted, unauthorized and partial-page
  failures have bounded teacher-facing states;
- the screen passes small-phone, tablet, text-scale, semantics, physical iOS and
  physical Android checks; and
- no raw recording, signed URL, transcript or AI content appears in telemetry.

## 13. Implemented file impact

- `lib/screens/teacher/comprehension_recordings_screen.dart`
- `lib/data/providers/comprehension_recordings_provider.dart`
- `lib/data/models/reading_log_model.dart`
- `lib/core/widgets/audio/comprehension_audio_player.dart`
- `lib/data/models/school_model.dart`
- `lib/data/providers/comprehension_eval_providers.dart`
- `lib/screens/teacher/teacher_classroom_screen.dart`
- `lib/screens/teacher/teacher_settings_screen.dart`
- `lib/core/routing/app_router.dart`
- `firestore.indexes.json`
- `firestore.rules`
- `functions/src/comprehension_retention.ts`
- `functions/scripts/backfill-comprehension-review-state.cjs`
- Flutter provider/widget/service tests
- `functions/test/firestore.rules.test.js`
- existing audio callable integration tests, extended only where needed

Avoid changing `storage.rules`, the canonical object layout, or the callable
authorization contract unless a failing security test demonstrates a concrete
need.
