# Lumi Security Hardening — Plan & Checklist

**Merged:** 2026-07-15 · combines the detailed technical audit + the plain-English summary into one working document.
**Purpose:** a single source of truth that a later session (or you) can run through top-to-bottom, ticking `[x]` as each fix lands and its **Verify** step passes.
**Scope reviewed:** Flutter app, active `firestore.rules` + `storage.rules`, Cloud Functions, school portal, super-admin portal, repo config, tests. Source-code + config only — the *live* deployed state (rule versions, App Check, IAM, backups, budgets) can't be proven from the repo and is captured in the "Verify outside the repo" section.

---

## How to use this checklist

- Work **P0 → P1 → P2**. Don't tick an item until its **Verify** line passes (a test, an emulator run, or a console check).
- Each item has: **Severity**, **Why it matters** (plain English), **Where** (file:line), **Fix** steps, **Verify** steps.
- `[ ]` = todo, `[x]` = done + verified, `[~]` = in progress / partially done.
- The **New negative-test matrix** near the bottom lists the automated tests that must exist and pass — most fixes should add one or more of them.

## Implementation log / session handoff

### 2026-07-15 — hardening implementation started

- **Current item:** finish P1-3 with a release-device network capture and live App Store/Play questionnaire updates, then finish P1-7 with the Play App Signing certificate, signed-device smoke tests and the remaining artifact/quota evidence; P0-1/P0-5 still need live App Check/IAM/on-device evidence and the full media-decoder decision.
- **Status:** P0-2, P0-3, P0-4, P0-6, P0-7, P0-8, P1-2, P1-5, P1-6 and P1-8 are complete; P0-1/P0-5/P1-3/P1-4/P1-7 are partially implemented. Optional Analytics and Crashlytics now have native and Dart fail-closed defaults, separate adult controls on the shared parent/staff Account screen, no direct account UID, no detailed child-reading attributes, advertising consent permanently denied, and aligned policy/repository label guidance. Privileged audio operations derive the canonical path, cleanup quarantines mismatches, playback/upload fail closed on the recording flag, and App Check options are wired behind `COMPREHENSION_AUDIO_APP_CHECK_ENFORCED`. Client uploads require the owning parent + canonical metadata; `confirmComprehensionAudioUpload` verifies metadata plus the ISO-media byte signature and is the only client-reachable path that stamps server-owned audio receipt fields. The audio handler and real Auth/Functions HTTP emulator paths now have end-to-end negative coverage. Teacher access and client queries are class-scoped, reading-log identity/system fields are immutable, create schemas validate optional values, proxy child/class mismatch is denied, log IDs are random 128-bit values, and comments are schema-checked against their authoritative parent log. Parent memberships can no longer be self-created and public demo enquiries now pass through the App-Check-ready, durably rate-limited `submitDemoRequest` callable; direct client access to `schoolOnboarding` is denied. Mutable portal routes now fail closed if current membership cannot be verified, legacy `/users` writes are terms-only, and mobile dev-access lookup no longer exposes an email-hash oracle. Incremental student/class aggregation is live and fully reconciled; class query batching and local-day removal checks now respect Firestore limits and Australian DST. Dangerous client provisioning and checked-in demo passwords are absent from the release APK. Functions and portal production dependency trees have zero critical/high advisories.
- **Working rule:** changes are being made in checklist order; each completed checkbox will include the verification command/result here or under the item.
- **Baseline before edits:** Firestore rules 125/125, Storage rules 6/6, Functions 109/109, targeted Flutter offline/log tests 40/40. Functions dependency audit: 2 critical, 7 high, 12 moderate, 1 low.
- **Verification so far:** `cd functions && npm run test:functions` → **116/116 passed**; `npm run test:rules` → **136/136 passed**; `npm run test:rules:storage` → **11/11 passed**; `npm run test:audio:integration` → **7/7 passed**; `npm run test:audio:http` → **4/4 passed**; `npm run test:audio:appcheck` → **1/1 passed**; `npm run test:deletion:integration` → **2/2 passed**; targeted Flutter audio/offline tests → **38/38 passed**. Functions build and lint pass (8 existing warnings, 0 errors), and the production dependency audit has **0 critical/high** advisories (8 moderate). Earlier targeted Flutter service/screen suite → **50/50 passed**, onboarding/callable migration suite → **28/28 passed**, mobile dev-access suite → **2/2 passed**, and portal session-policy suite → **2/2 passed**. The Next 15.5.20 production build succeeds. `flutter analyze --no-fatal-infos` → no errors/warnings (**123 existing info lints**). The broad Flutter run reports **400 passed / 8 unrelated UI-test failures**: stale finders in feelings tracker, splash, teacher assignment card, comment chips and week progress bar, plus a pending toast timer in the awards test. Android release APK builds successfully and provisioning/password/private-key scans are clean. Live API-key negative probes reject an unlisted web referrer, iOS bundle and Android signing certificate while accepting every registered Lumi identity; all three current Firebase keys retain their 27-service API allowlist. `git diff --check` and the redacted Gitleaks working-diff scan are clean.
- **Resume point if interrupted:** inspect the latest `git diff`; finish the P1-3 release-device capture, then obtain the Google Play App Signing SHA-1 before producing a store-signed Android build and finish P1-7's IPA/signed-device/quota evidence. Do not rebuild the account/student deletion or audio emulator suites. Audio authorization, canonical-path selection, kill-switch behavior, upload confirmation, deletion and retention are locally covered. Remaining audio work is: enable/prove App Check in staging, prove real Cloud IAM URL signing, test microphone/upload/playback on physical iOS/Android devices, and either add a real media decode/transcode service or formally accept/disable the header-only validator. The P0-7 refreshed-bundle canary is already deployed.

### 2026-07-15 — P1-7 live credential and API-key hardening

- **Legacy admin credential revoked:** The untracked `school-admin-web/service-account.json` contained user-managed key `b7be…1e1b` for the retired `lumi-kakakids` project. Portal runtime code already uses ADC and the configured current-project credential path did not point at this file. The legacy key was disabled, permanently deleted from IAM and removed locally. A no-ignore fingerprint scan found no second workspace/cache copy. Current school-admin, super-admin and marketing endpoints still return HTTP 200.
- **Current Firebase keys restricted:** The iOS key now accepts only `com.lumi.lumiReadingTracker`. The Android key accepts only package `com.lumi.lumi_reading_tracker` signed by the current debug certificate. The browser key accepts the four AU Hosting sites and their `.firebaseapp.com` mirrors, `lumi-reading.com`, the reserved `www` hostname and local development. Positive Identity Toolkit probes returned HTTP 200; an attacker referrer, wrong iOS bundle and wrong Android certificate each returned HTTP 403. All three keys retained their existing 27-service Firebase API-target allowlist.
- **Android release blocker:** `android/app/build.gradle.kts` still signs `release` with the debug key and Firebase has no Play signing fingerprints registered. Before any Play release, configure a protected upload/release signing setup, add the Google Play App Signing SHA-1 to Firebase and the Android API-key allowlist, then repeat the signed-device positive/negative test. Restricting the key only to the known certificate is safe for today's build but intentionally does not pretend a future Play-signed binary is covered.
- **Books key contained:** Current source and local environments contain no `GOOGLE_BOOKS_API_KEY`, and the obsolete project's separate `BOOKS API` key matches neither current nor legacy local Firebase keys. Monitoring showed only six Books API responses across the sampled 90 days with no credential label. The key is now API-target-restricted to `books.googleapis.com`; a Books request succeeds and a non-Books request is rejected with HTTP 403. Confirm no supported legacy app still needs it before deleting it entirely or replacing direct mobile use with a server proxy.
- **Management-plane change:** `apikeys.googleapis.com` was enabled in both projects solely to administer these restrictions. No application data path or client API surface was added.
- **Artifact rescan:** Gitleaks 8.30.1 rescanned all 566 commits plus the unsigned release `Runner.app` bundle and found no leak. A final signed IPA/store artifact scan is still required because signing/export packaging was not available locally.
- **Still open:** scan a final signed IPA/store bundle, repeat Firebase/Auth smoke tests from signed iOS and Android devices, register the Play App Signing certificate, and evidence Firebase Auth/API quotas and abuse alerts. These are why P1-7 remains partial rather than complete.

### 2026-07-15 — P1-3 analytics privacy implementation

- **Runtime defaults:** Android now ships `firebase_analytics_collection_enabled=false`, `firebase_crashlytics_collection_enabled=false`, ad-ID collection false and ad-personalisation false. iOS ships the equivalent Analytics and Crashlytics collection flags false. Dart also defaults both preferences false and applies advertising consent as permanently denied. This is defence in depth against collection before the Flutter UI loads.
- **Adult controls:** The shared parent/staff **Settings → Account → Privacy & diagnostics** screen has independent product-usage and crash-report switches. Choices are device-local and reversible. Analytics withdrawal removes legacy UID/role properties and resets the app-instance ID; Crashlytics withdrawal clears the user identifier and deletes unsent reports.
- **Data minimisation:** The splash flow no longer sends the Firebase UID or role to either SDK. Analytics retains only coarse event names and drops child feeling, book count, reading minutes, badge type, streak count, failure reasons and export counts. Crash calls are suppressed unless collection is enabled.
- **Disclosures:** The public privacy-policy source, `docs/app-store/app-privacy-labels.md` and `ios/Runner/PrivacyInfo.xcprivacy` now match. Labels remain conservatively "Linked to You" because pseudonymous Firebase installation identifiers may identify a device, even though no Lumi account UID is attached.
- **Voice default audit:** `ComprehensionRecordingSettings.defaults()` is false and missing school settings parse false. Production has 5 school documents; 1 has explicitly enabled recording. The platform-wide kill switch is enabled, so this is an available opt-in capability, not a global default-on school setting. Documentary evidence of the enabling school's authority remains an external privacy task.
- **Verification:** diagnostics preference/UI tests **8/8 passed**; targeted analysis has no issues; full analysis has no errors/warnings and the same **123 existing info lints**; school portal TypeScript and Next production builds pass. Clean Android and unsigned iOS release builds succeed. The built Android manifest has Analytics, Crashlytics, advertising-ID collection and ad-personalisation all false; the built iOS app has both collection flags false and a valid privacy manifest. PR **#393** passed required CI and was squash-merged as `6766e63`. The school portal deployed successfully to Node 24 revision `ssrlumischooladminau-00066-yec`; the live policy returns the new off-by-default, withdrawal and no-account-UID text. A release-device traffic capture before opt-in and after each opt-in/withdrawal is still required before P1-3 can be closed.
- **Resume point:** Perform the release-device network capture, ship the mobile changes in the next signed app release, and update the actual App Store Connect / Play Console questionnaires. Do not mark P1-3 complete from source inspection alone.

### 2026-07-15 — audio security local verification completed

- **Coverage added:** `functions/test/comprehension_audio.integration.test.js` exercises the deployed handlers against emulated Firestore/Storage; `functions/test/comprehension_audio.http.integration.test.js` crosses the real emulated Auth token + callable HTTPS boundary; `functions/test/comprehension_audio.appcheck.integration.test.js` proves an authenticated request without App Check is rejected when enforcement is enabled; `test/services/comprehension_audio_service_test.dart` verifies the Flutter callable adapter. Reusable npm scripts are `test:audio:integration`, `test:audio:http` and `test:audio:appcheck`.
- **Security cases passing:** unauthenticated, disabled-feature, wrong-parent, unassigned-teacher and cross-school calls are denied; hostile stored paths cannot redirect playback/deletion/retention; canonical owner uploads succeed; MIME-only junk and metadata mismatches are rejected and deleted; direct Storage reads remain denied; cleanup quarantines legacy mismatches.
- **Bugs found and fixed by the deeper run:** scheduled cleanup could delete data and then fail its audit write because `performedByEmail` was `undefined` (now stored as `null`); the local Firebase CLI 13.35 was incompatible with `firebase-functions` v7 (upgraded to 15.23); audio Firestore sentinels now use the modular `FieldValue`/`Timestamp` imports so the isolated Functions worker does not fail after a destructive operation. Emulator scripts now default to Java 21.
- **Real file check:** a genuine AAC `.m4a` was generated locally with macOS `afconvert`, confirmed by `afinfo` (M4A container, AAC, 48 kHz, about 1.5 seconds), and accepted by `hasIsoMediaFtypSignature`. This proves compatibility with a real M4A header, **not** full decoding or playable-content validation.
- **What local emulators cannot prove:** production `iam.serviceAccounts.signBlob`/signed-URL IAM, genuine Apple/Android App Check attestation, deployed rule parity, physical microphone codecs/permissions/playback, or a decoder/transcoder that has not yet been implemented.
- **Staging prerequisite discovered:** `functions/src/global_options.ts` pins every Gen2 function to `lumi-ninc-au@appspot.gserviceaccount.com`. A separate staging project cannot deploy these functions until that service-account selection is parameterised per project (or an explicit staging account is configured and granted least privilege). Do not point a staging deploy command at production by accident.
- **App Check replay-protection decision:** the server currently turns `consumeAppCheckToken` on with enforcement, while the Flutter wrapper uses the default reusable token and handlers do not reject `request.app.alreadyConsumed`. Before rollout, either use baseline enforcement with token consumption off, or request limited-use tokens via `HttpsCallableOptions(limitedUseAppCheckToken: true)` and explicitly enforce the replay policy. The present mix does not provide meaningful replay protection.

### 2026-07-15 — P1-2 account/student deletion completed

- **Status:** P1-2 is implemented and verified. A shared **Settings → Account** screen now exists for parents and teachers. Both roles can permanently delete their own account; assigned teachers can also select and delete a student from one of their authoritative classes. School admins retain the equivalent portal workflow. Parents are told explicitly that account deletion does not erase the school's child record and must coordinate child-record erasure with the school.
- **Server workflow:** `functions/src/deletion.ts` owns deterministic, idempotent jobs, recent-auth and typed-confirmation checks, class/school authorisation, five-attempt leased retries, sanitized requester-only status, and 90-day minimal completion receipts followed by automatic purge. Direct client reads/writes of `deletionJobs`, deletion-marker writes and student deletes are denied by Firestore rules.
- **Account result:** removes Firebase Auth, all located parent/staff memberships and membership notifications, user/index/feedback/token-adjacent data, guardian links, authored comments, voice recordings and direct attribution. Core school reading events are retained only in de-identified form so deleting a parent's login does not silently destroy the child's educational history. Staff roster/author references are removed or de-identified. The portal's existing 24-hour staff delete/undo markers migrate into this same engine when due.
- **Student result:** removes the student doc/subcollections, reading logs/comments/audio, parent links, class/group/allocation/campaign references, notifications and link codes; guardian Auth accounts are never deleted. The portal hides/decrements a queued student atomically and the worker avoids double-decrementing.
- **Verification:** Functions build/lint pass; helper/full Functions tests **116/116**; dedicated Firestore/Auth/Storage cascade integration tests **2/2**; Firestore rules **136/136**; deletion Flutter service/widget tests **7/7**; targeted changed-file analysis has no issues; portal TypeScript check and production build pass. Full `flutter analyze` still reports only the pre-existing 123 info-level lints.
- **Deployment:** `requestAccountDeletion`, `requestStudentDeletion`, `getMyDeletionStatus` and the updated `processPendingUserDeletions` are active in `australia-southeast1`. Unauthenticated production probes return 401. The insecure legacy `deleteStudentWithCascade` callable was retired after the replacements became active and now returns 404.
- **Resume point if interrupted:** P1-2 needs a signed-in real-device smoke test and staged App Check rollout only; do not re-implement or redeploy the workflow. Continue the main hardening sequence at P1-7, then the remaining live-console controls.

### 2026-07-15 — AI comprehension evaluation Phase 1 deployed inert

- **Scope:** Implemented and deployed only the inert security boundary from `docs/AI_COMPREHENSION_EVAL_CHECKLIST.md`. No STT/LLM SDK, provider call, entitlement or background worker was added.
- **Data boundary:** Evaluations live at `schools/{schoolId}/comprehensionEvals/{logId}`, separate from parent-readable reading logs. Parents cannot read them; assigned teachers must prove `classId` scope; school admins and live read-only impersonation sessions may read; all client writes are denied.
- **Server-only state:** Direct client access is denied for `aiEvalJobs`, `aiQuestionClassifications`, `aiEvalOpsConfig`, and `schools/{schoolId}/adminMeta`. School clients cannot write `settings.aiEvaluation` or the signed-in-readable `platformConfig/aiEvaluation` kill switch. Parent edits to server-captured `comprehensionQuestionText` remain denied by the reading-log update allowlist.
- **Verification:** `cd functions && npm run test:rules` → **145 passed, 0 failed**. Coverage includes own-child parent denial, cross-class denial, class-filter query provability, admin/impersonation reads, settings/adminMeta denial and server-collection write denial. Production index comparison: **60 remote, 0 missing locally**. All six newly pending composite indexes and all four eval-retention field-index variants reached **READY** before rules activation. Active Firestore ruleset `9c65ac25-4a52-46a9-902a-115a2d5fcc34` has the same local/remote SHA-256: `2698760bf82dad3fa20d609d5201f0b5897e162f48eca0587978dc1e8f502824`.
- **Fail-closed state:** Production now has exactly `platformConfig/aiEvaluation {enabled:false}`. Anonymous probes of AI jobs/cache/config return 403. There is still no AI processing code or provider secret deployed.
- **Security gates still open:** Complete the PIA/notice/APP 8 provider work and STT residency go/no-go before sending any child content externally. Keep AI disabled by default. The existing hardcoded production Functions service account still blocks a safe separate-project staging deploy.
- **Resume point:** Continue in `docs/AI_COMPREHENSION_EVAL_CHECKLIST.md` at Phase 0. Do not begin provider-connected Phase 2/3 work until the privacy/go-no-go prerequisites are satisfied.

### 2026-07-15 — AI comprehension Phase 0 Australian STT spike

- **Cloud configuration:** Enabled `speech.googleapis.com` in `lumi-ninc-au` and granted the existing Australian Functions runtime service account `roles/speech.client`. No Anthropic secret, LLM dependency, AI worker or entitlement was added; the production kill switch remains exactly `{enabled:false}`.
- **Regional evidence:** Speech-to-Text V2 requests reached `australia-southeast1`. Google Locations metadata reports `en-AU` `long`/`short` support. A synthetic 6.23-second AAC/M4A was transcribed correctly by `long` without transcoding; `latest_short` returned no transcript for that clip but did transcribe most of a 1.35-second sample. Chirp 2 returned unavailable for the Australian region.
- **Cost/capacity evidence:** Official V2 billing and observed requests use one-second upward rounding (1.35 s → 2 s; 6.23 s → 7 s). Live regional synchronous-recognition quota is 211 requests/minute versus planned `maxInstances=5`; this is enough for the spike, not a substitute for peak load testing.
- **Safety evidence:** Added a synthetic-only adversarial transcript fixture covering injection, prompt exfiltration, off-topic answers, adult prompting, gibberish, empty speech, insufficient evidence and incidental personal information, plus an automated schema/coverage test.
- **Repository verification:** Functions build and `npm run test:functions` pass **118/118**; lint has zero errors and the same eight existing non-null-assertion warnings. JSON validation and `git diff --check` pass.
- **Repository reconciliation:** The isolated evidence/fixture slice is PR #391 from `ai/phase0-go-no-go`; squash-merge only after required CI passes.
- **Decision:** Conditional technical GO for the Australian `long` model path; **NO-GO for production/school processing**. No child audio was tested. Representative authorised recordings, teacher accuracy review, approved PIA/notice/opt-out/no-backfill rules, Anthropic DPA/APP 8/retention/ZDR and cost controls remain release blockers. Full evidence and the working PIA are in `docs/AI_EVALUATION_PLAN.md`.
- **Resume point:** Finish the open Phase 0 gates in `docs/AI_COMPREHENSION_EVAL_CHECKLIST.md`. Do not deploy a provider-connected pipeline or set the kill switch true.

### 2026-07-15 — incremental statistics audit, repair and production reconcile

- **Production audit:** `platformConfig/incrementalAggregation` already had `studentStats:true` and `classStats:true`. All 52 sampled production students had `stats.readingDates`; all 14 classes had `stats.activeStudentIds`. Since the flag update, each hot-path function handled 1,089 HTTP 200 event deliveries with zero error entries.
- **Backfill defect found:** The 12 July scheduled reconcile logged one per-class `INVALID_ARGUMENT` while still recording overall completion. The class query combined 30 student IDs with two statuses, producing 60 normalized disjunctions above Firestore's maximum of 30. The cursor still wrapped to null, so that class would remain stale until another successful pass.
- **Fix:** Both legacy and self-heal class recomputation now share 15-ID batches. Incremental removal checks also convert the school-local reading date to an exclusive UTC range using the school timezone, including Melbourne/Sydney DST transitions, instead of treating local midnight as UTC.
- **Verification:** Functions build and tests pass **123/123**; lint has zero errors and the same eight existing warnings; Firestore rules pass **145/145**; focused Flutter offline queue tests pass **34/34**. Regression tests cover the compound-query budget, Melbourne 23/25-hour DST days, a Sydney summer day and invalid-timezone fallback.
- **Production result:** `aggregateStudentStats`, `updateClassStats` and `reconcileStatsScheduled` were updated in `australia-southeast1`. A controlled scheduled reconcile then processed **52 students and 14 classes with zero error entries**; the student/class cursors both returned to null. P1-5 is complete.
- **Repository reconciliation:** Branch `security/stats-reconcile-disjunction`, PR #392. Squash-merge only after required CI passes.
- **Remaining offline work:** Server receipt timestamps, date bounds, write allowlists, idempotent IDs and parked permission-denied UI state exist and are tested. P1-4 remains partial until concurrent parent/teacher edit behavior and the full airplane-mode → access-revocation → reconnect experience are exercised on physical devices.

---

## Current implementation verdict (plain English)

Lumi's highest-risk access-control findings are now remediated, covered by emulator tests and active in production: teachers are class-scoped, logs/comments are bound to authoritative child/class records, system fields are immutable, audio paths are canonical, uploads are owner-scoped, onboarding is server-owned, and client role/provisioning footguns are removed. Rules still default to deny, roles live in protected membership docs, audio reads remain callable-only, and the deployed security Functions run in Australia.

Lumi is still **not ready to hold production children's data** until the remaining controls are completed and proven in the live project. The main release blockers have shifted to production App Check enforcement, signed-device analytics/privacy evidence, Play signing, backup/budget evidence, and offline/timezone conflict testing. Account/student deletion and audio callable authorization are deployed but still need signed-in/on-device smoke tests. Audio should also gain full media decode/transcode validation (or remain disabled) before broad use.

| Area | Status | One-line |
|---|---|---|
| Firestore rules | 🟢 repo / 🟢 live | 145 emulator tests pass; active production source hash exactly matches the reviewed local rules. |
| Cloud Storage | 🟢 rules / 🟠 controls | Active rule hash matches local; full decode and live App Check/IAM/on-device evidence remain. |
| Children's privacy | 🟠 | Account/student deletion is deployed; optional diagnostics now fail closed with no Lumi UID, but signed-device traffic and store disclosure evidence remain. |
| App Check | 🟠 | Wired into every sensitive fn, enforcement defaults off everywhere. |
| Offline sync | 🟡 | Server receipt/date bounds, durable queue and AU/DST stats are covered; concurrent-edit and physical reconnect UX still need device testing. |
| Scaling & cost | 🟡 | ~3–4 reads/write in rules; unbounded portal queries; no budget alert. |
| Ops | 🟠 | Force-update + crash reporting exist; no evidenced backups/PITR/budget/incident readiness. |

No anonymous Firestore/Storage data path was found in the active rules. Public enquiries now use a validated, rate-limited callable. The remaining risk is primarily **privacy, live-control verification, credential operations, offline correctness and operational readiness**; for children's data those gaps remain release-blocking.

---

## What's already solid (don't re-litigate)

- [x] **Roles are server-side, not client-writable.** Role from `schools/{id}/users/{uid}.role`; self-update pins `role`/`schoolId` (`firestore.rules:308-309`); teacher self-provisioning removed (#383). Document-roles instead of custom claims is fine *because the field is locked*.
- [x] **Subcollections have explicit rules** (`comments`, `notifications`, `readingLevelEvents`) — no reliance on inheritance.
- [x] **Paid-access gate fails closed** — `studentAccessLive` (`firestore.rules:134-138`) denies on missing `access`.
- [x] **Audio read is denied** (`storage.rules`) and the app fetches via the class-authorised `getComprehensionAudioUrl` callable, which derives the canonical path. *(Callable integration is locally covered; production App Check and signer IAM remain under P0-1.)*
- [x] **Streaks are server-authoritative** (`functions/src/streak_refresh.ts`, `dateUtils.ts`); client `DateTime.now()` is display-only.
- [x] **No admin keys or ad/attribution SDKs in the app.** `firebase_options.dart` = public client keys only; no AdMob/AppsFlyer/Adjust/Facebook/Segment; SendGrid via Firebase secret params.
- [x] **Rules default-deny and are in Git**; `firebase.json` points at the active files.

---

## P0 — Release-blocking (before any real child data or external beta)

### `[~]` P0-1 · Audio signing/deletion trusts a client-editable path (confused deputy)
- **Severity:** Critical
- **Why:** `getComprehensionAudioUrl` signs a read URL for whatever path is stored on the log doc, after only a same-school role check — it never checks the path is inside that school's folder. Because the log's audio-path field is editable (P0-2) and signed URLs bypass Storage rules, a teacher can point it at another object (incl. `schools/{otherSchool}/comprehension_audio/...`) and read another school's child-voice recording.
- **Where:** `functions/src/comprehension_retention.ts:368,381` (sign), `:~260` (delete), `:~100-120` (scheduled cleanup); enabled by editable field at `firestore.rules:562-568`.
- **Fix:**
  - [ ] Consider disabling the comprehension-audio feature (kill switch) until this ships and is tested.
  - [x] Never read the object path from the doc for a privileged op. Derive it: `const expectedPath = \`schools/${schoolId}/comprehension_audio/${logId}.m4a\`;`
  - [~] Add App Check enforcement to both audio callables. *(Wired behind `COMPREHENSION_AUDIO_APP_CHECK_ENFORCED`; actual production enforcement belongs to the staged P1-1 rollout.)*
  - [x] Make the audio fields (`comprehensionAudioPath`, `comprehensionAudioUploaded`) server-owned.
  - [x] In cleanup, reject any legacy row whose stored path ≠ the canonical path before deleting.
- **Verify:**
  - [x] Test: a teacher who rewrites `comprehensionAudioPath` to another school's path gets denied / a URL only for their own school's object. *(Handler integration proves playback and deletion select only the canonical School-X path; real callable HTTP integration proves a School-Y Auth token is denied.)*
  - [x] Test: "School X cannot access School Y, including through an injected audio path" (see test matrix). *(Storage 11/11, handler integration 7/7, callable HTTP 4/4.)*
### `[x]` P0-2 · Reading-log writes permit mass assignment / forged stats
- **Severity:** High
- **Why:** Update only re-checks minutes — an owner or any school teacher can later change `studentId`, `classId`, `parentId`, `createdAt`, date, status, validation and audio fields. The old `parentId` still passes the ownership test while the new child/date/status corrupts another student's totals and streak. Create doesn't pin `schoolId` to the path, bind `classId` to the student's real class, restrict fields/types, or require server time.
- **Where:** create `firestore.rules:531-540`; update `:562-568`; stats consume supplied fields at `functions/src/stats_aggregation.ts:109-122`, `:278-348`; client writes `DateTime.now()` in `lib/services/reading_log_service.dart`.
- **Fix:**
  - [x] **Update:** split into narrow ops with an allow-list + immutable identity/system fields:
    ```rules
    request.resource.data.diff(resource.data).affectedKeys()
      .hasOnly(['minutesRead','bookTitles','feeling','notes','updatedAt'])
    && request.resource.data.studentId == resource.data.studentId
    && request.resource.data.classId  == resource.data.classId
    && request.resource.data.parentId == resource.data.parentId
    && request.resource.data.createdAt == resource.data.createdAt
    && request.resource.data.updatedAt == request.time
    ```
  - [x] **Create:** allow only a documented schema; check types/enums/sizes; require `schoolId == schoolId`; load the student and require the real class; use `request.time` for receipt fields. *(Parent and teacher-proxy branches now share one schema evaluation, avoiding the 1,000-expression ceiling; optional lists/strings/maps/booleans/timestamps are bounded and malformed cases are denied.)*
  - [x] Keep validation / aggregate / access / audio fields server-only.
  - [x] Use a random idempotency UUID as the doc ID, not a millisecond timestamp. *(128-bit `Random.secure()` hex ID; 100-ID uniqueness/shape regression passes.)*
- **Verify:**
  - [x] Test: parent cannot change `studentId`/`classId`/`parentId`/school/author/createdAt/status/validation/stats/audio fields.

### `[x]` P0-3 · Teachers have school-wide child access, not class access
- **Severity:** High
- **Why:** Teacher reads/writes are gated on "is a teacher at this school?", not "does this teacher teach this child?". A Class-A teacher can query and alter Class-B children, logs, comments, allocations and groups. Class docs themselves *do* check `teacherId`/`teacherIds` — the pattern just isn't applied elsewhere. Conflicts with the privacy policy ("that child's teachers", `school-admin-web/src/app/legal/privacy/page.tsx:110-113`).
- **Where:** students `firestore.rules:418-447`; logs `:516-568`; comments `:597-634`; allocations `:628-635`; reading groups `:649-653`. Correct pattern to copy: `:475-496`.
- **Fix:**
  - [x] Use `teacherTeachesClass()` for every teacher read/write involving a child; bind each student/log/comment/allocation/group to a class and verify it. Admins keep school-wide access.
  - [x] Update teacher **queries** in the app/portal to include an allowed `classId` condition (rules aren't query filters — an over-broad query fails closed once the rule tightens). *(Teacher screens/services audited; history, dashboard, student/group detail and library assignment listeners are class-scoped. School/super-admin portals intentionally retain school-wide access.)*
- **Verify:**
  - [x] Tests: Class-A teacher cannot get/list/update/delete Class-B students/logs/comments/allocations/groups; School-X staff cannot reach School-Y; admin retains whole-school access. *(Firestore Emulator 131/131; audio callable remains tracked under P0-1.)*

### `[x]` P0-4 · Teacher proxy log doesn't prove the child is in the class
- **Severity:** High
- **Why:** Proxy-log create proves the teacher teaches the submitted `classId`, but never that the submitted `studentId` belongs to that class — so a teacher can pair their own class ID with any child in the school. The existing negative test only checks a *wrong* class ID, not this mismatched pair.
- **Where:** `firestore.rules:551-560`.
- **Fix:**
  - [x] Load the student and require `student.classId == request.resource.data.classId` (and/or membership in the class's `studentIds`).
- **Verify:**
  - [x] Test: proxy log denied when child and class don't match. *(Firestore Emulator 127/127.)*

### `[~]` P0-5 · Storage uploads/overwrites authorised only by sign-in
- **Severity:** High
- **Why:** Any authenticated account can create/overwrite any community cover, or drop/replace any school's comprehension recording (<2 MB, `audio/*`). MIME type is user-controlled metadata, not proof of content. Storage requests are independent of Firestore, so "enforced app-side" doesn't hold. Current Storage tests *assert* this broad behaviour and have no cover / cross-tenant cases.
- **Where:** `storage.rules:7-24` (covers), `:44-61` (audio).
- **Fix:**
  - [~] Prefer a callable / signed-upload flow that derives a canonical path after checking the log + owner. *(Upload remains direct but owner/canonical path are enforced; new server receipt callable validates metadata before stamping the log.)*
  - [x] If keeping client upload: rules must consult Firestore membership/log, permit only the linked parent who owns that log, check the exact filename, use create-only where possible, and make teachers class-scoped.
  - [~] Enforce the comprehension kill switch server-side; validate real media after upload and delete rejected objects. *(Kill switch, metadata/size/content type and ISO `ftyp` byte signature are server-enforced; rejected objects are deleted. Full media decoding/transcoding remains.)*
- **Verify:**
  - [x] Tests: authenticated outsider cannot upload/overwrite covers or any school's audio; disabled-audio flag blocks upload + URL mint + processing. *(Storage 11/11 and handler integration 7/7; disabled confirmation/playback fail closed and rejected content is deleted.)*

### `[x]` P0-6 · Comments not bound to their parent reading log
- **Severity:** High
- **Why:** Comment access trusts denormalised `studentId`/`parentId`/`authorRole`/`logId` independently instead of loading the parent log and comparing. A linked parent can comment under another known log while supplying their own child's ID; a teacher can post under any school log and target denormalised parent data (which feeds notifications).
- **Where:** `firestore.rules:597-622`; mirror/notify in `functions/src/index.ts`.
- **Fix:**
  - [x] Bind every comment to an existing log: same child, same school/class, expected parent recipient, caller ID, bounded body, allowed keys, `createdAt == request.time`. Apply the same class-teacher check.
- **Verify:**
  - [x] Test: comment denied when its child/parent doesn't match the containing log. *(Also denies extra fields; Firestore Emulator 131/131.)*

### `[x]` P0-7 · Vulnerable production dependencies in Cloud Functions
- **Severity:** High
- **Why:** `npm audit --omit=dev` in `functions/` (15 Jul 2026) = **22 advisories: 2 critical, 7 high, 12 moderate, 1 low**. Critical chains: `fast-xml-parser`, `protobufjs`; high: `@grpc/grpc-js`, Axios, `jws`, `node-forge`, Express/path-matching, `form-data`. Internet-facing privileged functions shouldn't ship an untriaged critical tree.
- **Where:** `functions/` dependency tree.
- **Fix:**
  - [x] Upgrade supported Firebase/Admin + direct packages; review breaking changes; rebuild. *(A non-breaking lockfile refresh removed the vulnerable transitive chains; Firebase Admin's remaining major upgrade is tracked for the 8 moderate findings.)*
  - [x] Re-run `npm audit`; run all function/rules tests; canary deploy. *(Audit + tests/build pass. The refreshed bundle was canary-deployed through security Functions in Phase 1 and the statistics Functions in P1-4/P1-5; all are active.)*
  - [x] Re-run the portal audit with a working registry (pnpm endpoint returned HTTP 410 — not "clean"). *(Generated a temporary npm lock for audit compatibility, upgraded Next 15.5.7 → 15.5.20, and rebuilt successfully.)*
- **Verify:**
  - [x] `npm audit --omit=dev` shows 0 critical/high (or documented, unreachable exceptions); full suite green. *(Functions: 8 moderate, 0 high/critical; portal: 2 moderate, 0 high/critical.)*

### `[x]` P0-8 · Remove permissive-rule instructions and release provisioning/test code
- **Severity:** High (dangerous production capability) / Medium (test-cred)
- **Why:** A forgotten temporary `allow read, write: if request.auth != null` would expose the whole DB. A hidden in-app "Create Admin Account" workflow + client-side test-data seeding is a dangerous release capability (currently gated by the dev allow-list + bootstrap conditions, so **not** a confirmed unauth takeover, but it can create orphan Auth accounts). Checked-in demo/review passwords aren't made safe by nightly rotation.
- **Where:** `FIRESTORE_RULES_TESTING.md` (permissive-rule how-to); `lib/screens/auth/login_screen.dart:564-630`, `:1343-1369`; `lib/utils/setup_test_data.dart`; `scripts/seed_demo_school.js:151` + the other review-account default password.
- **Fix:**
  - [x] Rewrite `FIRESTORE_RULES_TESTING.md` so tests use only the emulator; delete the deploy-permissive-rules procedure.
  - [x] Strip test/provisioning code from release builds; do provisioning only in an audited server/admin tool. *(Removed `TestDataSetup`, the hidden dev admin creator, the public registration route, and the demo-request jump into client provisioning. Demo requests now stop for staff review.)*
  - [x] Generate random initial demo/review passwords via secret/interactive input; rotate existing; never print in CI logs. *(Seed/restore scripts require ≥16-character environment/CLI secrets; checked-in defaults and password output were removed.)*
  - [x] Archive / clearly mark non-deployable the stale `firestore.rules.production`, `firestore.rules.nested`, `firestore.rules.backup`, `firestore.indexes.json.backup`, `firestore.indexes.nested.json`.
- **Verify:**
  - [x] Release build has no admin-creation path; grep for permissive-rule string returns only emulator context. *(Release APK built successfully; binary scan confirms the client-provisioning symbols/routes and old passwords are absent. The sole permissive-rule literal is the checklist's historical finding.)*

---

## P1 — Before store submission / production launch

### `[ ]` P1-1 · Enable + enforce App Check; add durable rate limits + abuse alerts
- **Severity:** High (control gap)
- **Why:** `firebaseConfig` is public; App Check is the control that raises the cost of scripted abuse. It's wired everywhere but enforcement defaults off, and several public paths are unprotected: `verifySchoolCode` is callable without auth + no durable rate limit; SMS helper defaults disabled + fails open on internal errors; anonymous `schoolOnboarding` writes have no rate limit / allow-list / size cap / `createdAt == request.time`; any signed-in account can create unlimited tenants then self-bootstrap as admin.
- **Where:** `lib/core/services/app_check_service.dart:25-30`; `scripts/flutter-build.sh:34-36` (+ `.dart_define.json`); `*_APP_CHECK_ENFORCED` flags in `marketing_leads.ts`/`sms_rate_limit.ts`/`mfa_enrollment.ts`/`parent_linking.ts`/`impersonation.ts`/`school_resolution.ts`; `firestore.rules:749-780` (onboarding), `:236-238`+`:284-295` (tenant + self-admin).
- **Fix:**
  - [ ] Activate App Check in release builds; watch metrics; then enforce on Firestore, Storage, Auth and every callable that supports it. Make the release build fail if the flag is omitted.
  - [ ] Put public forms behind rate-limited callables (IP/device/email buckets, bot protection, payload limits, server timestamps).
  - [ ] Use high-entropy, short-lived join codes with attempt limits.
  - [ ] Fail **closed** for security gates, with an explicit operational override instead of silent fallback.
- **Verify:**
  - [ ] Test: missing/invalid App Check token is denied after rollout.
  - [ ] Console: App Check enforced for Firestore/Storage/Auth/Functions; enforcement metrics healthy.

### `[x]` P1-2 · Real end-to-end in-app account/student deletion
- **Severity:** High (compliance + store-blocking)
- **Why:** `deleteAccount()` deletes only top-level `/users/{uid}` + Auth (memberships live under `/schools/.../users|parents`) and has **no call site**. `deleteStudentWithCascade` / `processPendingUserDeletions` don't cover the full log/comment/audio/class/notification footprint. Apple + Google require in-app deletion; the privacy policy promises deletion/de-identification on request.
- **Where:** `lib/services/firebase_service.dart:238-252`; `functions/src/index.ts` (`deleteStudentWithCascade`, `processPendingUserDeletions`); policy `school-admin-web/src/app/legal/privacy/page.tsx:147-165`.
- **Fix:**
  - [x] Build one server-owned, idempotent deletion workflow with a data inventory + visible job status: Auth, every membership/index, children + parent links, logs, nested comments, notifications/tokens, offline/widget data, audit-safe tombstones, Storage objects. *(The local/offline/widget caches are cleared through the existing shared sign-out flow after account completion; student deletion is server-owned and invalidates the deleted remote record.)*
  - [x] Add an in-app request/initiation surface (settings screen). *(Shared Account screen linked from both parent and teacher Settings; exact `DELETE` confirmation for accounts, plus exact full student name for student data.)*
  - [x] Document legal retention exceptions, authorisation, school coordination, completion evidence. *(Parent account deletion de-identifies rather than destroys the school's core child reading event; assigned teacher/school-admin scope is re-checked server-side; minimal job receipts auto-purge after 90 days.)*
- **Verify:**
  - [x] Test: deletion removes all intended docs, nested comments, indexes, tokens and objects, and is safe to retry. *(Dedicated Firestore/Auth/Storage emulator integrations 2/2; deterministic/due/status helpers 3/3; rules 136/136; Flutter deletion service/UI 7/7.)*

### `[~]` P1-3 · Analytics privacy-by-default + accurate policy
- **Severity:** High (compliance)
- **Why:** `main.dart:144-173` starts Analytics + Crashlytics before UI; `analytics_service.dart:23-37` auto-enables in prod; `:43-108` links events to the Firebase UID and records child reading attributes (feeling, book count, minutes, badges, streaks) with no consent/opt-out. Policy calls this "aggregate" (`.../privacy/page.tsx:170-174`) — inaccurate while events are UID-linked.
- **Where:** as above.
- **Fix:**
  - [~] Default child-related Analytics + voice collection **off**; document necessity; obtain school/parent authority; support withdrawal. *(Analytics/Crashlytics now default off with separate adult withdrawal controls. Per-school voice settings default off and recording remains an optional parent action; production has 1/5 schools enabled, but documentary authority for that school must be verified outside the repo.)*
  - [x] Remove direct UID linkage + detailed child attributes unless demonstrably necessary. *(No account UID/role is attached; detailed reading, badge, streak, error-reason and export-count parameters were removed.)*
  - [~] Verify actual Firebase SDK network traffic vs App Store/Play privacy labels (`docs/app-store/app-privacy-labels.md`). If using Apple Kids Category, apply its third-party-analytics restrictions. *(Native defaults and the built Android manifest are verified; repository labels/policy are aligned and conservative. Release-device capture plus the live store questionnaires remain.)*
  - [~] Before any AI/LLM analytics: complete a PIA (purpose, fields, training use, retention, subprocessors, offshore access, deletion, AU residency). *(A working PIA and AU STT evidence exist in `docs/AI_EVALUATION_PLAN.md`; legal/school approval and provider contractual gates remain, and production AI is disabled.)*
- **Verify:**
  - [ ] Runtime capture confirms no child data leaves before consent; labels/policy match traffic.

### `[~]` P1-4 · Offline: server receipt time, validated local dates, conflict policy
- **Severity:** Medium
- **Why:** The original implementation used client time for audit fields, lacked date bounds, silently dropped failed queue items and treated a school-local date as UTC during incremental removals. Those paths are repaired. The remaining risk is product-level concurrent parent/teacher edit policy plus real-device reconnect UX.
- **Where:** `lib/services/reading_log_service.dart`; `functions/src/stats_aggregation.ts:324-335`.
- **Fix:**
  - [x] Store a trusted `receivedAt` server timestamp; keep a separate validated local reading date with an allowed backdate/future-skew window. *(`createdAt` is the server receipt timestamp and must equal `request.time`; the user-selected `date` is separately bounded to 366 days back / 1 day forward.)*
  - [~] Define which fields may be edited by whom; use idempotency IDs; surface rejected queued writes. *(Rules enforce identity/system-field immutability and content allowlists; random 128-bit log IDs make replays idempotent; server receipts prevent silent drops; persistent denials park and surface in service status. The explicit concurrent parent/teacher policy and real-device UX test remain.)*
  - [x] Convert school-local day boundaries to UTC using the school timezone; add DST regression tests. *(Exclusive UTC bounds now cover 23/25-hour Melbourne DST days and Sydney summer time.)*
- **Verify:**
  - [~] Tests: dates around Melbourne/Sydney midnight + DST preserve the correct local streak; offline write made before access revocation is rejected and clearly surfaced after reconnect. *(Date/stats unit tests, Firestore revocation denials 145/145 and offline permission-denied parking 34/34 pass. Repeat the combined scenario on physical iOS/Android before marking complete.)*

### `[x]` P1-5 · Confirm incremental-aggregation flags + backfill before load
- **Severity:** Medium (cost/correctness)
- **Why:** Config defaults to legacy/full recomputation when flags are missing; legacy triggers can query *all* logs for a student/class after each write.
- **Where:** `functions/src/stats_aggregation.ts` (flag `platformConfig/incrementalAggregation`).
- **Fix:**
  - [x] Confirm prod flags + backfill are enabled before load. *(Both production flags are true. Seed fields were present on all 52 students and 14 classes checked; a controlled full reconcile completed after repairing the compound-query batch bug.)*
- **Verify:**
  - [x] Console/flag read shows incremental on; spot-check a write triggers incremental, not full recompute. *(Production flag read is true/true; each hot-path function processed 1,089 event deliveries with HTTP 200 and zero error entries after enablement; controlled reconcile processed 52 students/14 classes with zero errors and null completion cursors.)*

### `[x]` P1-6 · Lock down self-service tenant / parent / onboarding creation
- **Severity:** Medium
- **Why:** A signed-in user can self-create an empty parent membership for any known school ID (`firestore.rules:341-366`) → school-member reads (school doc, books) *before* a valid child-link. The anonymous `schoolOnboarding` rule accepts arbitrary extra fields + user timestamps and its update rule permits broad mutation.
- **Where:** `firestore.rules:341-366` (parent self-create), `:749-780` (onboarding).
- **Fix:**
  - [x] Create parent membership only inside the server-side verified linking transaction.
  - [x] Retire the direct-client onboarding path; use the validated/rate-limited server API only. *(Demo enquiries use `submitDemoRequest`; it validates and bounds the payload, writes the timestamp server-side, applies durable IP/email rate limits, and supports staged App Check enforcement.)*
- **Verify:**
  - [x] Test: signed-in user cannot self-create a parent membership without a verified link; all direct client reads/writes to onboarding are denied. *(Firestore Emulator 131/131; onboarding/callable client migration 28/28; Functions 113/113.)*

### `[~]` P1-7 · Secret scan + rotate demo/review defaults
- **Severity:** Medium
- **Why:** The initial audit found an active old-project admin credential on disk, incompletely restricted public client keys and missing artifact evidence. Demo/review credentials also needed to fail closed instead of falling back to checked-in passwords.
- **Where:** `scripts/seed_demo_school.js:151` + review-account script; the now-removed `school-admin-web/service-account.json`; Firebase API Keys/IAM consoles.
- **Fix:**
  - [~] Run a history-aware secret scanner (e.g. Gitleaks) in CI; scan built APK/IPA/web artifacts, not just source. *(Gitleaks 8.30.1 rescanned 566 commits after reviewed false-positive fingerprints: clean. A pinned redacted GitHub workflow and reusable `scripts/security/scan-secrets.sh` were added. The release APK, unsigned iOS `Runner.app`, portal server output and portal static output contain zero private keys. A final signed IPA artifact was not available to scan.)*
  - [x] Remove checked-in demo/review password defaults. *(Both seed paths require a password-manager-supplied `DEMO_PASSWORD` of at least 16 characters; the demo workflow rotates shared passwords daily. Release-artifact scans found no provisioning password.)*
  - [x] Rotate the `lumi-kakakids` key; move the portal to Application Default Credentials / Secret Manager. *(Portal code uses ADC only and does not load a repository JSON credential. The exposed user-managed old-project key was disabled, deleted from IAM and removed locally; a no-ignore fingerprint scan found no cached copy.)*
  - [~] Restrict Firebase browser/iOS/Android API keys by bundle ID/package/signing cert/API/quota in GCP. *(Browser, iOS and the currently debug-signed Android build are platform-restricted and retain the 27-service Firebase API allowlist. The separate old Books key is now target-restricted to Books only. Add the Play App Signing SHA-1 and evidence quota/abuse-alert settings before closing.)*
- **Verify:**
  - [~] Gitleaks CI green on history + artifacts; portal boots without a repository JSON key. *(Local history and available deploy-artifact scans are green; required Gitleaks CI has passed on the prior hardening PRs; current portal/admin/marketing endpoints return 200 after key revocation. Live Identity Toolkit probes accept registered web/iOS/Android identities and reject unregistered ones with 403. Await a signed IPA/store scan, Play App Signing registration, signed-device smoke tests and quota/alert evidence.)*

### `[x]` P1-8 · Misc session / legacy-doc hardening
- **Severity:** Medium
- **Fix:**
  - [x] Portal session: `school-admin-web/src/lib/auth/session.ts` keeps a valid JWT on Firestore read failure — make privileged mutable routes fail **closed** (a narrow cached read-only fallback may be OK). *(Every ordinary mutation route opts into `requireMutable`; read-only JWT fallback remains available.)*
  - [x] Top-level `/users/{uid}` lets a user write arbitrary fields incl. `role` (`firestore.rules:742-746`) — not used for school authz today, but make it server-owned / limit self-writable fields so it can't become a future escalation source. *(Create/delete denied; legacy self-update is limited to validated, server-timestamped terms acceptance.)*
  - [x] `devAccessEmails/{sha256(email)}` is a probe-able email oracle (`firestore.rules:926-928`) — restrict the callable result to the caller's own token email. *(All direct client access denied; `checkDevAccess` accepts no candidate email/hash and derives it from the verified Auth token.)*
- **Verify:**
  - [x] Test: deactivated/demoted user cannot use an old portal/app session; `/users` self-write can't set a privileged field. *(Portal session policy 2/2; Firestore Emulator 133/133; mobile callable migration 2/2; Functions 113/113; portal production build passes.)*

---

## P2 — First production month (retain evidence)

- `[ ]` **P2-1 Budgets + dashboards.** Cloud Billing budgets/alerts, per-service anomaly monitoring, quotas, security/cost dashboards. Alert on reads/writes/egress/functions/SMS/Storage.
- `[ ]` **P2-2 Backups + restore drill.** Enable Firestore PITR and/or scheduled exports with retention; perform a timed restore drill; record recovery time + data loss.
- `[ ]` **P2-3 Privacy program.** Complete a Privacy Impact Assessment, vendor/data-flow register, and a breach tabletop exercise.
- `[ ]` **P2-4 Cost/scale.** Load-test dashboards + rules billing at 30/100/1,000-student schools; paginate/limit queries; replace global fallback scans (`resolveUserSchoolByUid` unbounded collection-group fallback) with a server-owned UID index; verify listeners are disposed; materialise dashboard summaries; avoid hot counters + sequential IDs. Note: the service-health controller forces a billable read every 180s per foreground app (rule comment still says 30s).
- `[ ]` **P2-5 Device + error-path testing.** Old iPads / low-end Android; offline/DST/date-tamper; account revocation; force-upgrade (make it fail into a support mode when version config is unavailable + configure store URLs); no-network, expired-session, empty-class, denied-camera, book-not-found/manual-entry paths on real devices.
- `[ ]` **P2-6 Recurring reviews.** Schedule dependency, rules and privacy reviews for every release that changes auth, child data, Storage, analytics or vendors.

---

## Verify outside the repo (console / IAM / ops — can't be proven from code)

- `[x]` Deployed `firestore.rules` + `storage.rules` **exactly match** the reviewed source. *(Rules API source hashes: Firestore local/remote `2698760b…502824`; Storage local/remote `10802186…825c`. Source consolidated and squash-merged through PR #390 after Gitleaks CI passed.)*
- `[ ]` App Check registration + metrics + enforcement (Firestore, Storage, Auth, Functions).
- `[ ]` Firestore/Storage/Auth/Functions resource locations + cross-border support/data flows are AU.
- `[ ]` Least-privilege IAM + service-account permissions.
- `[~]` Google API-key restrictions, Firebase Auth quotas, SMS abuse alerts. *(Browser/iOS/current Android identities and API targets are restricted and live negative tests pass. Add the Play signing SHA-1, then evidence Auth quotas and SMS abuse alerts.)*
- `[ ]` Cloud Billing budgets/alerts + per-service anomaly monitoring.
- `[ ]` Firestore PITR/scheduled backups + retention + a successful timed restore drill.
- `[ ]` Production logs/alerts for denied writes, function errors, deletion jobs, audio access, auth spikes, spend.
- `[ ]` Stable privacy/terms/support URLs + a monitored support mailbox.
- `[ ]` Written, exercised data-breach plan aligned with the OAIC Notifiable Data Breaches scheme.
- `[ ]` App Store / Play privacy disclosures match runtime SDK traffic.

---

## New negative-test matrix (each line = one automated test that must pass)

- `[x]` Class-A teacher cannot read/write Class-B student, log, comment, allocation, group, AI eval or audio. *(Firestore 145/145; audio handler integration denies unassigned teachers.)*
- `[~]` Parent-A cannot read/write Parent-B's child, log, comment or audio. *(Cross-parent log delete and audio upload are covered; retain partial until one consolidated get/list/write matrix test covers every record type.)*
- `[x]` School-X cannot access School-Y, including through an injected audio path. *(Firestore/Storage, handler integration and real callable HTTP boundary all pass.)*
- `[x]` Parent cannot change `studentId`, `classId`, `parentId`, school, author, created time, status, validation, stats or audio fields.
- `[x]` Teacher proxy log denied when child and class don't match.
- `[x]` Comment denied when its child/parent doesn't match the containing log.
- `[x]` Authenticated outsider cannot upload/overwrite covers or any school's audio.
- `[x]` Disabled-audio flag blocks upload, URL minting and processing server-side. *(Storage rule and handler integration tests pass.)*
- `[ ]` Expired/deactivated teacher cannot use an old portal/app session.
- `[~]` App Check missing/invalid token is denied after rollout. *(Missing token with enforcement enabled passes locally 1/1; a genuine registered-device token and invalid-token rejection still need staging.)*
- `[ ]` Offline write made before access revocation is rejected and clearly surfaced after reconnect.
- `[x]` Deletion removes all intended documents, nested comments, indexes, tokens and objects, and is safe to retry. *(Dedicated Firestore/Auth/Storage cascade integrations 2/2 plus deterministic retry/status helpers 3/3.)*
- `[ ]` Dates around Melbourne/Sydney midnight + DST changes preserve the correct local streak.

---

## Baseline test/tool results (15 Jul 2026 — reference)

| Check | Result | Interpretation |
|---|---:|---|
| Firestore Emulator rules | 125 passed | Baseline only; cross-class/mass-assignment/comment-binding negatives absent. |
| Storage Emulator rules | 6 passed | Cover audio shape + direct-read denial; assert broad upload, omit cover/cross-tenant. |
| Cloud Functions unit/build | 109 passed | Helper correctness only; audio-path exploit not covered. |
| Flutter offline/log tests | 40 passed | Good queue coverage; clock/DST/two-device conflict cases remain. |
| Flutter static analysis | 141 info lints | No error/warning; informational debt. |
| Functions prod dep audit | 22 advisories | 2 crit, 7 high, 12 mod, 1 low. |
| Portal dep audit | Inconclusive | pnpm endpoint HTTP 410; re-run with a working tool. |
| Secret pattern scan (tree) | No private key | Demo defaults + public client keys remain; history/artifacts unscanned. |

---

## Australian children's-privacy context (draft OAIC Children's Online Privacy Code)

Exposure draft released 31 Mar 2026; expressly covers examples like online school-management systems that monitor student performance; calls for strictly-necessary processing + high-privacy-by-default; requires a PIA before significant child-data changes; proposes prompt destruction (normally ≤30 days). Still a draft — details/commencement may change. **Don't assume the small-business turnover exemption applies** (Act has exceptions; school + Victorian public-sector contracts may bind regardless). Get Australian privacy advice for Lumi's exact entity/customers/data flows.

Before launch Lumi should have: a data inventory + child-data purpose/necessity table; high-privacy defaults (voice + analytics off by default); a published PIA/register process; working access/correction/deletion/destruction workflows with deadlines; school-facing answers on Firebase subprocessors, overseas processing, support access, retention, deletion, encryption, AU resource locations; SDK/runtime network verification matching policy + store labels; a child-safe support/escalation procedure with verified authority for parent/school requests.

---

## Final assessment

Lumi's foundation is recoverable and several strong controls are present, but the current authorisation model stops at the school boundary — too broad for child data. The fastest safe route: make **`school → class → child → record/object`** the common binding everywhere, keep client-editable fields intentionally small, derive privileged object paths server-side, and prove the denial cases in the emulator. Land deletion, privacy-by-default analytics and the operational controls before launch — not as post-launch paperwork.
