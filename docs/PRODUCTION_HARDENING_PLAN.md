# Lumi — Production Hardening & Platform Upgrade Plan

> **Purpose.** A single, ordered, execution-ready playbook for Claude to take Lumi (Flutter app + Next.js school portal + Cloud Functions + Firestore/Storage rules) from its current state to production quality. It combines the **security & stability review findings** (2026-07) with the **infrastructure upgrade TODOs** (Node 20→22, `firebase-functions` SDK bump, Gen1→Gen2 Cloud Functions migration).
>
> **Status when written:** app is LIVE in prod (`lumi-ninc-au`, `australia-southeast1`). The security findings below are therefore **live exposures of children's data**, not hypotheticals. Treat Phase 1 as an incident-response hotfix, not routine work.

---

## How to use this document

- Work **top to bottom**. Phases are ordered by a deliberate risk/dependency sequence (see "Why this order" below). Do not start a later phase before the earlier phase's **Done-when** boxes are all ticked, unless a task is explicitly marked *(parallelizable)*.
- Every task is self-contained: **Files → What/Why → Steps → Verify → Deploy → Rollback → Done-when.**
- After finishing each task, tick its checkbox and note the PR number inline.
- When a task says "verify the exact code first," **read the cited lines before editing** — line numbers drift as the tree changes.

### Ground rules for the executing agent (project conventions — do not violate)

1. **Branch → PR → squash-merge.** Every task gets its own prefixed branch (`fix/…`, `feat/…`, `chore/…`, `refactor/…`), push, open PR, squash-merge with auto-delete, ff-pull main. Group tightly-related edits into one PR; keep unrelated work out of it.
2. **Nothing but the admin portals is CI-deployed.** Cloud Functions, Firestore rules + indexes, Storage rules, and the Flutter app **all require a manual `firebase deploy` / app release**. **Production deploys must be confirmed with the user first.**
3. **Functions predeploy runs `eslint` + `tsc`.** Non-lint-clean or non-compiling code **blocks the entire functions deploy**. Keep every functions change lint-clean and type-clean.
4. **Surgical diffs only.** The repo is not `dart format`-enforced and has no format CI. **Never run `dart format` on whole files** (it reflows ~80 lines). Change only the lines you mean to change.
5. **Never run `next build` against a live `next dev` server** in `school-admin-web` (corrupts the shared `.next`). Verify the portal with `npx tsc --noEmit`; only do a full `next build` with the dev server stopped.
6. **Release builds** use `./scripts/flutter-build.sh <target>` (applies `.dart_define.json`), not raw `flutter build`.
7. **Concurrent sessions share this checkout.** Re-check branch/HEAD/index immediately before each commit; never `git checkout`/`restore`/`reset`/`stash` to undo your own work (use `Edit`) — a foreign uncommitted change may be present.
8. **Deploy divergence exists today:** the deployed `firestore.rules` is behind `origin/main` (missing the PR #200 messaging gate). Phase 1 includes reconciling and redeploying rules.

### Why this order

- **Security first, even though some fixes live inside functions that Phase 6 rewrites.** The vulnerabilities are exploitable in prod *now*; the fixes are tiny authorization guards that port to Gen2 with zero rework (the same check sits inside the new handler). Waiting weeks for a platform migration before closing a critical hole is unacceptable.
- **Platform upgrade (Node + SDK) is decoupled from and precedes the Gen2 rewrite.** `firebase-functions` v7 still supports `firebase-functions/v1`, so we can bump Node 22 + SDK v7 with **zero behavior change** first (low risk, fast), then do the Gen1→Gen2 handler rewrite incrementally on a known-good baseline.
- **UX/stability hardening sits between** — it's larger, lower-urgency, and partly parallelizable, but the portal CSV-import blocker gates a school's entire first-run, so it's early within that band.

### Global pre-flight (run once, before Phase 1)

- [ ] Confirm the git state is clean-ish and you know what foreign changes (if any) are present: `git status`.
- [ ] **Confirm in the Firebase Auth console whether open email/password self-signup is enabled.** This sets the exploitability of every "any signed-in user" finding. Record the answer here: `__________`. (If open — which is expected for a parent app — the Phase 1 criticals are reachable by anyone who signs up.)
- [ ] Snapshot the current Cloud Scheduler jobs and their regions (needed later to prove the Gen2 migration moved them and to find orphans):
  ```bash
  gcloud scheduler jobs list --project lumi-ninc-au --location us-central1
  gcloud scheduler jobs list --project lumi-ninc-au --location australia-southeast1
  ```
- [ ] Snapshot the live function inventory (source of truth for counts; the source tree shows ~42 deployable functions):
  ```bash
  firebase functions:list --project lumi-ninc-au
  ```
- [ ] Confirm a rollback path for rules: keep the currently-deployed ruleset retrievable (`firebase firestore:rules:get`-equivalent, or note the deployed git SHA).

---

# PHASE 1 — Security hotfixes (CRITICAL, release-blocking)

**Goal:** close every path by which an attacker — anonymous or any account holder — can bypass auth, cross the school boundary, or destroy/read children's data. Deploy each fix as soon as it is verified; do not batch all of Phase 1 into one big deploy. **Confirm each prod deploy with the user.**

Each finding below was verified against the actual source during the review. Line numbers are from the review snapshot — **re-read before editing.**

### 1.1 — Portal auth bypass: forged plain-JSON session cookie  ⟶ CRITICAL

- [ ] **PR:** `fix/portal-session-cookie-forgery`  (# ____ )

**Files**
- `school-admin-web/src/lib/auth/session.ts` (~L86–96, `getSession`)
- `school-admin-web/src/middleware.ts` (~L33–44, `getSessionData`) — **same bug, must fix both**

**What / Why.** When `jwtVerify` throws (which it does for any unsigned value), `getSession` falls through to `JSON.parse(cookie.value)` and accepts the result if it merely has `uid && schoolId && role`. `SESSION_SECRET` is never consulted. Anyone can set `__session` to `{"uid":"x","email":"x","schoolId":"<any-school>","role":"schoolAdmin","fullName":"x"}` and be treated as a full admin of any tenant, in both middleware and every API route. **Total authentication bypass + privilege escalation + cross-tenant.**

**Steps**
1. In `session.ts`, replace the `catch` body (the "Backward compat: try parsing as plain JSON" block) with a hard reject:
   ```ts
   } catch {
     // Invalid or unsigned cookie — never trust it.
     return null;
   }
   ```
2. Open `middleware.ts`, find the identical `JSON.parse` fallback in `getSessionData` (~L33–44), and remove it the same way — only a validly-signed JWT may be accepted.
3. Grep the whole portal for any other `JSON.parse(cookie` / manual cookie decoding to be sure this pattern exists nowhere else: `rg "JSON.parse\(.*cookie" school-admin-web/src`.

**Verify**
- `npx tsc --noEmit` in `school-admin-web` is clean.
- Manually: craft a fake `__session` cookie (plain JSON admin object) and confirm a protected API route now returns 401/redirect instead of data. A validly-signed cookie (real login) still works.

**Deploy** — portal is SSR on Cloud Run and **not** auto-deployed:
`FIREBASE_CLI_EXPERIMENTS=webframeworks firebase deploy --only hosting:school` (stop any local `next dev` first). Confirm with user.

**Rollback** — revert the PR and redeploy hosting.

**Done-when**
- [ ] Both `session.ts` and `middleware.ts` reject unsigned cookies.
- [ ] Forged-cookie request denied; real login works.
- [ ] Portal redeployed.

> ⚠️ **Session-invalidation note.** The removed branch was labelled "for existing sessions during rollout." Removing it will log out any user still holding a pre-JWT plain-JSON cookie; they simply re-login. Acceptable. Do not preserve the branch "just in case" — that *is* the vulnerability.

### 1.2 — `deleteStudentWithCascade` has no authorization  ⟶ CRITICAL

- [ ] **PR:** `fix/delete-student-cascade-authz`  (# ____ )

**Files**
- `functions/src/index.ts` (`deleteStudentWithCascade`, ~L2230–2308)

**What / Why.** The callable checks only `context.auth` (any signed-in user), then trusts client-supplied `schoolId`/`studentId` and deletes the student doc, revokes its link codes, and **deletes linked parents' Firebase Auth accounts** (`admin.auth().deleteUser(parentId)`, ~L2269). Any authenticated user can destroy any child and delete parent accounts in any school.

**Steps**
1. Read `backfillGuardianProfiles` (`functions/src/index.ts` ~L2521) first — it already does the correct staff-role check for a given school. Mirror that exact pattern for consistency.
2. Immediately after the `context.auth` guard and after validating `schoolId`/`studentId`, add an authorization check:
   ```ts
   // Authorization: caller must be a school admin or teacher of THIS school.
   const callerSnap = await db.doc(`schools/${schoolId}/users/${context.auth.uid}`).get();
   const callerRole = callerSnap.exists ? callerSnap.data()?.role : null;
   if (callerRole !== "schoolAdmin" && callerRole !== "teacher") {
     throw new functions.https.HttpsError(
       "permission-denied",
       "Only school staff can delete students.",
     );
   }
   ```
   (If product intent is admin-only deletion, drop the `"teacher"` branch — confirm with user; default to allowing both to match the portal UI that exposes delete.)
3. **Also fix the latent cascade bug flagged in review:** L2258 reads linked parents from `schools/${schoolId}/users/${parentId}`, but parent docs live under `schools/${schoolId}/parents/${parentId}` (see `getUserData` in `firestore.rules`, which checks `users` then `parents`). Verify where parents actually live, and if it's `parents/`, correct the read path so the cascade actually cleans parents instead of silently `continue`-ing. Add a test or manual check.

**Verify**
- `npm --prefix functions run build` (tsc) and `npm --prefix functions run lint` clean.
- Call the callable as a non-staff user (or with a foreign `schoolId`) → `permission-denied`. As a real school admin of the target school → succeeds.
- Confirm parent cleanup now targets the correct collection.

**Deploy** — single-function deploy is fine and fast:
`firebase deploy --only functions:deleteStudentWithCascade --project lumi-ninc-au`. Confirm with user.

**Rollback** — revert PR, redeploy the one function.

**Done-when**
- [ ] Authz check present and tested.
- [ ] Parent-collection path corrected.
- [ ] Function redeployed.

### 1.3 — Self-provision as teacher/parent in any school  ⟶ CRITICAL (most involved)

- [ ] **PR:** `fix/server-verified-school-join`  (# ____ )

**Files**
- `firestore.rules` — `users` create (~L189–205), `parents` create (~L247–256), `students` `parentIds` append (~L315–320)
- `functions/src/mfa_enrollment.ts` — `enrollLinkedPhoneAsMfa` (~L221–392), `finalizeTeacher` (~L175–219), `finalizeParent` (~L107–167)
- Signup call sites in the app (`lib/services/onboarding_service.dart`, `lib/services/school_code_service.dart`, `lib/screens/auth/…`) and portal (`school-admin-web/src/app/api/users/route.ts`, `api/users/import`) — whichever currently create user/parent docs.

**What / Why.** The `users` create rule grants `create` if `request.auth.uid == userId && role == 'teacher'`, with **no invitation/school-code verification** (the join-code check is client-only and bypassable via the raw SDK). `isTeacher()` reads exactly this self-authored doc, so any account holder becomes a teacher of any school → reads all children's PII. The same client-trust exists in `enrollLinkedPhoneAsMfa`, which writes a `role:'teacher'` user doc from a client-supplied `role`/`schoolId`/`email`. Parent self-provisioning (`parents` create) has the same shape.

**Approach — server-verified provisioning (recommended).** Make role-bearing membership creation prove a valid, unconsumed school code **server-side**, and deny privileged self-create in rules. This aligns with the existing phone-MFA signup architecture (enrol + finalise already run server-side via Admin SDK — see project memory "Phone-MFA signup architecture").

**Steps**
1. **Rules — deny privileged client self-create.**
   - `users` create: remove the `role == 'teacher'` self-create branch. Keep only: (a) `isSchoolAdmin(schoolId)` creating staff, and (b) the `schoolAdmin` bootstrap branch that already verifies `schools/{schoolId}.createdBy == request.auth.uid` (the first admin of a school they created). All other teacher creation must come from the Admin SDK (which bypasses rules).
   - `parents` create: same — require it come from the server linking flow, not a raw client write. If a minimal client-create must remain, gate it behind a server-set marker that a client cannot forge (e.g. a pre-created `pendingParent/{uid}` doc written by the linking function).
2. **Function — stop trusting client identity in `enrollLinkedPhoneAsMfa`.**
   - Derive `email` from the **verified token** (`context.auth.token.email`), never from `data.email`.
   - Gate `finalizeTeacher` (role:'teacher') on a **server-validated, unconsumed school join code** passed by the client and looked up by exact value with the Admin SDK (mark it consumed atomically). Reject if the code is missing/expired/used.
   - Apply the same to `finalizeParent` where relevant (parent linking already validates a link code via `linkParentToStudent` — reuse that path rather than trusting `role`).
   - Fix the `userSchoolIndex` poisoning: write `userSchoolIndex/{sha256(verifiedEmail)}` only, never from `data.email`.
3. **`students.parentIds` append (rules ~L315–320):** require proof of a valid `active` link code for that `studentId`, not merely "caller has a parent doc in the school." Simplest correct form: remove the client append path entirely and let the server `linkParentToStudent` callable be the sole writer of `parentIds` (it already validates the code TOCTOU-safely).
4. **Client call sites:** update app/portal signup + linking to call the server path (callable) with the school/link code, instead of writing the user/parent/`parentIds` docs directly. Verify no client code still does a direct privileged write that the tightened rules will now (correctly) reject.
5. **Tests:** add rules tests asserting that a signed-in user **cannot** create `schools/{other}/users/{self}` with `role:'teacher'` and **cannot** append themselves to an arbitrary student's `parentIds`. (Note: the existing test "users: teacher can create only own profile doc" currently asserts self-provisioning *succeeds* — update it to assert denial. See `functions/test/firestore.rules.test.js`.)

**Verify**
- `npm --prefix functions run test:rules` passes with the new denial tests.
- End-to-end: a legitimate teacher signup **with** a valid school code still succeeds via the server path; a raw-SDK attempt to self-create a teacher doc is denied.
- App signup + parent linking still work against the emulator / a test school.

**Deploy** — this touches rules **and** functions **and** the app/portal. Deploy in a safe order to avoid locking out real signups:
1. Deploy the **function** changes first (server path now validates codes) and the **client** changes (app release + portal) so legit flows use the server path.
2. Then deploy the **tightened rules** (`firebase deploy --only firestore:rules`) once you've confirmed no legitimate client still relies on the old self-create. Confirm each with user.

**Rollback** — rules and functions are independently revertible; keep the prior ruleset SHA. If a rules deploy breaks signup, redeploy the previous ruleset immediately while you diagnose.

**Done-when**
- [ ] Rules deny privileged client self-create; tests prove it.
- [ ] `enrollLinkedPhoneAsMfa` derives email from token and validates a server-side code for teacher finalisation.
- [ ] `parentIds` writes only via the validated server linking path.
- [ ] App + portal updated to the server path and released.
- [ ] Rules, functions, app, portal all deployed.

> This is the largest Phase 1 item and the one most likely to break legitimate onboarding if rushed. Do it carefully, test the real signup + linking flows end-to-end against a test school before the prod rules deploy, and keep the previous ruleset ready to redeploy.

### 1.4 — `resetUserPassword` IDOR / cross-tenant account takeover  ⟶ CRITICAL

- [ ] **PR:** `fix/reset-password-tenant-scope`  (# ____ )

**Files**
- `school-admin-web/src/lib/firestore/users.ts` (`resetUserPassword`, ~L310–313)
- `school-admin-web/src/app/api/users/[userId]/reset-password/route.ts` (~L15–16)

**What / Why.** `resetUserPassword(userId, schoolId)` does a **global** `adminAuth.getUser(userId)` and `generatePasswordResetLink(user.email)` with **no check that `userId` belongs to `session.schoolId`**, and the route **returns the reset link in the response body**. Any school admin can obtain a working reset link for any user in any school — including parents — and take over the account.

**Steps**
1. In `resetUserPassword`, before generating the link, load `schools/${schoolId}/users/${userId}` (the tenant-scoped doc) and throw/404 if it doesn't exist — proving the target is a member of the caller's school.
2. Reconsider returning the reset link at all. Prefer **emailing** the reset link to the target's on-file address (or triggering Firebase's built-in reset email) rather than returning it to the admin. If an admin-mediated flow is a hard product requirement, at minimum (a) confirm tenant membership as above, (b) restrict to `schoolAdmin` (see 2.3), and (c) never log the link.
3. Apply the same tenant-scoping review to sibling endpoints: `api/users/[userId]/credentials`, `api/profile/reset-password`.

**Verify**
- `npx tsc --noEmit` clean.
- As admin of School A, requesting a reset for a School B user (or a parent uid) → 404/denied. For an own-school staff user → works.

**Deploy** — `firebase deploy --only hosting:school`. Confirm with user.

**Done-when**
- [ ] Tenant membership enforced before link generation.
- [ ] Link no longer returned to the caller (or justified + gated + not logged).
- [ ] Sibling credential endpoints reviewed.
- [ ] Portal redeployed.

### 1.5 — Unauthenticated enumeration of link codes & school codes  ⟶ CRITICAL

- [ ] **PR:** `fix/code-enumeration-lockdown`  (# ____ )

**Files**
- `firestore.rules` — `studentLinkCodes` list (~L612–614) and `schoolCodes` list (~L681)
- New/existing callable for code verification (`functions/src/parent_linking.ts` / `functions/src/school_code_service`-equivalent server side)
- Client verify paths: `lib/services/parent_linking_service.dart`, `lib/services/school_code_service.dart`, and portal equivalents.

**What / Why.** `studentLinkCodes` list rule requires only `request.query.limit <= 10` (no `isSignedIn()`), so an anonymous client can paginate and **harvest every child-link code** (`code`, `studentId`, `schoolId`), then redeem one to link to a child. `schoolCodes` list allows `!isSignedIn() && request.query.limit == 1` — anonymous pagination harvests all active join codes (feeds 1.3).

**Steps**
1. **Move code verification server-side.** Add (or reuse) a callable `verifyStudentLinkCode(code)` and `verifySchoolCode(code)` that looks up by **exact value** with the Admin SDK and returns only a boolean / opaque short-lived token — never the raw code list.
2. **Rules:** delete the unauthenticated `list` rules for both collections. `studentLinkCodes` `get`/`list` should require `isSignedIn()` and ownership (`usedBy == uid` or staff of the code's school) — remove the broad `isParentMember(...)` `get` allowance too. `schoolCodes` should not be client-listable at all.
3. **Clients:** replace the "query the collection by code" logic with a call to the new callable(s). Handle the friendly expired/used/invalid messages from the callable's response (the app already renders clean messages for these states — preserve that UX).
4. **Tests:** add rules tests asserting a filter-less `limit(10)` list on `studentLinkCodes` and a `limit(1)` list on `schoolCodes` are **denied** (the current bounded-query test only exercises the happy path with a `where('code','==',…)` filter — extend it).

**Verify**
- Rules tests pass with the new denial cases.
- App/portal signup + parent linking still verify codes correctly via the callable, including the expired/used/revoked messages.

**Deploy** — order: deploy the **callable + client** first (so verification keeps working), then the **tightened rules**. Confirm with user.

**Done-when**
- [ ] Server-side code verification callable(s) live.
- [ ] Unauthenticated list rules removed; denial tests pass.
- [ ] Clients use the callable; code UX preserved.
- [ ] Functions, rules, app, portal deployed.

### 1.6 — Deploy pending rules + turn on App Check  ⟶ HIGH (defense-in-depth for all of Phase 1)

- [ ] **PR / action:** `chore/deploy-rules-and-appcheck`  (# ____ )

**What / Why.** (a) The deployed ruleset is behind `origin/main` (missing the PR #200 messaging gate); reconcile and redeploy so prod matches source, and so the Phase 1 rule tightenings actually take effect. (b) App Check is **off everywhere** — opt-in and default-OFF on the client (`lib/core/services/app_check_service.dart:27`) and unenforced on every callable. With it off, the Phase 1 criticals are reachable from any HTTP client holding a token. Turning it on raises the cost of scripted abuse substantially.

**Steps**
1. Reconcile `firestore.rules` with `origin/main` (ensure the messaging gate and every Phase 1 tightening are present in the file you deploy). Deploy: `firebase deploy --only firestore:rules,storage`. Confirm with user.
2. **App Check rollout (staged, avoid locking out real clients):**
   - Register the App Check providers in the Firebase console (Play Integrity / App Attest + reCAPTCHA Enterprise for web) and register debug tokens for internal devices.
   - Ship an app release built with `LUMI_APP_CHECK_ENABLED=true` (and the web reCAPTCHA key) so real clients start sending attestation tokens. `app_check_service.dart` already picks the right release providers behind `kDebugMode`.
   - **Only after** you confirm real traffic is sending valid App Check tokens (monitor in console), flip enforcement on the sensitive callables (`impersonation.ts` / `parent_linking.ts` already have opt-in enforce flags; add `enforceAppCheck` to `deleteStudentWithCascade`, `enrollLinkedPhoneAsMfa`, `createNotificationCampaign`, `requestSmsVerification`, etc.). In Gen2 (Phase 6) this becomes a per-trigger option.
3. Add `context.auth` requirement to `requestSmsVerification` (`sms_rate_limit.ts:85`) — it is currently unauthenticated and fails open; require auth (or App Check) so a victim's phone quota can't be exhausted anonymously.

**Done-when**
- [ ] Deployed rules match source (messaging gate + Phase 1 tightenings present).
- [ ] App Check enabled client-side and sending tokens; enforcement flipped on sensitive callables after verification.
- [ ] `requestSmsVerification` requires auth.

---

# PHASE 2 — Security HIGH / MEDIUM

*(Can start once Phase 1 criticals are deployed. 2.x items are independent of each other and parallelizable.)*

### 2.1 — Student `access` entitlement is client-writable  ⟶ HIGH (revenue/entitlement bypass)
- [ ] **PR:** `fix/student-access-field-allowlist`
- **File:** `firestore.rules` students update (~L311–312).
- **Fix:** the teacher/admin `students` `update` has no field allowlist, so any staff member can write `access.status='active'` / `access.expiresAt`. Add a `diff().hasOnly([...])` allowlist that **excludes** `access` (and other server-owned fields like reading-level/enrollment if those are meant to be server-only). `access` must be written only from the Admin SDK (renewals/subscriptions functions). Add a rules test asserting a client `access` write is denied.
- **Deploy:** `firebase deploy --only firestore:rules`.

### 2.2 — Comprehension voice recordings readable by any authenticated user  ⟶ HIGH (children's PII)
- [ ] **PR:** `fix/comprehension-audio-scope`
- **File:** `storage.rules` (~L44–49).
- **Fix:** `read: if request.auth != null` has no tenant/ownership scoping — any authed user can fetch any child's recording given the path (and a self-provisioned teacher could enumerate paths). Scope reads to school membership / the log's authorized parties. Because Storage rules can't cheaply read Firestore cross-service here (the prior attempt broke under `lumi-ninc-au`), the robust fix is **server-minted short-lived signed URLs**: a callable checks Firestore authorization and returns a signed URL; the Storage object itself is not client-readable. Alternatively bind reads to a path segment the client proves membership of. Do the same review for `community_books/covers` create/update (any authed user can overwrite any cover — bind to contributor).

### 2.3 — Portal role-gating inconsistency (teachers can hit admin-only mutations)  ⟶ MEDIUM
- [ ] **PR:** `fix/portal-api-role-gates`
- **Files:** `students/route.ts` (POST), `students/[studentId]/route.ts` (PATCH/DELETE), `students/bulk-delete`, `students/bulk-level`, `students/bulk-enrollment`, `students/[studentId]/enrollment`, `renewals/route.ts` (POST), `link-codes/route.ts` + `link-codes/bulk/route.ts`.
- **Fix:** page middleware makes these admin-only, but the API mutations don't check role. Add explicit `if (session.role !== 'schoolAdmin') return 403` in each handler (match the pattern already used by `settings`, `school-codes`, `users/*`). Don't rely on page-level middleware for API authorization.

### 2.4 — Cross-tenant link-code revoke/delete IDOR  ⟶ MEDIUM
- [ ] **PR:** `fix/link-code-tenant-check`
- **Files:** `school-admin-web/src/app/api/link-codes/[codeId]/route.ts`, `src/lib/firestore/link-codes.ts` (`revokeLinkCode`/`deleteLinkCode` ~L143–158).
- **Fix:** these operate on `.doc(codeId)` with no `schoolId` ownership check (the sibling `link-codes/reset` route does it correctly). Fetch the code doc and reject if `data.schoolId !== session.schoolId`.

### 2.5 — `students/import` unbounded + no role check  ⟶ MEDIUM (also see 4.7 for data-quality)
- [ ] **PR:** `fix/students-import-guard`
- **File:** `school-admin-web/src/app/api/students/import/route.ts` (~L16–27).
- **Fix:** add a `.max(...)` row cap to `importSchema` (staff import caps at 500 — match it) and a `schoolAdmin` role gate.

### 2.6 — `schoolOnboarding` unauthenticated create  ⟶ LOW/MEDIUM
- [ ] **PR:** `fix/school-onboarding-auth`
- **File:** `firestore.rules` (~L587–588).
- **Fix:** `allow create: if writeAllowedForDev()` is effectively open to anonymous callers with no field validation. Require `isSignedIn()` (or a validated onboarding token) and validate the document shape/required fields.

### 2.7 — Portal teacher comments may bypass the messaging feature-gate  ⟶ LOW (worth checking)
- [ ] **PR:** `fix/portal-comment-messaging-gate`
- **File:** `school-admin-web/src/lib/firestore/reading-logs.ts` (`addTeacherComment` ~L156–187).
- **Fix:** confirm whether this path checks the `messagingEnabled` flag that the app + rules enforce; if not, add the server-side check so a school that disabled messaging doesn't still deliver portal-originated comments.

---

# PHASE 3 — Stability & privacy hardening

*(Parallelizable with Phase 2. Lower urgency than security but still pre-scale.)*

### 3.1 — Encrypt / PII-strip local storage + disable Android backup  ⟶ MEDIUM (COPPA/GDPR-K)
- [ ] **PR:** `fix/pii-at-rest`
- **Files:** `android/app/src/main/AndroidManifest.xml`, `lib/services/offline_service.dart` (Hive box open ~L134–140), `lib/services/phone_verification_recovery_service.dart` (~L145).
- **Fix:** (a) set `android:allowBackup="false"` (or exclude the Hive dir via `dataExtractionRules`) so child PII isn't eligible for cloud/`adb` backup. (b) Encrypt the sensitive Hive boxes with a Keystore/Keychain-held `HiveAesCipher` key (add `flutter_secure_storage` to hold the key), or at minimum stop persisting the phone-recovery `contextJson` PII (email/full name/link-code/phone). Prioritize (a) — it's one line and high-leverage.

### 3.2 — Remove hardcoded test-admin credential from the shipped binary  ⟶ LOW/MEDIUM
- [ ] **PR:** `chore/remove-test-admin-creds`
- **Files:** `lib/utils/setup_test_data.dart` (creds ~L67–68, `print` at L122/211/329), imported by `lib/screens/auth/login_screen.dart:26`.
- **Fix:** `createTestSchool()` is dead code (unreachable from UI) but is compiled into the IPA/APK with a recoverable password (`admin@bps.edu.au` / `BPSAdmin2024!`). Move the file out of `lib/` into a dev-only `tool/` script and delete the hardcoded credential. If that account was ever created in prod, disable it in the Auth console.

### 3.3 — Gate PII `debugPrint`s behind `kDebugMode`  ⟶ LOW
- [ ] **PR:** `fix/release-log-pii`
- **Files:** `lib/services/notification_service.dart:500` (userId/schoolId + FCM token), `lib/services/crash_reporting_service.dart:52` (userId), `lib/core/services/dev_access_service.dart:103,106` (email).
- **Fix:** wrap in `if (kDebugMode)`. (Phone/SMS logs are already guarded — match that.)

### 3.4 — `setState` after async without `mounted` guard  ⟶ MEDIUM (crash)
- [ ] **PR:** `fix/onboarding-mounted-guard`
- **File:** `lib/screens/onboarding/school_registration_wizard.dart` (`_createSchoolAndCompleteOnboarding`, post-await `setState` at ~L190/206/212).
- **Fix:** add `if (!mounted) return;` before each post-await `setState` (same class as PR #198). Grep for sibling occurrences: `rg "setState" lib | rg -v mounted` and spot-check any that follow an `await`.

### 3.5 — Offline sync over-classifies `permission-denied` as permanent  ⟶ MEDIUM (data-parking)
- [ ] **PR:** `fix/offline-token-refresh`
- **File:** `lib/services/offline_service.dart` (permanent codes ~L1153–1162; drain ~L609–711).
- **Fix:** a stale-token race on cold-start drain can hit a transient `permission-denied` and permanently park a recoverable write. Force a fresh `getIdToken()` before draining, and/or give the first `permission-denied` a small bounded retry before parking. Do **not** blanket-remove `permission-denied` from the permanent set (genuine denials should still park).

### 3.6 — Fix bit-rotted test files (restore CI coverage)  ⟶ LOW (quality)
- [ ] **PR:** `chore/fix-broken-tests`
- **Files:** `test/widgets/stats_card_test.dart`, `test/screens/parent/reading_history_date_range_test.dart`, `test/services/school_library_service_test.dart`, `test/screens/teacher/teacher_library_screen_test.dart`.
- **Fix:** `flutter analyze` shows 17 errors — all in these test files referencing methods/params that no longer exist (`formatDurationMinutes`, `booksStream`, `totalMinutes`, `bestStreak`). They don't compile, so those tests silently don't run. Update them to the current APIs so they compile and pass. **Verdict target:** `flutter analyze` shows 0 errors (info-level `avoid_print` in `scripts/` is acceptable).

---

# PHASE 4 — Real-user experience (parent, teacher app, portal)

*(Larger effort; phase these by persona. **4.1 (portal CSV import) is the highest-priority UX item** — it gates a school's entire first run. After that, do the parent must-fixes, then the teacher-app systemic gaps.)*

### Portal (do first)

### 4.1 — CSV import is all-or-nothing and breaks on realistic data  ⟶ BLOCKER
- [ ] **PR:** `fix/portal-csv-import`
- **Files:** `school-admin-web/src/lib/firestore/students.ts` (~L424, L453–457, L459, L502–509), `src/components/.../csv-import-dialog.tsx` (~L53–55 parser, L281–288 counts, L88–93 header map).
- **Fix (all of):** (a) coerce/validate dates **per row** before the batch — `new Date("22/05/2020")` (AU dd/mm) yields Invalid Date and throws `Value for argument "seconds" is not a valid integer`, nuking the whole 400-row batch; Excel serials like `"43875"` become year-43874. Parse AU dd/mm and Excel serials explicitly; reject/null bad cells with a real per-row error. (b) Replace the raw comma-split parser with a real CSV parser (PapaParse) so quoted fields with commas don't shift columns. (c) Upsert on `studentId` instead of always `.doc()` (re-import currently duplicates students). (d) Fix count accounting so it can't go negative or report phantom created classes (don't push class names until the commit succeeds; recompute from committed rows). (e) Surface the header auto-map for manual override when a header isn't recognized.

### 4.2 — App-wide missing fetch-error states  ⟶ MAJOR
- [ ] **PR:** `fix/portal-error-states`
- **Files:** add `school-admin-web/src/app/(authenticated)/error.tsx`; `dashboard/page.tsx` (~L15–39, wrap Firestore await in try/catch); standardize `isError` handling in `class-report-tab.tsx`, `student-detail.tsx`, `analytics-page.tsx`, `library-page.tsx`, `reading-history-section.tsx` (grep shows only `parent-links/link-codes-tab.tsx:42` handles `isError`).
- **Fix:** every data view should render an error card + Retry on fetch failure instead of a hung spinner or a confident-but-false empty state ("0% participation", "no books", "didn't read"). Add the route-level `error.tsx` boundary.

### 4.3 — Unbounded analytics scans  ⟶ MAJOR (perf/timeout)
- [ ] **PR:** `fix/portal-analytics-queries`
- **Files:** `api/analytics/route.ts` (~L37–45), `src/lib/.../analytics.ts` (~L133–135).
- **Fix:** analytics runs ~5 separate unbounded full-period reading-log scans per load; "School Year" on a big school = 5 full-year scans → timeout surfaces as a misleading "No data". Fetch the period once and derive all aggregates in memory (or precompute server-side).

### 4.4 — Bulk link-code generation partial-success reporting  ⟶ MAJOR
- [ ] **PR:** `fix/portal-bulk-codes`
- **Files:** `src/lib/firestore/link-codes.ts` (`bulkCreateLinkCodes`), `generate-code-modal.tsx` (~L53–67).
- **Fix:** chunked `Promise.all` can partially succeed but reports a flat "Failed to generate codes"; a retry supersedes earlier codes so a parent may get an already-invalidated code. Return `{created, failed}` and make generation idempotent.

### 4.5 — Reading-group DnD / kanban partial-save is misleading  ⟶ MINOR
- [ ] **PR:** `fix/portal-dnd-allsettled`
- **Files:** `reading-group-organizer.tsx` (~L99–128), `classes/kanban-board.tsx` (~L170–187), `reading-groups-tab.tsx` (~L119–132).
- **Fix:** use `Promise.allSettled`, roll back optimistic reorders on failure, and report exactly which moves persisted.

### 4.6 — Portal media/audio `onError`  ⟶ MINOR
- [ ] **PR:** `fix/portal-audio-onerror`
- **File:** `log-media.tsx` (~L37).
- **Fix:** the `<audio>` has no `onError`; a 404/500 makes Play silently no-op. Add `onError` → "Recording unavailable".

### Parent (Flutter app) — must-fixes

### 4.7 — Licence-expired quick-log dead-end  ⟶ MAJOR (leans BLOCKER)
- [ ] **PR:** `fix/parent-quicklog-access-gate`
- **Files:** `lib/screens/parent/parent_home_screen.dart` (~L628, ~L1295), gate lives only in `lib/core/routing/app_router.dart:335`.
- **Fix:** the quick-log button calls `ReadingLogService.logReading()` directly with no `hasActiveAccess` check, so when a school's licence lapses at renewal the parent hits an endless "Couldn't log reading, try again" loop (and offline it's queued, celebrated, then parked). Check `hasActiveAccess` before the quick-log write (both home entry points **and** the widget drain) and route to `AccessLockedScreen`.

### 4.8 — Phone-only parents logged out on every cold start  ⟶ MAJOR
- [ ] **PR:** `fix/splash-phone-only-signout`
- **File:** `lib/screens/auth/splash_screen.dart` (~L62).
- **Fix:** splash force-signs-out any account without a verified email, but the app promotes phone-only signup (phone accounts always have `emailVerified == false`) → re-do phone + SMS every launch. Skip the email-verification gate when `refreshedUser.phoneNumber != null`. (Note the inconsistency with `login_screen.dart:269–281`, which treats unverified email as a non-blocking warning.)

### 4.9 — Offline "saved vs synced" ambiguity + lost feeling/audio  ⟶ MAJOR (data durability)
- [ ] **PR:** `fix/parent-offline-feedback-durability`
- **Files:** `lib/services/reading_log_service.dart` (`writeLog` returns `savedOffline` ~L320; `attachFeeling` ~L327–334 has no offline queue; siblings `attachComment`/`attachComprehension` do), `lib/screens/parent/log_reading_screen.dart` (~L469–477 drops `savedOffline`), `lib/screens/parent/reading_success_screen.dart` (~L254–262 swallows feeling with `catch (_)`), `lib/screens/parent/widgets/comprehension_recording_step.dart` (no lifecycle observer; temp-dir path ~L189–190).
- **Fix (all of):** (a) thread `savedOffline` to the success screen and show "Saved — will sync when you're online" + soften the stale night count. (b) Give `attachFeeling` the same offline-queue fallback as its siblings so the feeling isn't silently discarded offline. (c) Add a `WidgetsBindingObserver` to the comprehension recorder to stop+preview (or warn) on backgrounding, and copy confirmed recordings out of `getTemporaryDirectory()` into Documents/Support before queuing (iOS purges tmp → offline recordings lost).

### 4.10 — MFA login lockout with no recovery + signup-modal orphan  ⟶ MAJOR
- [ ] **PR:** `fix/parent-auth-recovery`
- **Files:** `lib/screens/auth/login_screen.dart` (~L1029–1114 MFA dialog), `lib/screens/auth/widgets/parent_registration_modal.dart` (close button ~L1143–1148; account created ~L613–618), `lib/screens/auth/forgot_password_screen.dart` (~L69–78).
- **Fix:** (a) add a "Can't receive the code?" link in the MFA dialog to a support/admin factor-reset path (currently only Resend/Cancel → hard lockout if the phone changed). (b) Confirm-before-dismiss past the SMS step (an accidental X orphans an email+password account with no parent doc; re-registration then collides with `email-already-in-use`); surface the pending-recovery entry. (c) Forgot-password: add a "signed up with a phone number?" hint so phone-only parents aren't stuck at "No user found".

### 4.11 — Parent polish (batch)  ⟶ MINOR
- [ ] **PR:** `fix/parent-polish`
- Friendly error + Retry instead of raw exception text on achievements (`achievements_screen.dart:141,693`) and reports (`student_report_screen.dart:444,462,479`). Replace placeholder store URLs + add a copyable fallback (`web_not_available_screen.dart:16–27`). Use the non-destructive `clearCachedData()` for "Clear offline cache" (`offline_management_screen.dart:309` currently calls `clearLocalData()` which wipes the sync queue + drafts). Hide the "Search feature coming soon!" dead affordance (`book_browser_screen.dart:748,752`). Bound the duplicate-log check with a `date >=` filter (`log_reading_screen.dart:270–300` currently reads the child's entire log collection on every open).

### Teacher (Flutter app) — systemic gaps

### 4.12 — Kiosk/scan/allocation write path has no offline handling  ⟶ BLOCKER (classroom)
- [ ] **PR:** `fix/teacher-scan-offline`
- **Files:** `lib/screens/teacher/kiosk/kiosk_scan_session_screen.dart` (~L225–236, error ~L180–181), `lib/services/isbn_assignment_service.dart` (`_upsertWeeklyAllocation` `runTransaction` ~L316; `resolveIsbn` swallows network errors → `IsbnNotFound` ~L169–173), `lib/screens/teacher/allocation/isbn_scanner_screen.dart` (~L276–311).
- **Fix:** the scan/allocation write uses `runTransaction` with no offline guard — on flaky Wi-Fi scans are silently lost and **real books are mislabeled "couldn't find that book."** Gate the persist on `canWriteToFirebase` and queue offline (mirror the reading-log queue), and distinguish an offline/network error from a genuine `IsbnNotFound`.

### 4.13 — Read streams have no `hasError` branch  ⟶ MAJOR (screens lie)
- [ ] **PR:** `fix/teacher-stream-error-states`
- **Files:** infinite spinners at `student_detail_screen.dart:2181–2196`, `teacher_student_reading_history_screen.dart:147–150` (needs a `studentId+date` composite index); false-empty dashboard cards at `dashboard_engagement_card.dart:144–150`, `dashboard_unread_comments_card.dart:86–89`, `dashboard_weekly_chart.dart:150–153`, `dashboard_recent_reading_card.dart:105–108`.
- **Fix:** add a `snapshot.hasError` → inline "Couldn't load — retry" branch everywhere (especially the two infinite-spinner sites). Create any missing composite index the history query needs.

### 4.14 — Unread-parent-comments card hides real replies  ⟶ MAJOR
- [ ] **PR:** `fix/teacher-unread-comments-query`
- **File:** `lib/screens/teacher/dashboard/widgets/dashboard_unread_comments_card.dart` (~L63–76).
- **Fix:** it pulls the latest 80 logs **by log date**, so a reply on an older log never surfaces (80 logs ≈ under a day for a big class) → shows "Up to date" while the teacher misses replies. Query by unread state (`unreadByTeacher` / `lastCommentAt`), not recent log date.

### 4.15 — Comment composer + allocation/renew swallow failures  ⟶ MAJOR
- [ ] **PR:** `fix/teacher-write-feedback`
- **Files:** `lib/core/widgets/comments/comment_thread.dart` (~L90–102 `try/finally` no catch; offline clears text silently, see `reading_log_service.dart:526–539`), `allocation/active_allocations_tab.dart` (~L100–107 delete, no try/catch/snackbar), `student_detail_screen.dart` (~L1066–1147 renew loop, no try/catch, partial writes).
- **Fix:** add `catch` + error snackbar (and a "queued" affordance offline) to the comment composer; add try/catch + success/error snackbars to allocation delete and the renew loop; report partial success on the renew loop.

### 4.16 — Big-class performance cliffs  ⟶ MAJOR (100+ students)
- [ ] **PR:** `fix/teacher-bigclass-queries`
- **Files:** `class_report_screen.dart` (~L494–510 N+1: one awaited `readingLogs.get()` per student), `teacher_dashboard_view.dart` (~L404–491 unbounded 30-day whole-class query on init and every `didUpdateWidget`), `dashboard_reading_calendar_card.dart` (~L59–66 `.limit(3000)`), `allocation/new_allocation_tab.dart` (~L1045–1071 N-students × M-books sequential reads before every save).
- **Fix:** replace N+1 with a single `classId + date`-range query grouped client-side; cap/`.limit` and one-shot `.get()` the dashboard queries; batch the previously-read conflict checks (`whereIn`/`Future.wait`) or skip for whole-class allocations. Add friendly errors on the report (raw exceptions at ~L535–549).

### 4.17 — Empty-class dead-end + teacher polish  ⟶ MAJOR / MINOR
- [ ] **PR:** `fix/teacher-emptyclass-and-polish`
- **Fix:** a brand-new empty class (`teacher_classroom_screen.dart:895–918`) offers only "Choose Another Class"/"Refresh" — there is **no teacher add-student flow anywhere** (rosters come from admin/import), so add guidance ("Students are added by your school admin" / route to roster setup). Batch the remaining teacher polish: profile stats use the legacy `teacherId`/`assistantTeacherId` schema instead of canonical `teacherIds` (`teacher_profile_screen.dart:57,69` → teacher sees zero/fewer classes; Reports stat hardcoded `'0'` at L140; "Export Reports coming soon" L305–311); server-side library search (`teacher_library_screen.dart:216–228` only filters the ~50 loaded books → "No books match" on page 3+); distinguish error from empty on login class-load (`teacher_home_screen.dart:108–113`); route away from / delete the orphaned buggy `ClassDetailScreen` (`app_router.dart:504–515`, `class_detail_screen.dart`); centralize a friendly-error mapper for the ~13 screens leaking raw `[cloud_firestore/...]` text to users.

---

# PHASE 5 — Cloud Functions platform upgrade (Node 22 + `firebase-functions` v7)

**Goal:** get onto a supported runtime and the current SDK **with zero behavior change**, on a known-good Gen1 baseline, before attempting the Gen2 rewrite. `firebase-functions` v7 still ships `firebase-functions/v1`, so we can bump without touching handler logic.

> **Why now, not fused with Gen2:** decoupling means if the SDK/Node bump surfaces a problem, it's isolated from the (much larger) handler rewrite. It also unblocks the Node 20 deprecation deadline independently of finishing all ~42 rewrites.

### 5.0 — Confirm the runtime deadline & baseline
- [ ] Check the current Node 20 deprecation/decommission status for Cloud Functions (the runtime keeps working through deprecation; **decommission is the hard cutoff** after which deploys/execution fail). Record the decommission date here: `__________`.
- [ ] Confirm the green baseline: `npm --prefix functions ci`, `npm --prefix functions run lint`, `npm --prefix functions run build`, `npm --prefix functions run test:functions` all pass **before** changing anything.

### 5.1 — Bump SDK + Node, keep v1 imports
- [ ] **PR:** `chore/functions-node22-sdk7`
- **File:** `functions/package.json`.
- **Steps:**
  1. `"engines": { "node": "22" }`.
  2. `"firebase-functions": "^7.2.5"` (latest at time of writing — re-check `npm view firebase-functions version`). Keep `firebase-admin` current (`^12` is fine; bump only if v7 requires it — check peer deps).
  3. Bump the toolchain if needed so the build stays clean: `typescript` (v4.9 → v5.x is safe and recommended), `@typescript-eslint/*` and `eslint` if the newer TS needs it. Make the **minimum** changes required to keep `lint` + `build` green.
  4. **Do not change any handler code yet.** If v7 removed a v1 symbol you use, switch that import to the explicit `firebase-functions/v1` path (e.g. `import * as functions from "firebase-functions/v1";`) rather than rewriting the handler. The shared `const fns = functions.region("australia-southeast1")` builder pattern continues to work under `firebase-functions/v1`.
  5. `npm --prefix functions ci` to regenerate the lockfile; commit it.
- **Verify:** `lint` + `build` + `test:functions` all green. Diff the compiled output or run the emulator (`npm --prefix functions run serve`) and smoke-test a callable + a Firestore trigger + a scheduled function (`firebase functions:shell`).
- **Deploy:** deploy **all** functions together (runtime change): `firebase deploy --only functions --project lumi-ninc-au`. Confirm with user; expect every function to be updated (new runtime). Watch `firebase functions:log` for cold-start errors immediately after.
- **Rollback:** revert `package.json` + lockfile and redeploy. (Keep the pre-bump SHA handy.)
- **Done-when:** all functions running Node 22 / `firebase-functions` v7 with identical behavior; logs clean; `firebase functions:list` shows the new runtime.

> **Gotcha:** if bumping the Node runtime of the existing Gen1 functions in place proves troublesome, the alternative is to defer the Node bump into Phase 6 (Gen2 functions are created fresh, so they pick up Node 22 cleanly). Prefer 5.1 for the deadline, fall back only if a specific function won't redeploy.

---

# PHASE 6 — Gen1 → Gen2 migration (all functions)

**Goal:** rewrite every function from Gen1 handlers to Gen2 (`firebase-functions/v2`), running on Cloud Run, with **all triggers and scheduled jobs in `australia-southeast1` (Sydney)**, then remove the orphaned `us-central1` scheduler jobs/topics. Migrate **incrementally** — a few functions per deploy, low-risk/low-traffic first, hot-path Firestore triggers last and during low traffic.

Reference: https://firebase.google.com/docs/functions/2nd-gen-upgrade

### Function inventory (source of truth for this phase)

The tree has **~42 deployable functions** (confirm the live count with `firebase functions:list`): **19 callables**, **13 Firestore triggers**, **~9–10 scheduled jobs**. Grouped for incremental migration:

**Callables (`https.onCall`) — 19** — *migrate first (easiest, lowest blast radius):*
- Impersonation (8): `startImpersonationSession`, `endImpersonationSession`, `revokeImpersonationSession`, `reportImpersonationActivity`, `reportBlockedWrite`, `exportImpersonationAudit`, `listImpersonableSchools`, `listImpersonableUsers` — `impersonation.ts`
- Admin/backfill (5): `backfillAchievements`, `deleteStudentWithCascade`, `backfillGuardianProfiles`, `sendTestReadingReminder`, `createNotificationCampaign` — `index.ts`
- Linking/access (4): `linkParentToStudent`, `unlinkParentFromStudent` (`parent_linking.ts`); `renewStudents` (`renewals.ts`); `enrollLinkedPhoneAsMfa` (`mfa_enrollment.ts`)
- Other (2): `deleteComprehensionAudio` (`comprehension_retention.ts`); `requestSmsVerification` (`sms_rate_limit.ts`)

**Scheduled (`pubsub.schedule` / `.schedule`) — ~9–10** — *migrate second (verify Sydney region + delete us-central1 orphans):*
- `cleanupComprehensionAudio` — `comprehension_retention.ts:165` — `"every 24 hours"`, TZ `Australia/Sydney`
- `dispatchScheduledNotificationCampaigns` — `index.ts:942` — `"every 5 minutes"`, UTC
- `sendReadingReminders` — `index.ts:1202` — `"0 * * * *"`, UTC
- `pruneStaleFcmTokens` — `index.ts:1297` — `"0 4 * * 1"`, UTC
- `cleanupExpiredLinkCodes` — `index.ts:1576` — `"0 2 * * *"`
- `reconcileStatsScheduled` — `index.ts:2205` — `"0 3 * * 0"`, UTC
- `processPendingUserDeletions` — `index.ts:2317` — `"0 * * * *"`, UTC
- `annualRollover` — `renewals.ts:180` — `"0 2 25 1 *"`, TZ `DEFAULT_TIMEZONE`
- `expireImpersonationSessions` — `impersonation.ts:852` — `"every 5 minutes"`
- `monitorImpersonationAnomalies` — `impersonation.ts:956` — `"every 60 minutes"`

**Firestore triggers (`firestore.document(...)`) — 13** — *migrate last; hot-path (readingLogs/students) during low traffic:*
- `onSchoolSubscriptionWrite` — `subscriptions.ts:79` — `schoolSubscriptions/{subId}` — onWrite
- `maintainLibraryCounts` — `library_counts.ts:97` — `schools/{schoolId}/books/{bookId}` — onWrite
- `revokeOnDevAccessRemoval` — `impersonation.ts:898` — `devAccessEmails/{emailHash}` — onDelete
- `aggregateStudentStats` — `index.ts:112` — `schools/{schoolId}/readingLogs/{logId}` — onWrite  *(hot path)*
- `processQueuedNotificationCampaign` — `index.ts:926` — `schools/{schoolId}/notificationCampaigns/{campaignId}` — onCreate
- `detectAchievements` — `index.ts:1364` — `schools/{schoolId}/students/{studentId}` — onUpdate
- `validateReadingLog` — `index.ts:1518` — `schools/{schoolId}/readingLogs/{logId}` — onCreate  *(hot path)*
- `processParentOnboardingEmail` — `index.ts:1709` — `schools/{schoolId}/parentOnboardingEmails/{emailId}` — onCreate  *(secrets)*
- `processStaffOnboardingEmail` — `index.ts:1948` — `schools/{schoolId}/staffOnboardingEmails/{emailId}` — onCreate  *(secrets)*
- `updateClassStats` — `index.ts:2116` — `schools/{schoolId}/readingLogs/{logId}` — onWrite  *(hot path)*
- `syncGuardianProfiles` — `index.ts:2385` — `schools/{schoolId}/parents/{parentId}` — onWrite
- `refreshGuardianProfilesOnLink` — `index.ts:2457` — `schools/{schoolId}/students/{studentId}` — onWrite
- `onCommentCreated` — `index.ts:2602` — `schools/{schoolId}/readingLogs/{logId}/comments/{commentId}` — onCreate

### 6.0 — Migration mechanics (apply consistently to every function)

- **Global region:** replace the per-file `const fns = functions.region("australia-southeast1")` pattern. Set it once with `import { setGlobalOptions } from "firebase-functions/v2"; setGlobalOptions({ region: "australia-southeast1" });` (in `index.ts`, imported before any trigger). You may still pass `region` per-trigger for clarity.
- **Callable:** `functions.region(...).runWith(opts).https.onCall((data, context) => {...})` → `import { onCall, HttpsError } from "firebase-functions/v2/https";` then `onCall({ ...opts }, (request) => {...})`. Remap inside the body: `data` → `request.data`; `context.auth` → `request.auth`; `context.auth.uid` → `request.auth.uid`; `context.rawRequest` → `request.rawRequest`. Throw `HttpsError` from the v2 import. Add `enforceAppCheck: true` here where Phase 1.6 called for it.
- **Firestore triggers:** `import { onDocumentWritten, onDocumentCreated, onDocumentUpdated, onDocumentDeleted } from "firebase-functions/v2/firestore";`
  - onWrite → `onDocumentWritten({ document: "path", ...opts }, (event) => {...})` — `change.before/after` → `event.data.before/after`; `context.params` → `event.params`.
  - onCreate → `onDocumentCreated` — the created snapshot is `event.data` (not `event.data.after`).
  - onUpdate → `onDocumentUpdated` — `event.data.before/after`.
  - onDelete → `onDocumentDeleted` — the deleted snapshot is `event.data`.
  - **Guard for undefined `event.data`** (Gen2 can deliver events with no snapshot) before using it.
- **Scheduled:** `import { onSchedule } from "firebase-functions/v2/scheduler";` then `onSchedule({ schedule: "expr", timeZone: "TZ", ...opts }, async (event) => {...})`. The old `.onRun((context) => ...)` body becomes the handler with no `context`. **In Gen2 the Cloud Scheduler job is created in the function's region → these move to Sydney automatically.**
- **RuntimeOptions → per-trigger options.** `.runWith({ timeoutSeconds, memory, secrets })` becomes fields in the trigger's options object. **Memory unit change:** Gen1 `"256MB"`/`"512MB"` → Gen2 `"256MiB"`/`"512MiB"` (MiB, string enum). Map every function's memory/timeout from the review inventory (e.g. `cleanupComprehensionAudio` 540s/512MiB; `processParentOnboardingEmail` 120s/512MiB + `secrets`).
- **Secrets:** `defineSecret(...)` already works in v2 — pass via the `secrets: [...]` option on the trigger. `processParentOnboardingEmail` and `processStaffOnboardingEmail` use `sendgridApiKey`/`sendgridSenderEmail`.
- **Concurrency (important gotcha):** Gen2 defaults to **80 concurrent requests per instance**; Gen1 was 1. Any function relying on module-global mutable state or non-reentrant logic can now race. **Start every migrated function at `concurrency: 1`** to preserve Gen1 semantics, then raise deliberately per function after review. Stateless functions can go higher.
- **Invoker/IAM:** Gen2 `onCall` sets its invoker so the app can call it (auth enforced in-code); after deploying a callable, confirm the app can still invoke it (no `PERMISSION_DENIED` from IAM). Firestore/scheduled triggers are event-driven (no invoker concern).
- **Deletion/recreation:** switching a function name from Gen1 to Gen2 **deletes the Gen1 function and creates a Gen2 one** with the same name. Firebase will prompt to confirm the delete during deploy. There is a **brief window with no trigger** — for Firestore triggers this can **miss events**. Deploy hot-path triggers during **low traffic**, and for critical aggregations consider running the matching backfill/reconcile function afterward (`reconcileStatsScheduled`, `backfillAchievements`) to heal any gap.

### 6.1 — Migrate callables (group 1)
- [ ] **PR(s):** `refactor/gen2-callables-impersonation`, `refactor/gen2-callables-admin`, `refactor/gen2-callables-linking`
- Migrate the 19 callables in the sub-groups above. **Deploy per group**, e.g.:
  `firebase deploy --only functions:startImpersonationSession,functions:endImpersonationSession,…`
- **Preserve every Phase 1 authz change** exactly (the guards move inside the new `onCall` handler unchanged). `deleteStudentWithCascade` keeps its 1.2 staff check; `enrollLinkedPhoneAsMfa` keeps its 1.3 server-code validation.
- **Verify per group:** call each from a client / `functions:shell`; confirm auth + App Check behavior; watch logs. Confirm the app still invokes them (IAM).
- **Done-when:** all 19 callables are Gen2, deployed, and behaving identically (plus their Phase 1 guards).

### 6.2 — Migrate scheduled functions (group 2)
- [ ] **PR:** `refactor/gen2-scheduled`
- Migrate all scheduled jobs; deploy in 1–2 batches.
- **After deploy, verify region moved to Sydney:**
  ```bash
  gcloud scheduler jobs list --project lumi-ninc-au --location australia-southeast1
  ```
  Confirm each migrated job appears here with the correct cron + timezone.
- **Delete orphaned Gen1 jobs/topics in us-central1** (compare against the Phase-0 snapshot):
  ```bash
  gcloud scheduler jobs list   --project lumi-ninc-au --location us-central1
  gcloud scheduler jobs delete <job> --project lumi-ninc-au --location us-central1
  # and remove any orphaned Pub/Sub topics the Gen1 scheduled functions created
  gcloud pubsub topics list --project lumi-ninc-au
  ```
- **Preserve timezones exactly** (`annualRollover` = `DEFAULT_TIMEZONE`; `cleanupComprehensionAudio` = `Australia/Sydney`; the rest UTC). A wrong TZ shifts the 25-Jan rollover and the reminder cadence.
- **Done-when:** all scheduled jobs Gen2, showing `australia-southeast1`; no orphaned us-central1 jobs/topics remain; timezones/crons unchanged.

### 6.3 — Migrate Firestore triggers (group 3 — hot path last)
- [ ] **PR(s):** `refactor/gen2-triggers-lowtraffic`, `refactor/gen2-triggers-hotpath`
- Migrate low-traffic triggers first (`onSchoolSubscriptionWrite`, `maintainLibraryCounts`, `revokeOnDevAccessRemoval`, `detectAchievements`, both onboarding-email triggers, `processQueuedNotificationCampaign`, `syncGuardianProfiles`, `refreshGuardianProfilesOnLink`, `onCommentCreated`).
- Migrate the **hot-path readingLogs triggers last and during low traffic**: `aggregateStudentStats`, `validateReadingLog`, `updateClassStats` (all on `schools/{schoolId}/readingLogs/{logId}`). After deploying these, run `reconcileStatsScheduled` (and `backfillAchievements` if relevant) once to heal any events missed during the swap window. Note: `validateReadingLog` is a validation-on-create trigger — a brief gap could let an invalid log through; reconcile/spot-check after.
- **Verify per group:** trigger each path in a test school (write the relevant doc) and confirm the Gen2 function fires with correct `event.data`/`event.params`; watch logs for undefined-data or memory-unit errors.
- **Done-when:** all 13 triggers Gen2; stats/achievements reconciled; no duplicated or missing triggers in `firebase functions:list`.

### 6.4 — Post-migration cleanup & verification
- [ ] Remove any remaining `firebase-functions/v1` imports and the per-file `functions.region(...)` builders now that everything is v2 (leave `v1` only if a specific API genuinely has no v2 equivalent — document why).
- [ ] `firebase functions:list` shows **all** functions as **2nd gen** in `australia-southeast1`; no leftover Gen1 duplicates.
- [ ] `gcloud scheduler jobs list --location us-central1` is empty (or only intentionally-external jobs remain).
- [ ] `lint` + `build` + `test:functions` + `test:rules` all green.
- [ ] Update project memory: functions are Gen2 on Node 22 / `firebase-functions` v7, scheduler in Sydney, us-central1 orphans removed (supersedes the "scheduler in us-central1" note).

---

## Appendix A — Per-task deploy cheat-sheet

| Change type | Command | CI-deployed? |
|---|---|---|
| Firestore/Storage rules | `firebase deploy --only firestore:rules,storage` | No — manual, confirm prod |
| One Cloud Function | `firebase deploy --only functions:<name>` | No — manual, confirm prod |
| All Cloud Functions | `firebase deploy --only functions` | No — manual, confirm prod |
| School portal | `FIREBASE_CLI_EXPERIMENTS=webframeworks firebase deploy --only hosting:school` (stop `next dev` first) | No — manual |
| Flutter app | `./scripts/flutter-build.sh <target>` → store/release pipeline | No — manual release |
| Admin portal | (CI-deployed on merge to main) | Yes |

## Appendix B — Verification quick-reference

- Functions: `npm --prefix functions run lint && npm --prefix functions run build && npm --prefix functions run test:functions`
- Rules: `npm --prefix functions run test:rules` (Firestore) / `test:rules:storage`
- Portal: `cd school-admin-web && npx tsc --noEmit` (never `next build` against a live dev server)
- Flutter: `flutter analyze` (target: 0 errors in `lib/`) — Phase 3.6 restores test-file compilation
- Live infra: `firebase functions:list`, `gcloud scheduler jobs list --location <region>`

## Appendix C — Sequencing summary (one screen)

1. **Phase 1 (now):** portal cookie bypass → `deleteStudentWithCascade` authz → server-verified school join (rules + MFA fn + clients) → reset-password tenant scope → code-enumeration lockdown → deploy pending rules + App Check. *Deploy each as verified; confirm prod.*
2. **Phase 2:** access-field allowlist, audio scoping, portal role gates, link-code IDOR, import guard, onboarding auth, messaging-gate check.
3. **Phase 3:** PII at rest + Android backup, remove test creds, release-log PII, mounted guards, offline token refresh, fix broken tests.
4. **Phase 4:** portal CSV import (first) → portal error states/analytics → parent access-gate/splash/offline-durability/auth-recovery → teacher scan-offline/error-states/unread-comments/write-feedback/big-class/empty-class.
5. **Phase 5:** Node 22 + `firebase-functions` v7, v1 imports retained, zero behavior change; deploy all functions.
6. **Phase 6:** Gen1→Gen2 incrementally — callables → scheduled (verify Sydney, delete us-central1 orphans) → Firestore triggers (hot path last, reconcile after). Final cleanup + memory update.

> **Do not** start Phase 5/6 until Phase 1 is fully deployed — live children's-data vulnerabilities must not wait behind a platform migration.
