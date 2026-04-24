# Developer Impersonation — Operations Runbook

Phase 5 deliverable. Operational procedures for deploying, configuring, and
monitoring the read-only developer impersonation pipeline. Code changes
across Phases 1–4 are fully captured in `.claude/plans/impersonation-phase-*-handoff.md`.

---

## 1. First-time rollout (in order)

### 1.1 Deploy Firestore rules & indexes
```bash
cd /Users/nicplev/lumi_reading_tracker
firebase deploy --only firestore:rules,firestore:indexes
```
The eight new composite indexes in [firestore.indexes.json](../firestore.indexes.json) must build
before any queries from Phase 4's audit viewer run in production. Index
builds are visible in the Firebase console → Firestore → Indexes tab; they
typically take 1–5 minutes per index.

### 1.2 Deploy Cloud Functions
```bash
cd functions
firebase deploy --only functions:startImpersonationSession,functions:endImpersonationSession,functions:revokeImpersonationSession,functions:reportImpersonationActivity,functions:reportBlockedWrite,functions:exportImpersonationAudit,functions:expireImpersonationSessions,functions:revokeOnDevAccessRemoval,functions:listImpersonableSchools,functions:listImpersonableUsers,functions:monitorImpersonationAnomalies
```

All eleven functions are deploy-safe (no destructive migrations, no backfills).

### 1.3 Seed the super-admin allowlist
The impersonation Cloud Functions check `/superAdmins/{uid}` as the primary
source of super-admin privilege. Seed your own UID first — without it,
`revokeImpersonationSession` / `exportImpersonationAudit` reject all callers.

**Option A — local seed script (recommended):**
```bash
FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/path/to/service-account.json \
  node scripts/seed_super_admin.js <YOUR_UID> you@example.com
```

**Option B — Firebase console:**
1. Open the Firebase console → Firestore → Data.
2. Create collection `superAdmins`.
3. Add a document with ID = your Firebase Auth UID.
4. Any fields are fine; presence of the doc is what grants privilege.

Either way, re-running is idempotent.

### 1.4 (Optional) Bootstrap env var
For the brief window between deploy and the first `/superAdmins/{uid}` seed,
you can set the `SUPER_ADMIN_UIDS` env var on the functions:
```bash
firebase functions:config:set impersonation.super_admin_uids="uid1,uid2"
# Note: this uses the deprecated runtime config API. Prefer Option 1.3 above.
```

Once Firestore is seeded, **remove** the env var so there's a single source
of truth.

### 1.5 Add yourself to the dev access allowlist
Use the existing lumi-admin flow:
1. Sign in to lumi-admin as a super-admin.
2. Go to Operations → Dev Access.
3. Click "Add" → enter your dev email → save.

This writes to `/devAccessEmails/{sha256(email)}` and makes the impersonate
button appear in both the Flutter app and `school-admin-web`.

---

## 2. App Check rollout (graduated)

App Check is **off by default** in Phase 5. Turning it on is a gradual
rollout because any client that doesn't send a valid App Check token will
start receiving `failed-precondition` errors the moment enforcement flips.

### 2.1 Pre-flight: register App Check providers in the Firebase console
- **iOS**: DeviceCheck (default) or App Attest (iOS 14+). Register the app
  bundle ID.
- **Android**: Play Integrity (recommended) or SafetyNet (legacy). Register
  the package name + SHA-256 certificate hash.
- **Web**: reCAPTCHA Enterprise OR reCAPTCHA v3. Register the site key.

### 2.2 Integrate App Check in each client
Flutter: `firebase_app_check` package; call
`FirebaseAppCheck.instance.activate(...)` in `main()` **before** any Firebase
SDK calls.

admin-web: `firebase/app-check` module; call `initializeAppCheck(app, {...})`
in `src/lib/firebase/client.ts`.

Both should initialise with `isTokenAutoRefreshEnabled: true`.

### 2.3 Monitor unattested traffic in audit-only mode
Before flipping enforcement, in the Firebase console enable **audit mode**
for the impersonation callables. Unattested requests are logged but still
allowed. Watch `Cloud Logging` for unexpected sources.

### 2.4 Enforce
Once unattested traffic is near zero, set the env var on Cloud Functions:
```bash
firebase functions:config:set impersonation.app_check_enforced="true"
# Or for the newer params API:
firebase functions:params:set IMPERSONATION_APP_CHECK_ENFORCED=true
```
Redeploy. All impersonation callables now refuse requests without a valid
App Check token.

### 2.5 Roll back
If the enforce flip causes issues, set the var back to `false` and redeploy.
Instant reversion — no client-side changes needed.

---

## 3. MFA enforcement on dev accounts

This is **policy, not code**. Firebase Auth supports multi-factor via SMS
(out of the box) and TOTP (preview). The impersonation pipeline doesn't
depend on MFA being enabled — but allowing a dev account to bypass MFA
undermines the whole privacy story.

### 3.1 Enable MFA in Firebase Auth
Firebase console → Authentication → Sign-in method → scroll to
Multi-factor authentication → enable SMS (default) or TOTP.

### 3.2 Require MFA for dev-access holders
Firebase Auth does not yet support "require MFA for users in group X"
natively. Workarounds:
- **Admin-enforced enrollment**: when adding a dev email to
  `devAccessEmails`, the super-admin notifies the dev that they must enroll
  a second factor. A separate client-side check (not implemented) can
  `multiFactor(user).enrolledFactors.length === 0` and refuse to start an
  impersonation session.
- **Policy-only for now**: write this into the contractor/developer
  agreement. Revisit when Firebase ships group-based MFA policies.

### 3.3 Client-side MFA guard (implemented — opt-in)
The guard is already in the code — just needs a build-time flag to turn on.

- **Flutter** ([lib/core/services/impersonation_service.dart](../lib/core/services/impersonation_service.dart), `start()`) — checks `FirebaseAuth.instance.currentUser.multiFactor.getEnrolledFactors()` before calling the Cloud Function. Enable with:
  ```bash
  flutter run --dart-define=LUMI_IMPERSONATION_REQUIRE_MFA=true
  ```
- **admin-web** ([school-admin-web/src/app/(authenticated)/dev/impersonate/impersonation-picker.tsx](../school-admin-web/src/app/(authenticated)/dev/impersonate/impersonation-picker.tsx), `handleStart()`) — checks `multiFactor(auth.currentUser).enrolledFactors`. Enable with `NEXT_PUBLIC_IMPERSONATION_REQUIRE_MFA=true` in `.env.production` (or the Vercel/hosting env settings).

Both throw a clear "Enrol a second factor" message when the user has no
enrolled factors. Off by default so existing dev accounts keep working
while the policy rolls out.

**Security note**: this is a FRICTION layer, not a security boundary. The
session doc gets created by the Cloud Function regardless of this guard —
a determined dev could bypass by calling the function directly. True
enforcement would require the Cloud Function to verify `auth.token.firebase.sign_in_second_factor` on the caller, which only gets set when they signed in via MFA.

---

## 4. Cloud Monitoring alerts

### 4.1 Anomaly detector (already deployed)
`monitorImpersonationAnomalies` runs hourly and emits a `severity=WARNING`
structured log with `eventType: "impersonation.anomaly"` whenever a single
developer exceeds:
- **5 distinct schools** impersonated in the last hour, OR
- **4 sessions** started in the last hour.

### 4.2 Wire a log-based alerting policy (step-by-step)

1. Open **GCP console → Monitoring → Alerting** (must be the `lumi-kakakids` project — double-check the top-bar project picker).
2. **Configure notification channels** first if none exist yet — click **Edit notification channels** → pick Email (simplest) → add super-admin email address → Save.
3. Back on Alerting, click **Create policy**.
4. **Select a metric** → switch to the **Logs** tab (not Metric). Click **Next: Add condition based on log events**.
5. **Log filter** (paste into the filter box):
   ```
   resource.type="cloud_function"
   resource.labels.function_name="monitorImpersonationAnomalies"
   jsonPayload.eventType="impersonation.anomaly"
   severity>=WARNING
   ```
6. **Condition type**: "Log match". Trigger: **any log entry that matches**.
7. **Alert threshold**: 0 (trigger on the first matching log line). **Retest window**: 5 min.
8. **Notifications**: select the Email channel from step 2.
9. **Incident auto-close**: 1 hour.
10. **Name**: `Impersonation anomaly detected`. **Severity**: Warning.
11. **Documentation** (optional but helpful — shown in the alert email):
    ```
    A developer has started an unusually high number of impersonation sessions
    or accessed an unusually high number of distinct schools in the last hour.

    Investigate in lumi-admin → Operations → Impersonation Audit. Filter by
    the `devUid` value in the alert payload.
    ```
12. **Save**.

**Verify it works** without waiting for a real anomaly:
```bash
# Temporarily lower the thresholds in functions/src/impersonation.ts
#   ANOMALY_SCHOOLS_PER_HOUR = 1
#   ANOMALY_SESSIONS_PER_HOUR = 1
# Redeploy monitorImpersonationAnomalies only, then:
gcloud functions call monitorImpersonationAnomalies
# Check Cloud Logging for the WARNING entry
# Check email for the alert (usually within 1–3 min)
# Restore thresholds + redeploy
```

### 4.3 Escalation runbook when an anomaly fires
1. Open lumi-admin → Operations → Impersonation Audit.
2. Filter by `devUid` from the alert payload.
3. Review the recent sessions + their reasons.
4. If the pattern looks unauthorised:
   - Revoke each active session individually.
   - Remove the dev from `/devAccessEmails` via Operations → Dev Access. This
     triggers `revokeOnDevAccessRemoval` which kills any remaining sessions
     within seconds.
5. Record the incident in your security log.

---

## 5. Day-2 operations

### 5.1 Granting a new dev access
lumi-admin → Operations → Dev Access → Add → email + optional note.
Effective within ~30s (dev-access cache TTL).

### 5.2 Revoking dev access
Same page, click Revoke. The Firestore onDelete trigger revokes any active
sessions for that dev instantly.

### 5.3 A dev calls and says "my session is stuck"
- In lumi-admin, find their active session under Impersonation Audit.
- Click Revoke with reason "manual unblock for <dev>".
- Their client will detect the status change within a few seconds (via the
  session doc snapshot listener) and sign out.

### 5.4 A school requests an audit trail
1. lumi-admin → Operations → Impersonation Audit.
2. Filter by `targetSchoolId` (use the school picker or exact ID).
3. For each relevant session, open the detail view → Export CSV.
4. Each export is itself logged (`audit_exported` event) — the school can
   verify that the export they received matches a corresponding log entry.

### 5.5 Emergency global kill-switch
There is no global kill-switch in code. If you need to immediately stop ALL
impersonation:
1. Clear the `devAccessEmails` collection (`firebase firestore:delete
   --recursive devAccessEmails --force`). All active sessions auto-revoke
   via the trigger.
2. Redeploy the `startImpersonationSession` function with a hardcoded
   `throw new HttpsError("unavailable", "…")` at the top.

Both actions are reversible but disruptive.

---

## 6. Routine maintenance

### 6.1 Monthly
- Review `/devAccessEmails` — revoke access for anyone no longer needing
  it. Each dev-access grant is logged in `/adminAuditLog` and visible under
  Operations → Audit Log.
- Review anomaly alerts over the past 30 days — tune thresholds if noise is
  high.

### 6.2 Quarterly
- Test the end-to-end flow: start a session, take a screenshot, try a
  mutation, exit, verify audit. Document the result in the security review.
- Review super-admin list. Confirm each entry still needs the privilege.

### 6.3 Yearly
- Rotate the `SESSION_SECRET` JWT signing secret for `school-admin-web`.
  This forces all active admin-web sessions — including any active
  impersonation sessions — to re-authenticate.

---

## 7. Disaster recovery

### 7.1 Audit log corruption
Audit events are append-only writes to `devImpersonationAudit` via the
Admin SDK. Clients cannot read or write this collection (enforced by rules).
If the collection is ever corrupted, restore from Firestore's point-in-time
recovery (requires PITR to be enabled on the project).

### 7.2 Forged claim suspicion
Claims are issued only by `admin.auth().createCustomToken(...)` inside a
Cloud Function. Anyone trying to forge a JWT would need the Firebase
project's signing key, which is only accessible to the service accounts
configured on the project. If you suspect forgery:
1. In Firebase console → Project settings → Service accounts, rotate the
   Firebase Admin SDK private key.
2. Redeploy all functions so they pick up the new key.
3. Every existing custom token becomes invalid.
4. Every impersonation session is effectively revoked.

### 7.3 Dev laptop compromise
1. Remove the dev's entry from `/devAccessEmails` (instant revoke of active
   sessions via trigger).
2. If MFA is enabled, invalidate all the dev's sessions via Firebase Auth:
   `admin.auth().revokeRefreshTokens(uid)`.
3. Review the impersonation audit for that dev over the retention window,
   export as CSV, archive for forensics.
