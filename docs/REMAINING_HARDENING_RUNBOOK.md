# Remaining Hardening & Refactor — Execution Runbook

> Companion to `PRODUCTION_HARDENING_PLAN.md`. That doc was the *plan*; this is
> the *finish line* — the ordered, do-this-then-that guide for everything still
> open, including the real-device E2E procedures **you** run.
>
> Everything the code could safely deliver is already merged (~40 PRs) and the
> deployable, no-app-dependency work is live in prod (`lumi-ninc-au`). What's
> left is the set that genuinely needs **a real device**, **the Firebase
> console**, or **an app release + adoption window**. This runbook sequences it.

Legend: 🧑‍💻 = a step **you** do (device / console / store) · 🤖 = a step Claude
does (code) · ☁️ = a prod deploy (confirm first).

---

## 0. The one thing that unblocks almost everything: cut an app release

Read this first — it changes the order of everything else.

A large batch of **client** changes is merged on `main` but only takes effect in
a *new app build*: the code-verification switch (#210), co-parent generation
(#211), the phone-only splash fix, the parent access-gate, all the Phase-4 UX
fixes (error states, offline durability, library search, etc.). Several **rules
tightenings can't deploy until that build is adopted** in the field, because old
installs still do the old client queries.

So the critical path is:

```
build & release app  ─►  watch adoption  ─►  deploy the gated rules (#212)
      │
      └─►  (in parallel) run the device E2E tests below on that same build
```

Until you cut a release, the gated items stay parked — that's correct, not
stuck.

---

## 1. Current state (what's live vs pending)

**Live in prod now** (deployed + verified this cycle):
- Security criticals: portal cookie forgery, `deleteStudentWithCascade` authz,
  `resetUserPassword` IDOR.
- Callables: `verifyStudentLinkCode`, `verifySchoolCode`, `createCoParentInvite`.
- Portal: Phase-2 authz + Phase-4 (CSV blocker, error states, partial-success,
  analytics perf).
- Rules: access-field allowlist + `schoolOnboarding` shape (2.1/2.6).
- The `(classId, lastCommentAt)` and existing indexes.

**Merged, ships with the next app release** (no action beyond releasing):
- All the client-side work listed in §0.

**Open PR, intentionally gated:**
- **#212** — remove the unauthenticated code-`list` rules. **Do not merge/deploy
  until the app carrying #210 + #211 is adopted** (§4).

**Built this cycle, merged, awaiting deploy/release** (see §5):
- **1.3 server-verified join** — server (#241), client (#242), rules (#243). The
  functions + rules halves are **deploy-safe now** (legit paths already run
  server-side); the client half ships with the app release. See §5.1.
- **4.12-b offline allocation queue** (#240) — client-only; ships with the app.

**Not built yet** (needs device / console / a focused session): 1.6 App Check,
2.2 audio, 3.1 Hive encryption, 4.10 MFA-login recovery. Covered below.

---

## 2. 🧑‍💻 Cut the app release (Gate 0)

1. Confirm `main` is what you want to ship:
   ```bash
   git checkout main && git pull --ff-only
   flutter analyze          # expect 0 errors
   flutter test             # note: ~38 pre-existing emulator-dependent failures are known
   ```
2. Build the release artifacts (this applies `.dart_define.json` — **do not** use
   raw `flutter build`):
   ```bash
   ./scripts/flutter-build.sh ipa          # iOS → TestFlight/App Store
   ./scripts/flutter-build.sh appbundle    # Android → Play
   ```
3. Upload to TestFlight / Play internal testing. **Smoke-test on a real device**
   before promoting (see §3 — you'll reuse that build for the E2E tests).
4. Promote to production. Note the version/build number — you'll watch its
   adoption before the §4 rules deploy.

---

## 3. 🧑‍💻 Real-device E2E test procedures

These are the tests that can't be automated (real SMS, real offline transitions,
real scanning). Run them on the release/profile build from §2. Do them against a
**dedicated test school**, not a live one.

### 3.0 One-time setup

1. **Test device:** a real iPhone (phone-MFA can't be exercised on the Simulator
   — `appVerificationDisabledForTesting` masks the hint) and, ideally, a real
   Android for parity.
2. **Test school:** create a throwaway school + a school join code + at least one
   student with a link code. (Use the school portal or the onboarding flow.)
3. **A real phone number** you can receive SMS on (and a second one for the
   co-parent / phone-primary cases).
4. **Going offline on a real device:**
   - iOS: **Settings → Airplane Mode ON** (turn Wi-Fi back off if it auto-re-enables).
     For *flaky* conditions, use **Xcode → Devices → Network Link Conditioner**
     ("Very Bad Network" / "100% Loss").
   - Android: Airplane Mode, or Dev Options → "Networking" throttling.
5. **Verification tool:** keep the **Firebase console → Firestore** open for
   `lumi-ninc-au` so you can confirm docs after each test. Useful paths:
   - `schools/{schoolId}/readingLogs/{logId}`
   - `schools/{schoolId}/allocations/{allocationId}`
   - `schools/{schoolId}/parents/{uid}` and `.../users/{uid}`
   - `userSchoolIndex/{...}`

> Tip: build a **profile** build (`flutter run --profile --dart-define-from-file=.dart_define.json`)
> if you want `debugPrint` logs while testing; release builds strip them.

### 3.1 Signup flows (validates the 1.3 changes once §5 ships them)

Run each; after each, confirm the membership doc + `userSchoolIndex` in Firestore.

| # | Flow | Steps | Expect |
|---|------|-------|--------|
| A | Teacher email + MFA | New teacher → enter school **code** → email/password → SMS code | `schools/{id}/users/{uid}` with `role:teacher`, `schoolId` matching the **code's** school; `userSchoolIndex/{sha256(email)}` keyed to the **verified** email |
| B | Parent email + MFA | New parent → enter **link code** → email/password → SMS code | `schools/{id}/parents/{uid}` under the **link code's** school; student's `parentIds` contains the uid |
| C | Parent phone-primary | New parent, **no email** → enter link code → phone → SMS code | Parent doc created **server-side** (after 1.3-b), linked; no email index |
| D | Re-entry / add child | Existing parent → add another child via a link code | New link succeeds; no duplicate parent doc |

**Adversarial check (proves the fix, do after §5 rules deploy):** with a signed-in
account, try to self-write `schools/{other}/users/{self}` with `role:teacher`
via a raw client → must be **denied**.

### 3.2 Offline reading-log durability (validates #238, already merged)

1. Open the parent app, go **offline** (§3.0.4).
2. Log a reading session (quick-log and the detailed flow); pick a **feeling**;
   record a **comprehension answer**.
3. Confirm the success screen shows **"Saved — we'll sync it when you're back
   online"** (not a stale "Night N complete").
4. **Background the app mid-recording** once → confirm the recording stops and is
   preserved (not lost).
5. Go **online**. Within a drain cycle, confirm in Firestore:
   - the `readingLogs/{logId}` doc exists,
   - `childFeeling` is set (this is the new offline sync-type — the feeling used
     to vanish offline),
   - the comprehension audio uploaded (check Storage `schools/{id}/comprehension_audio/{logId}.m4a`).
6. **Cold-start test:** repeat 1-2, then **force-quit** the app before reconnecting.
   Relaunch online → the queued log + feeling + audio should still drain (they're
   persisted to disk + the recording now lives in Documents, not temp).

### 3.3 Offline classroom scanning (validates #239 now; 4.12-b later)

1. Open the teacher **kiosk / ISBN scanner**, go **offline**.
2. Scan a **real, known** book's barcode.
   - **Now (#239):** you should see **"You're offline — try that book again once
     you're connected"** — *not* "We couldn't find that book." (That was the bug.)
   - **After 4.12-b ships:** the scan should be **queued** ("saved, will sync")
     and, on reconnect, land on the student's weekly allocation. Verify
     `allocations/{id}.assignmentItems` after reconnect.
3. Scan a **genuinely unknown** barcode while **online** → should still say
   "couldn't find that book" (not-found is unchanged).

### 3.4 MFA-login recovery (validates 4.10, still to build)

1. As a phone-MFA account, start login, reach the SMS step.
2. Test the "can't receive the code?" path (to be added) and confirm it routes to
   a support/factor-reset flow rather than a hard lockout.
3. Test dismissing the signup modal past the SMS step → confirm it doesn't orphan
   an email+password account (re-registration shouldn't collide with
   `email-already-in-use`).

---

## 4. ☁️ App-adoption-gated deploy: the code-enumeration rules (#212)

Do this **after** the §2 release is adopted.

1. **Check adoption.** In the Firebase console → Analytics (or Crashlytics →
   versions), confirm the share of sessions still on the *pre-release* build is
   negligible. Old builds run the client `where('code','==',x)` queries that #212
   removes; deploy too early and their signup/linking breaks.
2. Merge #212 (or check out its branch) so `firestore.rules` on disk has the
   tightening.
3. Deploy (confirm prod):
   ```bash
   firebase deploy --only firestore:rules --project lumi-ninc-au
   ```
4. **Verify:** run the §3.1 signup + linking flows on the current app — codes
   still verify (via the callables). Then confirm an **anonymous** filter-less
   `studentLinkCodes` / `schoolCodes` list is now **denied**.
5. **Rollback if signup breaks:** redeploy the previous ruleset immediately.
   Rollback ruleset id: `firestore 81c7c969-1004-4a98-9f69-26eea34f85f3`.

---

## 5. Remaining build work (🤖 Claude builds → 🧑‍💻 you E2E → ☁️ deploy)

These aren't done yet. Each is: Claude builds it (emulator/unit-verified), you
run the matching §3 device test, then deploy in the safe order.

### 5.1 — 1.3 server-verified join ✅ BUILT (closes teacher self-provisioning)
Server **#241**, client **#242**, rules **#243** — all merged to `main`.
- **Server (#241):** `enrollLinkedPhoneAsMfa` derives `schoolId` from the school
  **code** (teacher) / link **code** (parent) via shared `resolveSchoolCode` /
  `resolveLinkCodeSchool` (read-only — school code **not** consumed, so enroll
  stays retry-safe). New **`finalizeParentSignup`** callable for the
  phone-primary parent path. Backward-compatible: old clients fall back to
  `data.schoolId`.
- **Client (#242):** teacher passes the verified school code; parent
  phone-primary path now finalises via `finalizeParentSignup` (was the
  client-side `parentRef.set`).
- **Rules (#243):** removed the **teacher self-create** branch (the critical
  hole) and the **client `parentIds` self-append** rule. Tests flipped to assert
  denial — `test:rules` 99/99. **Parent self-create was KEPT** (the existing-MFA
  parent linking a child at a *new* school still client-creates its membership;
  residual risk low — bare parent doc has empty `linkedChildren`). Closing that
  fully needs a server path for cross-school existing-MFA linking (follow-up).
- **Deferred:** school-code `usageCount` consumption — never incremented today,
  so switching it on is a separate live-behaviour change (maxUsages caps would
  start biting active onboarding).
- **E2E (🧑‍💻):** §3.1 flows A-D on a real device, against a test school. Plus the
  §3.1 adversarial check (raw self-write of a teacher doc must be **denied**).
- **Deploy (☁️) — order:**
  1. **Functions (#241)** — safe to deploy now (additive + backward-compatible):
     `firebase deploy --only functions --project lumi-ninc-au`.
  2. **Rules (#243)** — safe to deploy now (current app's teacher signup +
     parent linking already go through the Admin SDK, unaffected):
     `firebase deploy --only firestore:rules --project lumi-ninc-au`. Keep the
     prior ruleset id ready (Appendix).
  3. **App release (#242 client)** — after functions are deployed (the new build
     calls `finalizeParentSignup`).

### 5.2 — 4.12-b offline allocation write queue ✅ BUILT (#240)
`SyncType.allocationAssignment` added; `assignResolvedBooks` guards on
`canWriteToFirebase` and enqueues a serialized PendingSync offline;
`replayQueuedAssignment` re-runs the transaction on drain (wired via
`registerAllocationReplay`). Drain unit-tests added (30/30 in
`offline_service_test.dart`).
- **E2E (🧑‍💻):** §3.3 step 2 "after 4.12-b" — scan offline, reconnect, verify the
  allocation merged correctly. **This is the one that most needs a device** (real
  scanning + real offline→online transition + transaction replay).
- **Deploy (☁️):** ships with an app release (client-only change).

### 5.3 — 2.2 comprehension audio scope ✅ BUILT (children's PII at rest)
Callable + client **#244** (MERGED); gated storage rule **#245** (OPEN — do not
deploy until adoption).
- **#244:** `getComprehensionAudioUrl({schoolId, logId})` callable authorizes the
  caller (teacher/schoolAdmin at the log's school) and returns a 15-min signed
  URL. `ComprehensionAudioPlayer` fetches via it (was `getDownloadURL`);
  expiry-aware URL cache. Playback is teacher-only (per-log player in the teacher
  comments sheet).
- **#245 (GATED):** `storage.rules` `comprehension_audio` read → `if false`.
  `test:rules:storage` 6/6 (incl. a direct-read-denied test + a corrected stale
  kill-switch test). **Deploy only after the #244 app build is adopted** — older
  installs still read the object directly.
- **⚠️ Deploy prerequisite:** `getSignedUrl` needs the functions runtime service
  account to sign blobs — grant `roles/iam.serviceAccountTokenCreator` (or
  `iam.serviceAccounts.signBlob`). **Verify playback on-device before tightening
  the rule.** (`community_books/covers` contributor-binding is NOT done — storage
  rules can't cheaply do the cross-service Firestore read under lumi-ninc-au;
  tracked as a separate follow-up.)
- **E2E (🧑‍💻):** confirm a teacher can still play a child's recording via the app
  on a device (this also verifies the signing IAM); confirm a foreign authed user
  can't fetch the object directly once #245 is deployed.
- **Deploy (☁️):** function #244 (anytime) + app release first; then storage rule
  #245 after adoption. `firebase deploy --only storage --project lumi-ninc-au`.

### 5.4 — 3.1 Hive encryption (COPPA/GDPR-K at rest)
- **Build (🤖):** add `flutter_secure_storage`; generate/store a 32-byte key in
  Keychain/Keystore; open the sensitive Hive boxes with `HiveAesCipher`. Handle
  **migration**: opening an existing *unencrypted* box with a cipher throws →
  catch, delete, reopen encrypted (safe for the transient
  `phone_verification_recovery` box).
- **E2E (🧑‍💻):** **this needs a device** — verify (a) the app still launches and
  reads/writes after upgrading an existing install (migration path), (b) Keychain
  access works on iOS and Keystore on Android, (c) a device backup / `adb backup`
  no longer yields readable box contents. (`allowBackup=false` already shipped.)

---

## 6. 🧑‍💻 Firebase console: App Check (1.6)

Staged so you don't lock out real clients.

1. **Register providers** — Firebase console → App Check:
   - iOS: **App Attest** (or DeviceCheck). Android: **Play Integrity**. Web:
     **reCAPTCHA Enterprise**.
   - Register **debug tokens** for your internal test devices.
2. **Ship a build with attestation on:** release an app built with
   `--dart-define=LUMI_APP_CHECK_ENABLED=true` (and the web reCAPTCHA key). The
   client (`app_check_service.dart`) already picks release providers behind
   `kDebugMode`.
3. **Watch tokens arrive** — App Check console shows verified vs unverified
   requests. Wait until the bulk of real traffic is sending valid tokens.
4. **Only then enforce** on the sensitive callables. The opt-in env flags now
   exist on ALL of them (code side done in **#248** — default OFF, so setting a
   flag is a pure config flip + redeploy, no code change):
   - `PARENT_LINKING_APP_CHECK_ENFORCED` · `CODE_VERIFICATION_APP_CHECK_ENFORCED`
     · `IMPERSONATION_APP_CHECK_ENFORCED` (pre-existing)
   - `DELETE_STUDENT_APP_CHECK_ENFORCED` · `NOTIFICATION_CAMPAIGN_APP_CHECK_ENFORCED`
     · `SMS_APP_CHECK_ENFORCED` · `MFA_ENROLLMENT_APP_CHECK_ENFORCED` (#248 — the
     last one covers both `enrollLinkedPhoneAsMfa` + `finalizeParentSignup`)

   Set each to `true` and redeploy those functions (☁️, confirm prod). App Check
   attests the APP, not the account, so `SMS_`/`MFA_ENROLLMENT_` are safe on the
   mid-MFA / pre-account paths — the only reason to stage them is to confirm real
   traffic is attesting first (step 3), not an auth concern.

---

## 7. 🧑‍💻 Product decision (not a code task)

- **4.17-A empty-class add-student flow.** There is **no add-student feature
  anywhere in the app** — rosters come from the admin/import only. So the
  empty-class screen can't offer "add students" until you decide whether teachers
  *should* be able to add students. Options: (a) guidance only ("Students are
  added by your school admin"), or (b) build a real teacher add-student flow
  (larger). Tell me which and I'll build it.

---

## 8. Suggested end-to-end order

1. 🤖 Build the remaining server/client code. **Done:** 1.3 (#241/#242/#243),
   4.12-b (#240). **Left:** 2.2 audio, 3.1 Hive (both emulator/unit-verifiable;
   they just can't *deploy* until your E2E + release).
2. ☁️ **Deploy-safe-now** (independent of the app release, confirm prod):
   - 1.3 **functions** (#241) — additive/backward-compatible.
   - 1.3 **rules** (#243) — teacher self-provision + parentIds self-append
     removals; current app unaffected. Closes the live teacher-self-provision
     critical without waiting for adoption.
3. 🧑‍💻 Cut the app release (§2) with all merged client work **+** the newly-built
   1.3/4.12-b clients (and 2.2/3.1 if built by then).
4. 🧑‍💻 Run the §3 device E2E on that build.
5. ☁️ Deploy the remaining server halves + the **adoption-gated** rules (#212) in
   the safe order (§4, §5).
6. 🧑‍💻 App Check rollout (§6) once real traffic is attesting.

---

## Appendix — commands & rollback

```bash
# Rules deploy (confirm prod)
firebase deploy --only firestore:rules --project lumi-ninc-au
# Rollback ruleset ids: firestore 81c7c969-1004-4a98-9f69-26eea34f85f3
#                       storage   e11c1757-926a-4afe-b4e4-81a301bbe3a7

# One function / all functions
firebase deploy --only functions:<name> --project lumi-ninc-au
firebase deploy --only functions --project lumi-ninc-au   # runtime/SDK changes

# Portal (SSR on Cloud Run — stop any `next dev` first)
FIREBASE_CLI_EXPERIMENTS=webframeworks firebase deploy --only hosting:school --project lumi-ninc-au

# Indexes
firebase deploy --only firestore:indexes --project lumi-ninc-au

# App builds (apply .dart_define.json)
./scripts/flutter-build.sh ipa
./scripts/flutter-build.sh appbundle

# Verify surfaces
npm --prefix functions run test:rules      # firestore rules (emulator)
npm --prefix functions run build && npm --prefix functions run lint
cd school-admin-web && npx tsc --noEmit     # never `next build` vs a live dev server
flutter analyze                             # target 0 errors in lib/
```

**Node 20 decommission: 2026-10-30** — ✅ **Phase 5 DONE + DEPLOYED 2026-07-05
(#249):** all 47 functions on **Node.js 22 (1st Gen)** + `firebase-functions`
v7, zero behaviour change (only code change was switching the 11 bare
`firebase-functions` imports to `firebase-functions/v1`). The decommission
deadline is now handled. **Phase 6 (Gen1→Gen2, ~19 callables + scheduled +
triggers → v2 API; changes function URLs)** remains — the last big block, no
hard deadline now that Phase 5 bought the runtime headroom.

> Deploy gotcha (for future function deploys): the deploy failed twice on
> **transient network** (`ECONNRESET` / "socket hang up" to the GCP prep APIs) —
> all pre-deploy, so prod stayed untouched — and went through clean on a retry.
> If `firebase deploy` dies with a vague "An unexpected error has occurred," run
> it with `--debug`; if it's a socket/TLS reset, just retry.
