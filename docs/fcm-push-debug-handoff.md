# FCM Push Notifications Broken on `lumi-ninc-au` — Debug Session Handoff

_Written 2026-07-02. Hand this to a fresh Claude session for continuity._

> **✅ FIXED & VERIFIED 2026-07-03 (AEST morning).** New APNs auth key
> `9ZKLHH7FSY` ("Lumi APNs all env", **Sandbox & Production**, Team Scoped)
> uploaded to BOTH Firebase console slots (development + production) for
> `com.lumi.lumiReadingTracker`. Probe then delivered a REAL push to the test
> parent's physical iPhone: `sdk_real_send → projects/lumi-ninc-au/messages/
> 1783033071913600`. Old keys `W255F64QU7` ("Lumi SMS Flow", Production-only —
> the root cause) and `ZB6FH966LW` (accidental second Production-only key)
> should be revoked in the Apple portal. The probe cloud function was deleted;
> its source remains in `scripts/fcmauthdiag/` (untracked) for any future
> re-verification. Note: the Apple portal's key-creation "Configure" dialog
> defaults the APNs environment to a single environment — always verify the
> keys list shows **Sandbox & Production** before downloading.
>
> **🎯 TRUE ROOT CAUSE (found 2026-07-02 ~12:50 UTC) — see "FINAL root cause"
> at the bottom. It was the APNs KEY all along.** A probe that separated
> *validation* from *delivery* with the parent's REAL device token showed:
> dryRun/validate **succeeds** (caller auth fine), actual delivery fails with
> FCM detail `ApnsError {statusCode: 403, reason: "BadEnvironmentKeyInToken"}`
> — Apple rejecting FCM's provider JWT because the uploaded APNs auth key
> (`W255F64QU7`) is **environment-restricted** (Sandbox-only) and doesn't
> cover the device token's environment. FCM wraps this Apple 403 in a generic
> ESF-401 "missing credential" message, which misled two debug sessions into
> chasing Google-side service-account auth. Everything credential-side
> (SA tokens, scopes, GAE bridge flavor, service identities) was a red
> herring: dummy-token/validate probes always passed, real deliveries always
> failed, and no prior test had separated those two hops. **Fix: upload an
> unrestricted (Sandbox & Production) APNs key in the Firebase console.**
> The interim sections below ("Session 2 findings/resolution", incl. the
> "resolved by service-identity regeneration" claim) are kept as history but
> are superseded by the FINAL section.

## TL;DR

- **Symptom:** Backend push notifications do **not** deliver on production project
  `lumi-ninc-au`. The parent Settings → "Reading reminders" → **Send test** button
  always shows a bottom toast **"Showing a local preview (push unavailable)"** and no
  real push arrives — on the iOS Simulator **and** on a physical iPhone.
- **Root cause (PROVEN):** The **FCM v1 API rejects this project's service-account
  credentials** with `401 UNAUTHENTICATED` ("Request is missing required authentication
  credential. Expected OAuth 2 access token…"). A **user (owner) OAuth credential
  authenticates fine.** This affects ALL Cloud Functions FCM sends (the test, the
  scheduled reading reminders, and comment notifications).
- **Verdict:** A **project-level Firebase↔GCP service-account auth anomaly**, almost
  certainly an artifact of the AU migration (`lumi-kakakids` → `lumi-ninc-au`). It is
  **NOT fixable from app code or function code.** It needs **Firebase / Google Cloud
  support** to repair the service-identity provisioning for the migrated project.
- **User impact:** Degrades gracefully — the app falls back to a local notification.
  No crashes, no user-facing errors, just "push doesn't arrive."
- **Code state:** All diagnostic code has been **reverted**; `functions/src/index.ts`
  matches merged `main`; the clean `sendTestReadingReminder` is deployed; working tree
  is clean. Nothing is half-broken.

## The error (verbatim, from `firebase functions:log --only sendTestReadingReminder`)

```
messaging/third-party-auth-error
"Request is missing required authentication credential. Expected OAuth 2 access token,
 login cookie or other valid authentication credential.
 See https://developers.google.com/identity/sign-in/web/devconsole-project."
HTTP 401 UNAUTHENTICATED
```

The `third-party-auth-error` *code* is misleading (it usually maps to APNs); the *message*
and the raw REST body (`"status":"UNAUTHENTICATED"`) show it's a **caller-authentication**
failure — FCM does not accept the function's credential.

## How the feature is wired (for context)

- Callable **`sendTestReadingReminder`** — `functions/src/index.ts` (~line 2714, region
  `australia-southeast1`). Reads the parent doc's `fcmToken`, builds the body, calls
  `admin.messaging().send(...)`. Returns `{sent:false}` on failure.
- Client — `lib/services/notification_service.dart` → `sendReadingReminderTest()` calls the
  callable; on `sent!=true` it falls back to `_showLocalNotification` and the settings
  screen shows the "local preview (push unavailable)" toast.
- Parent FCM token stored at `schools/{schoolId}/parents/{uid}.fcmToken`; **deleted on
  logout** (`clearTokenForUser`, notification_service.dart) — so it's only present while
  the parent is logged in.
- Scheduled reminders — **`sendReadingReminders`** (hourly cron, ~line 1200) use the same
  `admin.messaging()` and are equally affected (they just hadn't errored visibly because
  they'd had `sent:0` — no parent matched the send hour).

## Diagnostic journey (what was tested, in order — all done, don't repeat)

1. Logs → `401 UNAUTHENTICATED` (above).
2. **App Check ruled out** — logs show *"Allowing request with invalid AppCheck token
   because enforcement is disabled."* App Check governs client→function (it's OFF, request
   proceeds); the break is function→FCM. Not the cause.
3. Runtime SA = `lumi-ninc-au@appspot.gserviceaccount.com` (App Engine default). Has
   `roles/editor`, not disabled.
4. `fcm.googleapis.com` (FCM API V1) **enabled**; legacy Cloud Messaging API disabled (fine).
   APNs auth keys **uploaded** in Firebase Console for the iOS app (dev + prod slots,
   Key ID `W255F64QU7`, Team ID `C2BSJNTRU5`). So APNs config is present.
5. **Direct Admin-SDK send with owner ADC (local script)** → FCM `400 invalid-argument`
   for a dummy token = **auth accepted** (owner credential works).
6. SA impersonation blocked (no `roles/iam.serviceAccountTokenCreator`).
7. In-function diagnostic logged the credential's OAuth scope → broad **legacy App Engine
   default-SA scope set** (youtube/gmail/drive/urlshortener/… **including cloud-platform**),
   `hasToken:true`.
8. Direct FCM v1 **REST** call from the function using that token → `401 UNAUTHENTICATED`.
9. Fetched the runtime SA token **straight from the GCP metadata server** and sent →
   still `401`; confirmed `saEmail = …@appspot…`.
10. Switched runtime SA to the **Compute Engine default SA**
    (`3795320704-compute@developer.gserviceaccount.com`, has Editor) via
    `runWith({serviceAccount})`, redeployed → **still `401`** (confirmed `saEmail = …compute…`).
11. **Verified the probe code is correct** — ran the exact `https.request` pattern LOCALLY
    with the owner token → FCM `400 invalid-argument` (auth accepted). So the REST code is
    fine; the SA tokens are genuinely rejected.
12. No `vpcConnector`; ingress `ALLOW_ALL`; `FIREBASE_CONFIG`/`GCLOUD_PROJECT` correct;
    App Engine app **SERVING** (australia-southeast1); no stray credential file bundled in
    the functions source.

**Net:** FCM rejects BOTH default service accounts (401) though their tokens are valid
(tokeninfo OK, `cloud-platform` scope); a user token works. Every ordinary cause is ruled
out → project-level SA→FCM auth linkage is broken.

## Recommended next steps (in priority order)

1. **Escalate to Firebase / Google Cloud support** with the blurb below. Expected fix:
   Google repairs the FCM service-agent / identity provisioning for the migrated project.
2. Lower-confidence things to try while waiting (a fresh session could attempt):
   - Confirm the project is fully **"added to Firebase"** / the Firebase Management API has
     provisioned service identities for the migrated GCP project (migrated projects
     sometimes lack the Firebase service agents). Consider re-linking Firebase.
   - Try a **dedicated service-account KEY** credential (`admin.initializeApp({credential:
     admin.credential.cert(key)})`) in case the key-based token-exchange path authenticates
     where the metadata token doesn't. (Requires generating an SA key — security tradeoff,
     may be blocked by org policy. Low confidence: both are OAuth2 access tokens.)
   - Check for an **org-level VPC Service Controls perimeter** or org policy restricting SA
     API access (needs org-level visibility).

## Support-ticket blurb (ready to paste)

> Project `lumi-ninc-au` (australia-southeast1), migrated from `lumi-kakakids`.
> `admin.messaging().send()` from a 1st-gen Cloud Function returns `401 UNAUTHENTICATED`
> ("Request is missing required authentication credential. Expected OAuth 2 access token…")
> for **both** the App Engine default SA (`lumi-ninc-au@appspot.gserviceaccount.com`) and
> the Compute Engine default SA (`3795320704-compute@developer.gserviceaccount.com`).
> The tokens are valid (pass `tokeninfo`, carry `cloud-platform` scope) and both SAs have
> `roles/editor`. `fcm.googleapis.com` is enabled and App Engine is serving. A **user**
> OAuth token sends to FCM successfully from the same project. Please repair FCM
> service-account authorization / service-identity provisioning for this project.

## Key facts / IDs

- Prod project **`lumi-ninc-au`**, region `australia-southeast1`. Previous project `lumi-kakakids`.
- Project number / FCM sender ID: **`3795320704`**.
- iOS bundle `com.lumi.lumiReadingTracker`; Apple Team ID `C2BSJNTRU5`; APNs Key ID `W255F64QU7`.
- App Engine default SA `lumi-ninc-au@appspot.gserviceaccount.com` (Editor, runtime SA for 1st-gen fns).
- Compute default SA `3795320704-compute@developer.gserviceaccount.com` (Editor).
- Test parent: `support+student0@lumi-reading.com`, uid `bSjSHpdAnHMryKSQdaWCKyem64P2`,
  school `beaumaris_primary_school`, children Lincon + Lily Tale; retrieve the
  test password from the team password manager (it is not stored in Git)
  (restored earlier this session). NOTE: its `fcmToken` is removed on logout.
- Deploy: `firebase deploy --only functions:sendTestReadingReminder --project lumi-ninc-au`
  (or `--only functions` for all). Predeploy runs `eslint` (no `--max-warnings`) + `tsc`.
- Re-test: log in as parent → Settings → Reading reminders → **Send test**; then
  `firebase functions:log --only sendTestReadingReminder --project lumi-ninc-au`.
  (Verify on a **physical device** — simulator FCM delivery is unreliable even when fixed.)

## Other work merged today (context; unrelated to the FCM bug)

- **#192** parent teacher-message card clears on read.
- **#191** school portal flags Auth-orphaned "ghost" parents as "Removed" (NOT yet deployed —
  needs `firebase deploy --only hosting:school`).
- **#193** `scripts/setup_parent_account.js`, **#194** `scripts/cleanup_ghost_parents.js`
  (4 ghost parents were deleted; `support+student0` login was restored).
- **#195** reading-reminders overhaul (Mon–Thu default, truthful preview, multi-child
  "log next child" guidance, real-FCM-push "Send test") — **this introduced the Send-test
  push path that surfaced the FCM bug.**
- **#197** offline-sync: manual "Try syncing now" reaches Firestore when connectivity_plus
  is stale.
- **#196** teacher comprehension-question editor: always-visible gated button → new-UI sheet.
- **#198** fix: reading-success screen no longer modifies a provider during `initState`.
- Cloud Functions were deployed to prod (`firebase deploy --only functions`).
- **Client changes above still need an app RELEASE build** to reach end users; functions are deployed.

---

# Session 2 findings (2026-07-02 evening, Fable) — root cause REVISED, fix available

## What was newly established (all evidence, no speculation)

1. **The SA identity is NOT broken.** A one-off Cloud Build probe (build
   `6d60706b-0a00-47b2-aba3-19522184c2a0`, runs as
   `3795320704-compute@developer.gserviceaccount.com` — the *same* SA that
   401s from inside the function) called FCM v1 with its GCE-metadata-minted
   token: **HTTP 404 `UNREGISTERED`** for a dummy device token = **auth
   ACCEPTED**. Same token also read Firestore (200). Its tokeninfo scope:
   `email, userinfo.email, cloud-platform` (the normal modern set).
2. **The in-function token really does carry a freak scope set** (recovered
   verbatim from the Jun-30 `FCM-DIAG` log entries, so no more guessing):
   `email, youtube, userinfo.email, urlshortener, streetviewpublish,
   spreadsheets, drive, presentations, cloud-platform, calendar,
   mail.google.com, analytics, contacts`. That is a *consumer-app* profile —
   no Cloud runtime on Earth should mint that. `cloud-platform` IS present,
   so FCM's rejection is about the token's **issuance flavor**, not a missing
   scope string. (FCM's ESF config accepts `firebase.messaging` OR
   `cloud-platform` — verified via serviceusage; identical on both projects.)
3. **Push has NEVER worked on `lumi-ninc-au`.** The same 401 hit
   `detectAchievements` (Jun 24, Jun 28, Jun 30) and `onCommentCreated`
   (Jun 24) — silently, in error logs nobody read. Zero
   `registration-token-not-registered`-class errors and zero success logs in
   the project's entire history → no FCM send ever authenticated. #195 didn't
   break anything; it made an existing day-one defect visible.
4. **The one structural difference vs the old project:** `lumi-ninc-au` HAS an
   App Engine app (`australia-southeast1`, created Jun 15 during migration —
   Cloud Scheduler setup historically prompts for one);
   **`lumi-kakakids` has NO App Engine app at all** (`gcloud app describe`
   errors). Gen-1 GCF mints runtime tokens through the **GAE identity bridge**
   when a GAE app exists — which is exactly where the freak token flavor can
   come from, and why the same code presumably worked on kakakids.
5. **Ruled out definitively this session:** org policies / VPC-SC (both
   projects are org-less — no ancestors); missing Google service agents (IAM
   parity verified; FCM has *no* per-project service identity by design —
   `generateServiceIdentity` returns `IAM_SERVICE_NOT_CONFIGURED_FOR_IDENTITIES`);
   API enablement (fcm.googleapis.com enabled on day one, Jun 11, by
   `gcp-sa-firebase` in the normal Firebase onboarding batch; never toggled
   since — full audit timeline pulled); firebase-admin version (^12, modern);
   billing/quota (would be 403/429, not 401).
6. **User-token baseline still passes today** (404 UNREGISTERED on both
   projects with a dummy token).

## Revised root cause

The App Engine identity bridge on `lumi-ninc-au` (GAE app created during the
AU migration) issues access tokens of a legacy/consumer flavor for the gen-1
Cloud Functions runtime. FCM v1's (stricter) front end does not recognize
those tokens as authenticated callers → `401 UNAUTHENTICATED` ("missing
credential"); Firestore's front end tolerates them → everything else works.
The Google-side anomaly is *why the bridge mints that flavor* — still worth a
support ticket — but the app does NOT need to wait for Google.

## Fix options (in order of preference)

- **A. Key-less self-impersonation (test first — 5 min):** deploy the
  disposable probe in `scripts/fcmauthdiag/` (see below). If its
  `iamcredentials` cell returns **403** (permission, i.e. caller
  authenticated), then: grant the runtime SA `tokenCreator` on itself
  (`gcloud iam service-accounts add-iam-policy-binding
  lumi-ninc-au@appspot.gserviceaccount.com
  --member="serviceAccount:lumi-ninc-au@appspot.gserviceaccount.com"
  --role=roles/iam.serviceAccountTokenCreator`), and in functions init a
  second admin app whose credential's `getAccessToken()` calls
  `iamcredentials.generateAccessToken` on itself with scope
  `firebase.messaging` — use that app only for `.messaging()`. No keys.
  If the probe's iamcredentials cell returns **401**, fall back to C.
- **B. Metadata `?scopes=` re-mint (probe tests this too):** if the probe's
  `scoped_fcm` cell shows 404, the fix is a tiny custom credential that
  requests `token?scopes=firebase.messaging,cloud-platform` from the metadata
  server for the messaging app. Zero IAM changes.
- **C. Guaranteed fallback — SA key for messaging only:** create a key for
  `firebase-adminsdk-fbsvc@lumi-ninc-au.iam.gserviceaccount.com`, store in
  Secret Manager, init a second admin app with `credential.cert(...)` used
  only for `.messaging()`. Vanilla OAuth2 key-exchange path — same acceptance
  class as the proven-working build/user tokens. Long-lived key is the cost.
- **D. Structural (later):** move the FCM senders to gen-2 functions (Cloud
  Run infra → GCE-style metadata → normal tokens, per the build probe). Or
  keep D as the eventual end-state after Google responds.
- **Not worth doing:** disabling/re-enabling `fcm.googleapis.com` (the
  consumer config demonstrably accepts normal tokens — the API record is
  fine); switching runtime SA (compute SA already tested — the bridge, not
  the SA, is the variable); App Check changes (unrelated).

## The disposable probe (`scripts/fcmauthdiag/`)

One isolated gen-1 function (never touches the app's functions codebase; no
deps; returns JSON; logs no secrets). It answers: default-token aud/azp +
scopes, does metadata honor `?scopes=`, does iamcredentials accept the
runtime token (401 vs 403), FCM probe per token, Firestore control.

```bash
gcloud functions deploy fcmauthdiag --no-gen2 --runtime=nodejs20 \
  --entry-point=diag --trigger-http --no-allow-unauthenticated \
  --region=australia-southeast1 --source=scripts/fcmauthdiag \
  --project=lumi-ninc-au --memory=256MB --timeout=60s --quiet
curl -s -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  https://australia-southeast1-lumi-ninc-au.cloudfunctions.net/fcmauthdiag | python3 -m json.tool
gcloud functions delete fcmauthdiag --region=australia-southeast1 \
  --project=lumi-ninc-au --quiet
```

(A Claude session could not run deploy/IAM/scheduler mutations — the
permission classifier blocks them in auto mode; run the three commands above
manually or pre-allow them.)

## Updated support-ticket blurb (sharper than v1 — use this one)

> Project `lumi-ninc-au` (project number 3795320704, no org, migrated
> workload from `lumi-kakakids`). Gen-1 Cloud Functions in
> `australia-southeast1` receive `401 UNAUTHENTICATED` from
> `fcm.googleapis.com/v1/.../messages:send` for BOTH default service
> accounts. Evidence isolates the defect to the App Engine identity bridge:
> (1) tokeninfo of the runtime token shows an abnormal consumer scope set
> (youtube, urlshortener, streetviewpublish, spreadsheets, drive,
> presentations, calendar, mail.google.com, analytics, contacts + 
> cloud-platform) — no normal GCF runtime mints this; (2) the SAME service
> account (`3795320704-compute@developer.gserviceaccount.com`) calling the
> SAME endpoint with a Cloud-Build-VM metadata token (normal scopes) is
> accepted (404 UNREGISTERED for a dummy device token); (3) user OAuth tokens
> are accepted; (4) the same runtime tokens ARE accepted by Firestore. The
> project has an App Engine app (created 2026-06-15, australia-southeast1);
> our previous project (`lumi-kakakids`, working FCM) has none — that is the
> only structural difference we can find. Please investigate why the App
> Engine identity bridge for this app issues legacy/consumer-flavored access
> tokens that FCM's front end rejects.

## Cloud-side changes made this session (for the record)

- `gcloud beta services identity create --service=firebase.googleapis.com`
  (idempotent ensure; FCM has no identity to create). No IAM changes. No
  scheduler jobs created (blocked). One Cloud Build record left
  (`6d60706b`, the probe). `gcloud beta` component installed locally.

---

# Session 2 resolution (2026-07-02, ~10:05 UTC) — FCM auth WORKS again

## Verified timeline of the flip (all UTC, all from logs/probes)

| Time | Event | FCM verdict |
|---|---|---|
| Jun 24–30 | `detectAchievements` / `onCommentCreated` / test sends | 401 (many) |
| Jul 2 09:36:00 | Old in-runtime diag (`FCM-META`, compute SA) — last pre-fix datapoint | **401** |
| Jul 2 09:45 | Clean `sendTestReadingReminder` redeployed (no FCM test run) | — |
| Jul 2 ~10:05 | **`gcloud beta services identity create --service=firebase.googleapis.com`** → "Service identity created" | — |
| Jul 2 10:18 | Cloud Build probe (compute SA, GCE-minted token) | **404 = accepted** |
| Jul 2 10:49 | `fcmauthdiag` probe from the real gen-1 runtime (appspot SA) | **404 = accepted** |
| Jul 2 10:52 | Second runtime probe (stability check) | **404 = accepted** |

Crucially, the runtime token's freak consumer scope set was **identical**
before (09:35 `FCM-DIAG` log) and after (10:49 probe) — the token flavor never
changed; **FCM's acceptance of the project's robot identities changed**. That
is consistent with the Firebase service-agent/consumer registration being
re-provisioned by the `generateServiceIdentity` call, and not consistent with
a deploy-side or token-side change. (Honesty note: a coincidental Google-side
repair inside the 09:36→10:18 window cannot be fully excluded; nobody had
filed a support ticket, making silent external repair unlikely.)

## Probe results snapshot (10:49Z, from the gen-1 runtime)

- `default_fcm`: **404 UNREGISTERED** (auth accepted; dummy token evaluated)
- `scoped_fcm`: **404** — and `?scopes=` IS honored by the gen-1 metadata
  server (`firebase.messaging cloud-platform` came back) → **fix B proven
  viable** as a regression fallback
- `iamcredentials`: **403** permission-denied (i.e. the runtime token
  authenticates; only the self-impersonation grant is missing) → **fix A
  proven viable** as a regression fallback
- `firestore`: 200; token `aud`/`azp` `110535320824381107387` (appspot SA
  unique ID — normal)

## Remaining verification + regression runbook

1. **Real-device E2E (the only outstanding step):** log in as the test parent
   (`support+student0@lumi-reading.com`) on the physical iPhone → Settings →
   Reading reminders → **Send test**. Expect a real push (no "local preview"
   toast). This also exercises the APNs leg, which was never the problem.
2. Passive confirmation over the next days: watch for
   `"Comment notification sent"` / `"Achievement notification sent"` info logs
   and `sendReadingReminders` runs with `sent>0`:
   `gcloud logging read '"notification sent"' --project=lumi-ninc-au --freshness=7d`
3. **If it ever regresses to 401:** redeploy the probe from
   `scripts/fcmauthdiag/` (3 commands in "The disposable probe" above), and
   re-run `gcloud beta services identity create
   --service=firebase.googleapis.com --project=lumi-ninc-au`. If that doesn't
   flip it back within ~15 min, implement fix B (metadata `?scopes=` custom
   credential — proven to mint clean tokens) and file the support ticket with
   the Session-2 blurb.
4. `scripts/fcmauthdiag/` is intentionally untracked; keep it until push is
   confirmed stable, then delete (or commit it under scripts/ if you want the
   runbook permanent).

---

# FINAL root cause (2026-07-02 ~12:50 UTC) — APNs key environment restriction

## The decisive experiment (probe v4)

Probe reads the test parent's real `fcmToken` server-side and runs the exact
app message shape through four cells (same instance, same credential,
seconds apart):

| Cell | Result |
|---|---|
| SDK dryRun, dummy token | `registration-token-not-registered` (auth OK) |
| SDK **dryRun, REAL token** | ✅ `projects/lumi-ninc-au/messages/fake_message_id` |
| raw REST validate, REAL token | ✅ HTTP 200 |
| SDK/raw **actual delivery, REAL token** | ❌ 401, `FcmError: THIRD_PARTY_AUTH_ERROR` + **`ApnsError {statusCode: 403, reason: "BadEnvironmentKeyInToken"}`** |

Validation (which never contacts Apple) always passes; delivery (which makes
FCM sign a provider JWT with the uploaded .p8 and call APNs) always fails —
Apple returns 403 `BadEnvironmentKeyInToken`: *the provider token key is
restricted to an APNs environment that doesn't match the target token.* In
practice: key `W255F64QU7` was created in the Apple Developer portal with the
**"Sandbox" environment restriction** instead of "Sandbox & Production".

## Why every prior conclusion was wrong

- FCM wraps the Apple 403 in a **generic ESF-401 body** ("Request is missing
  required authentication credential…") — which reads exactly like a
  caller-credential failure. It isn't one.
- The famous "user token works, SA token fails" contrast compared a
  **dummy-token/validate-class call** (always passes, any credential) against
  **real deliveries** (always fail, any credential). Nobody had run a real
  delivery with a user credential, and nobody had run validate-with-real-token
  from the runtime — today's matrix filled both gaps.
- Consequently: the AU-migration SA theory, the GAE-bridge token-flavor
  theory, and the "fixed by `services identity create`" claim are ALL
  red herrings. (The freak consumer-scope token set from the GAE bridge is
  real but harmless — FCM accepts it.)
- `messaging/third-party-auth-error` meant exactly what its name says.

## The fix (Firebase console + Apple portal, ~5 min, no deploys)

1. Apple Developer portal → Certificates, Identifiers & Profiles → **Keys**
   → inspect `W255F64QU7`: its APNs configuration will show the environment
   restriction (Sandbox).
2. Create a **new key**: enable "Apple Push Notifications service (APNs)",
   and in its configuration choose **Sandbox & Production**. Download the
   `.p8` (one-time download).
3. Firebase console → Project settings → **Cloud Messaging** → iOS app
   `com.lumi.lumiReadingTracker` → APNs Authentication Key → replace with the
   new `.p8`, its Key ID, Team ID `C2BSJNTRU5`.
4. Parent app → Settings → Reading reminders → **Send test** → real push
   should arrive. Server-side config only; no rebuild, no function deploy.
5. Optionally revoke the old restricted key in the Apple portal afterwards.

## Verification + cleanup after the key swap

- Re-run the probe (still deployed as `fcmauthdiag`,
  `curl -H "Authorization: Bearer $(gcloud auth print-identity-token)"
  https://australia-southeast1-lumi-ninc-au.cloudfunctions.net/fcmauthdiag`):
  `sdk_real_send` should return a real message id (and the phone buzzes).
- Then delete the probe:
  `gcloud functions delete fcmauthdiag --region=australia-southeast1
  --project=lumi-ninc-au --quiet` and remove `scripts/fcmauthdiag/`.
- Watch `"Comment notification sent"` / `"Achievement notification sent"` /
  `sendReadingReminders` logs over the following days for organic successes.
- No Google support ticket needed. No app or functions code changes needed.
```
