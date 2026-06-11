# Pre-Release Notes

Tasks that are intentionally deferred and should be revisited before a major
release / production rollout. Each entry is self-contained so it can be picked
up later without re-reading whatever conversation prompted it.

---

## App Check enforcement (deferred from the scale-safety plan, 2026-06-10)

**Why deferred:** the Flutter wiring is complete but flipping enforcement is
known to be a painful rollout (debug-token registration, version-gating old
clients, false-positive risk across four services). Wanted to ship it on its
own once everything else is stable so we can give it the attention it needs.

**Current state** ([lib/core/services/app_check_service.dart:27-30](lib/core/services/app_check_service.dart#L27-L30)):
- `LUMI_APP_CHECK_ENABLED` dart-define defaults to `false`
- Providers wired for all platforms (Play Integrity, App Attest + DeviceCheck fallback, reCAPTCHA Enterprise for web) at [lines 45-55](lib/core/services/app_check_service.dart#L45-L55)
- Server-side `IMPERSONATION_APP_CHECK_ENFORCED` env var also off

**Target:** monitoring-mode rollout → enforcement on phone auth, Storage uploads, and all callables.

### Phase A — monitoring (no enforcement)

- Add `LUMI_APP_CHECK_ENABLED=true` and `LUMI_APP_CHECK_RECAPTCHA_KEY=<key>` to the production dart-define. The existing build script [scripts/flutter-build.sh](scripts/flutter-build.sh) is the right place (per CLAUDE memory `reference_release_builds`).
- Register the production Play Integrity, App Attest, and reCAPTCHA Enterprise keys in the Firebase console.
- Enable **monitoring** (NOT enforcement) for: Cloud Firestore, Cloud Storage, Cloud Functions, Authentication. Console only — no code change.
- Verify debug builds still work via the auto-injected debug provider at [app_check_service.dart:46-50](lib/core/services/app_check_service.dart#L46-L50). Register the debug token in the console.
- Bake for **at least 7 days**. Watch the App Check metrics dashboard for the percentage of "verified" vs "unverified" requests per service. Target: >95% verified before enforcing.

### Phase B — enforcement (one service at a time)

- Enforce on **Phone Authentication** first (this is the abuse vector that matters most — pairs with the SMS rate-limit work).
- Then **Cloud Storage** (audio uploads).
- Then **all callables** — flip `IMPERSONATION_APP_CHECK_ENFORCED=true` and add `enforceAppCheck: true` to each `functions.https.onCall` config that handles sensitive ops: `createNotificationCampaign`, `deleteComprehensionAudio`, `linkParentToStudent`, `requestSmsVerification` (if SMS rate-limit work has shipped), `startImpersonationSession`, `deleteStudentWithCascade`.
- Finally **Firestore** — last because false-positives here break the entire app rather than a single feature.

### Risk + mitigation

- Old app versions without App Check break when enforcement turns on.
- Pair Phase B with a minimum-supported-version gate (Remote Config or in-app version check).
- **Don't ship enforcement during a school's enrollment week** — false-positive lockouts during onboarding are particularly damaging.

### Verification before enforcing

- Phase A: after 7 days, console shows ≥95% verified requests per service. If below, investigate before flipping enforcement.
- Phase B (per service): deploy enforcement, do an end-to-end smoke test (sign up new parent → log a reading → upload an audio recording). Watch error logs for `app-check-token-is-invalid` and roll back the offending service if seen.
