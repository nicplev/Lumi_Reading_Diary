# AU Region Migration Runbook — `lumi-kakakids` → new AU project

Goal: stand up a new Firebase project with **Firestore, Storage, and Cloud Functions in
`australia-southeast1` (Sydney)**, move the existing test data across, repoint all four code
surfaces (Flutter app, `functions/`, `admin/` super-admin portal, `school-admin-web/`), and
decommission the old us-central1 project.

The new project ID is **`lumi-ninc-au`**, used consistently throughout this doc.

**Why each step exists is grounded in the actual codebase** — file:line references are included
so you can verify before changing anything.

---

## Phase 0 — Facts discovered in this codebase (read first)

These drive the plan; the original "repoint config" estimate missed several of them.

1. **Functions have NO region config.** No `setGlobalOptions` or `.region()` anywhere in
   `functions/src/`. All 34 functions (14 callables, 12 Firestore triggers, 8 scheduled)
   default to `us-central1`. In the new project, **v2 Firestore triggers must be co-located
   with the database region** — with an `australia-southeast1` database, deploying triggers
   without region pinning will fail or mis-deploy. Code change required (Phase 2.1).
   Sydney has full service coverage for this stack: Cloud Run, Functions gen-2, Eventarc,
   and Cloud Scheduler all support `australia-southeast1` (note: Cloud Scheduler does NOT
   exist in `australia-southeast2`/Melbourne — one reason Sydney is the right choice).

2. **All clients call functions in the default region (`us-central1`).**
   - Flutter: `FirebaseFunctions.instance` (no region) across
     `lib/services/impersonation_service.dart`, `lib/services/staff_notification_service.dart`,
     `lib/services/parent_linking_service.dart`, `lib/services/comprehension_audio_service.dart`
     (10 callables total).
   - Admin portal: `admin/src/lib/callDeployedCallable.ts:7` —
     `FUNCTIONS_REGION ?? "us-central1"`, builds a raw
     `https://${region}-${projectId}.cloudfunctions.net/...` URL.
   - School admin: `school-admin-web/src/lib/firebase/client.ts` — `getFunctions(app)` with no
     region arg.
   All three need the region passed explicitly (Phase 2).

3. **No Google/Apple sign-in, but email/password AND phone auth.** No `google_sign_in` /
   `sign_in_with_apple` in `pubspec.yaml`, so the old plan's "reconfigure OAuth clients" step
   is **not needed**. But parent registration has a phone-primary path —
   `lib/services/sms_verification_service.dart` calls `verifyPhoneNumber` (3 flows), backed by
   the `functions/src/sms_rate_limit.ts` gate (`platformConfig/smsRateLimits`) — so the
   **Phone provider must be enabled** alongside Email/Password (Phase 1.3). What IS also
   needed: hash-preserving Auth user export/import (Phase 4.1) because `superAdmins/{uid}`,
   `users`, FCM token docs, and impersonation audit all key off UIDs (phone numbers carry
   through the same export).

4. **APNs + FCM are real.** `firebase_messaging ^16.0.3` with token storage per parent doc,
   plus `aps-environment` entitlement (`ios/Runner/Runner.entitlements:5-6`). The APNs auth key
   (.p8) must be uploaded to the new project. Old FCM tokens in imported data are dead (tokens
   are bound to the old project's sender ID `432054475733`); clients re-register on next launch
   and `pruneStaleFcmTokens` (Mondays 04:00 UTC) cleans the rest.

5. **`ios/Runner/Info.plist:38-44` hardcodes a Firebase-derived URL scheme**
   (`app-1-432054475733-ios-3e84170b90653be9963b5c` — the GOOGLE_APP_ID with dashes).
   `flutterfire configure` regenerates `firebase_options.dart` and the plist/json config files
   but does **not** touch Info.plist URL schemes — manual edit (Phase 2.2).

6. **Secrets & env defaults in functions:**
   - Secret Manager: `SENDGRID_API_KEY`, `SENDGRID_SENDER_EMAIL` (`functions/src/index.ts:6-7`)
     — must be re-created in the new project (Phase 5.1).
   - `STAFF_PORTAL_URL` defaults to `https://lumi-school-admin.web.app`
     (`functions/src/index.ts:1868`) — staff onboarding emails embed this; if the hosting site
     ID changes, set the env var (Phase 5.2).
   - `IMPERSONATION_APP_CHECK_ENFORCED` / `PARENT_LINKING_APP_CHECK_ENFORCED` default `"false"`
     — App Check stays a non-blocker for the migration.

7. **Hosting site IDs are globally unique** and currently owned by the old project:
   `lumi-kakakids` (Flutter web), `lumi-dev-admin` (super-admin), `lumi-school-admin`
   (school admin). Plan assumes **new site IDs** (`-au` suffix) to avoid a delete-then-pray
   race on name reclamation. That changes the school portal URL → update `STAFF_PORTAL_URL`.

8. **Stored Storage URLs in Firestore will break:**
   - School logos: V4 **signed URLs** signed by the old project's service account
     (`admin/src/app/api/schools/[schoolId]/logo/route.ts:59-71`, expiry 2099). Signed URLs
     are bucket+key-specific → invalid after migration. Fix: re-upload logos via the admin
     portal (test data: trivial) or re-sign with the new SA.
   - `community_books` cover URLs: token-based download URLs containing the old bucket name.
     `gcloud storage cp` preserves the `firebaseStorageDownloadTokens` metadata, so a simple
     string replace of the bucket name inside stored URLs revives them (Phase 4.4), or just
     re-run `scripts/migrate_llll_to_community.js`.
   - Comprehension audio stores **paths** not URLs (`readingLogs.comprehensionAudioPath`,
     `schools/{schoolId}/comprehension_audio/{logId}.m4a`) → works as-is after object copy.

9. **CI deploys the admin portal** (`.github/workflows/admin-deploy.yml`) and hardcodes:
   project ID, auth domain, storage bucket, sender ID (in the "Write admin/.env.production"
   step), `projectId: lumi-kakakids`, `target: admin`, and the GH secrets
   `FIREBASE_SERVICE_ACCOUNT_LUMI_KAKAKIDS`, `FIREBASE_SERVICE_ACCOUNT_KEY`,
   `NEXT_PUBLIC_FIREBASE_API_KEY`, `NEXT_PUBLIC_FIREBASE_APP_ID` (Phase 6.3).
   `admin-ci.yml` uses dummy values — no change.

10. **Out of scope / unaffected:** Cloudflare status worker (`.dart_define.json` →
    `lumistatus.aged-morning-985b.workers.dev`), SendGrid account + sender domain auth,
    Realtime Database (unused), Remote Config (unused), emulator-based tests
    (`functions/package.json` `test:rules*` use demo projects). The untracked
    `school-admin-web-minor-edits/` working copy contains stale duplicates of all configs —
    don't migrate it; reconcile or delete it before starting.

---

## Phase 1 — Create and provision the new project (Console, ~30 min)

1. **Create project** `lumi-ninc-au` at console.firebase.google.com.
   Disable Google Analytics or link as you prefer (app uses `firebase_analytics`; a new GA
   property is fine — no data worth carrying).
2. **Upgrade to Blaze immediately.** Functions, Secret Manager, Cloud Scheduler, and the
   hosting frameworks backend all require it. Link the same billing account; copy any budget
   alerts from the old project.
3. **Authentication** → Get started → enable **Email/Password** AND **Phone** providers.
   - Phone: re-add any **test phone numbers** configured in the old project (Sign-in method →
     Phone → "Phone numbers for testing" — Console-only config) so dev flows don't burn real
     SMS. On iOS, phone verification uses APNs silent push (needs the .p8 from step 6) with
     the reCAPTCHA URL-scheme fallback that Phase 2.2 updates in `Info.plist`.
   - Settings → Authorized domains: defaults are fine; the new `*.web.app` /
     `*.firebaseapp.com` domains are added automatically as you create hosting sites.
   - Templates: if you customized password-reset / verification emails in the old project,
     re-apply them (Console-only config, not in the repo).
4. **Firestore** → Create database → **Standard edition**, **`australia-southeast1`
   (Sydney)**, production mode. ✅ Done (2026-06-11).
   ⚠️ Location is immutable — this click is the entire point of the migration.
5. **Storage** → Get started → choose **`australia-southeast1`** for the default bucket
   (co-located with Firestore).
   New bucket will be `lumi-ninc-au.firebasestorage.app`.
6. **Cloud Messaging (iOS)**: Project settings → Cloud Messaging → Apple app configuration →
   upload your **APNs auth key (.p8)** with Key ID + Team ID. (Same .p8 file as the old
   project — APNs keys are Apple-side and project-independent. Do this after Phase 2.3
   registers the iOS app, otherwise there's no Apple app to attach it to.)
7. Don't pre-enable other APIs — `firebase deploy` enables Cloud Functions, Cloud Run,
   Eventarc, Artifact Registry, Secret Manager, and Cloud Scheduler on first use (it prompts).

---

## Phase 2 — Code changes (branch: `feat/au-project-migration`)

Do all of this on a branch. **Do not deploy this branch to the old project** — the region
change would try to recreate every function.

### 2.1 Pin functions to australia-southeast1

Create `functions/src/global_options.ts`:

```ts
import { setGlobalOptions } from "firebase-functions/v2";

// Firestore lives in australia-southeast1 (Sydney); v2 Firestore triggers must
// co-locate with the database, and everything else belongs there too.
setGlobalOptions({ region: "australia-southeast1" });
```

Then in `functions/src/index.ts`, add **as the very first import, above all others**:

```ts
import "./global_options";
```

⚠️ Ordering matters: `impersonation.ts`, `parent_linking.ts`, `comprehension_retention.ts`,
and `library_counts.ts` define their functions at module load. With CommonJS emission, imports
execute in declaration order — `global_options` must be first or those modules register with
the default region before `setGlobalOptions` runs.

The 8 scheduled functions inherit the global region — Cloud Scheduler supports
`australia-southeast1`, so no per-function overrides are needed.
`cleanupComprehensionAudio` already sets `timeZone: "Australia/Sydney"`
(`comprehension_retention.ts:164`) — unchanged.

### 2.2 Flutter client

1. **Re-run flutterfire** (after Phase 2.3 — needs the project to exist):
   ```bash
   flutterfire configure --project=lumi-ninc-au --platforms=android,ios,web
   ```
   Regenerates `lib/firebase_options.dart`, `android/app/google-services.json`,
   `ios/Runner/GoogleService-Info.plist`, and updates the `flutter` block in `firebase.json`.
   Bundle IDs stay the same (`com.lumi.lumiReadingTracker` iOS,
   `com.lumi.lumi_reading_tracker` Android) — flutterfire registers them as new apps in the
   new project.
2. **Functions region** — add a shared constant (e.g. in a small
   `lib/core/services/functions_instance.dart` or wherever fits your layering):
   ```dart
   const kFunctionsRegion = 'australia-southeast1';
   final lumiFunctions = FirebaseFunctions.instanceFor(region: kFunctionsRegion);
   ```
   and replace `FirebaseFunctions.instance` in:
   - `lib/services/impersonation_service.dart` (6 callables)
   - `lib/services/staff_notification_service.dart` (`createNotificationCampaign`)
   - `lib/services/parent_linking_service.dart` (`linkParentToStudent`, `unlinkParentFromStudent`)
   - `lib/services/comprehension_audio_service.dart` (`deleteComprehensionAudio`)
3. **`ios/Runner/Info.plist:38`** — replace the URL scheme
   `app-1-432054475733-ios-3e84170b90653be9963b5c` with the new iOS GOOGLE_APP_ID
   (take the new `appId` from `firebase_options.dart` iOS section, replace `:` with `-`,
   prefix `app-`).
4. **`web/index.html:31,34,38,41`** — og:/twitter: meta URLs `https://lumi-kakakids.web.app`
   → new default hosting site URL.

### 2.3 Register the web apps & create hosting sites (CLI)

```bash
firebase use --add lumi-ninc-au   # alias e.g. "au"
firebase hosting:sites:create lumi-ninc-au      # Flutter web
firebase hosting:sites:create lumi-dev-admin-au     # super-admin portal
firebase hosting:sites:create lumi-school-admin-au  # school admin portal
```

flutterfire creates the web app for the Flutter app; `admin/` and `school-admin-web/` share
that web app's config (they only need apiKey/appId/etc., same pattern as today where all three
use the `...web:503da019d86e3de8963b5c` app).

### 2.4 `.firebaserc` and `firebase.json`

`.firebaserc` → replace wholesale:

```json
{
  "projects": { "default": "lumi-ninc-au" },
  "targets": {
    "lumi-ninc-au": {
      "hosting": {
        "admin":   ["lumi-dev-admin-au"],
        "default": ["lumi-ninc-au"],
        "school":  ["lumi-school-admin-au"]
      }
    }
  },
  "etags": {}
}
```

`firebase.json` → both `frameworksBackend.region` values (lines 36 and 46):
`"us-central1"` → `"australia-southeast1"`. (The SSR backends are v2 functions, so AU is a
valid region; if the webframeworks experiment rejects it, the fallback is leaving SSR in
`us-central1` — that only affects portal SSR latency, not data residency. Verify at first
deploy.)
The `flutter` block is rewritten by flutterfire — don't hand-edit.

### 2.5 school-admin-web

- `src/lib/firebase/admin.ts:16` — fallback `initializeApp({ projectId: 'lumi-kakakids' })`
  → `'lumi-ninc-au'`.
- `src/lib/firebase/client.ts` — `getFunctions(app)` → `getFunctions(app, 'australia-southeast1')`.
- `next.config.js:14` — image hostname `lumi-kakakids.firebasestorage.app`
  → `lumi-ninc-au.firebasestorage.app`.
- `.env.local` + `.env.production` — all six `NEXT_PUBLIC_FIREBASE_*` values from the new
  web app config (Console → Project settings → Your apps → web app). Keep `SESSION_SECRET`.
  `.env.local` also has `FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH` → point at the new SA key
  (Phase 3).

### 2.6 admin (super-admin portal)

- `.env.local` — new values for the six `NEXT_PUBLIC_FIREBASE_*` keys, new base64
  `FIREBASE_SERVICE_ACCOUNT_KEY` (Phase 3), and add `FUNCTIONS_REGION=australia-southeast1`
  (consumed at `src/lib/callDeployedCallable.ts:7`). Keep `SESSION_COOKIE_MAX_AGE`.
- `.env.example` — update placeholder project values to match, add `FUNCTIONS_REGION`.
- Optional hardening: change the `callDeployedCallable.ts:7` default from `"us-central1"` to
  `"australia-southeast1"` so a missing env var can't silently point at the wrong region.

### 2.7 scripts

- `scripts/migrate_llll_to_community.js:38` — `projectId: "lumi-kakakids"` → new ID.
- The Dart admin scripts (`seed_healthcheck.dart`, `setup_test_school_code.dart`,
  `backfill_*.dart`) authenticate via `GOOGLE_APPLICATION_CREDENTIALS` — no code change,
  just the new key file when running them.

---

## Phase 3 — Service accounts & keys (~15 min)

1. Console (new project) → Project settings → Service accounts → **Generate new private key**
   → save as e.g. `~/keys/lumi-ninc-au-admin.json` (outside the repo!).
2. Base64 for the admin portal:
   ```bash
   base64 -i ~/keys/lumi-ninc-au-admin.json | tr -d '\n' | pbcopy
   ```
   → paste into `admin/.env.local` `FIREBASE_SERVICE_ACCOUNT_KEY` (and later the GH secret).
3. `school-admin-web/.env.local` → `FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=~/keys/lumi-ninc-au-admin.json`
   (or however it's pathed today).
4. For local gcloud work below: `gcloud auth login` with the account that owns both projects.

---

## Phase 4 — Data migration

Order matters: **Auth users → Firestore → Storage → URL fix-ups**, all BEFORE functions are
deployed (managed imports don't fire triggers, but a clean sequence removes doubt).

### 4.1 Auth users (UIDs + password hashes preserved)

```bash
# export from old project
firebase auth:export users.json --format=json --project lumi-kakakids
```

Get the password hash parameters: old project Console → Authentication → Users → ⋮ (three-dot
menu) → **Password hash parameters**. You'll get scrypt `base64_signer_key`,
`base64_salt_separator`, `rounds`, `mem_cost`.

```bash
firebase auth:import users.json \
  --hash-algo=scrypt \
  --hash-key="<base64_signer_key>" \
  --salt-separator="<base64_salt_separator>" \
  --rounds=8 --mem-cost=14 \
  --project lumi-ninc-au
```

(Use the actual rounds/mem-cost values from the dialog.) This preserves UIDs, emails,
verification flags, and custom claims (`customAttributes`) — everyone keeps their password.
Delete `users.json` afterwards.

### 4.2 Firestore (managed export/import — the Google-documented region-move path)

```bash
# 1. Export bucket in the OLD project, co-located with the old database (us-central1)
gcloud storage buckets create gs://lumi-kakakids-migration \
  --project=lumi-kakakids --location=us-central1

# 2. Export everything
gcloud firestore export gs://lumi-kakakids-migration/firestore-export \
  --project=lumi-kakakids

# 3. Grant the NEW project's Firestore service agent read access
#    (find NEW_PROJECT_NUMBER: gcloud projects describe lumi-ninc-au --format='value(projectNumber)')
gcloud storage buckets add-iam-policy-binding gs://lumi-kakakids-migration \
  --member="serviceAccount:service-<NEW_PROJECT_NUMBER>@gcp-sa-firestore.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# 4. Import into the new (australia-southeast1) database
gcloud firestore import gs://lumi-kakakids-migration/firestore-export \
  --project=lumi-ninc-au
```

This carries all 18 top-level collections (incl. `superAdmins`, `devAccessEmails`,
`platformConfig`, `community_books`, `userSchoolIndex`) and every school-scoped subcollection
(incl. `staffCredentials`, `readingLogs/comments`) with timestamps intact. Composite indexes
are NOT part of exports — deployed separately (Phase 5.3).

### 4.3 Storage objects

```bash
gcloud storage cp -r "gs://lumi-kakakids.firebasestorage.app/*" \
  "gs://lumi-ninc-au.firebasestorage.app/"
```

Copies `community_books/covers/*`, `schools/{id}/comprehension_audio/*`,
`schools/{id}/logo.*` with custom metadata (incl. `firebaseStorageDownloadTokens`) preserved.

### 4.4 Stored-URL fix-ups (test-data scale → do the cheap version)

- **`community_books.*` cover URLs** (token URLs embedding the old bucket): either
  re-run `node scripts/migrate_llll_to_community.js` (idempotent, merge semantics) against the
  new project, or run a one-off string replace of
  `lumi-kakakids.firebasestorage.app` → `lumi-ninc-au.firebasestorage.app` in the stored
  URLs (tokens survive the copy, so the rewritten URLs work).
- **School logos** (signed URLs — cryptographically dead): re-upload each test school's logo
  through the admin portal once it's running. For a handful of test schools this beats
  scripting re-signing.

### 4.5 Re-seed checks

```bash
# health probe doc (_meta/healthcheck)
GOOGLE_APPLICATION_CREDENTIALS=~/keys/lumi-ninc-au-admin.json dart run scripts/seed_healthcheck.dart
```

`superAdmins` came across in the Firestore import (UIDs preserved by 4.1), so
`seed_super_admin.js` is only needed if you add people. Same for
`backfill_user_school_index.dart` — the index docs were imported; run it only as a
verification no-op if paranoid.

---

## Phase 5 — Deploy backend (new project)

All from the repo root on the migration branch, with `firebase use lumi-ninc-au` active.

### 5.1 Secrets

```bash
firebase functions:secrets:set SENDGRID_API_KEY      --project lumi-ninc-au
firebase functions:secrets:set SENDGRID_SENDER_EMAIL --project lumi-ninc-au
```

(Same SendGrid key/sender as before — SendGrid is account-level, nothing changes there.)

### 5.2 Functions runtime env

Create `functions/.env` (firebase-tools loads it at deploy):

```
STAFF_PORTAL_URL=https://lumi-school-admin-au.web.app
```

Leave `IMPERSONATION_APP_CHECK_ENFORCED` / `PARENT_LINKING_APP_CHECK_ENFORCED` /
`SUPER_ADMIN_UIDS` unset — defaults are correct (App Check off, superAdmins collection is the
real gate).

### 5.3 Rules, indexes, functions

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage --project lumi-ninc-au
# 41 composite indexes start building — kick this off early, building takes a while
firebase deploy --only functions --project lumi-ninc-au
```

First functions deploy will prompt to enable APIs (Cloud Run, Eventarc, Artifact Registry,
Secret Manager, Cloud Scheduler) — accept. Verify the regions:

```bash
firebase functions:list --project lumi-ninc-au
```

Expected: every function in `australia-southeast1`. If anything shows `us-central1`,
the `global_options` import-order fix (2.1) didn't take.

### 5.4 Hosting

```bash
# Flutter web
./scripts/flutter-build.sh web
firebase deploy --only hosting:default --project lumi-ninc-au

# Portals (webframeworks experiment, same as CI does)
export FIREBASE_CLI_EXPERIMENTS=webframeworks
firebase deploy --only hosting:school --project lumi-ninc-au
firebase deploy --only hosting:admin  --project lumi-ninc-au
```

Note the admin portal normally deploys via GitHub Actions on merge to main (Phase 6.3) —
the manual deploy here is for pre-merge verification. The admin/school SSR deploys need the
env files from 2.5/2.6 in place because Next inlines `NEXT_PUBLIC_*` at build time.

---

## Phase 6 — Verification, CI, cutover

### 6.1 Smoke test matrix

| Check | How |
|---|---|
| Auth + UID continuity | Log into school admin portal with an existing test teacher (old password must work) |
| Phone auth | Run the parent phone-primary registration flow on a real device (use a console test number first, then one real SMS) |
| Super-admin gate | Log into `lumi-dev-admin-au.web.app` — `superAdmins/{uid}` check passes |
| Callable region | Trigger `createNotificationCampaign` or parent linking from the app — no NOT_FOUND |
| Firestore triggers | Create a reading log → `aggregateStudentStats` / `updateClassStats` fire (check `firebase functions:log`) |
| Scheduled fns | `gcloud scheduler jobs list --project lumi-ninc-au --location=australia-southeast1` shows 8 jobs |
| Emails | Trigger a staff onboarding email → arrives, portal link points at `lumi-school-admin-au.web.app` |
| Push | Real device: log in as parent, check FCM token written to parent doc, send a test campaign |
| Comprehension audio | Record → upload to new bucket → playback → `deleteComprehensionAudio` callable |
| Book covers | Library screens render community book covers (4.4 fix-up worked) |
| Impersonation | Start/end a dev impersonation session from the admin portal (exercises `callDeployedCallable` + `FUNCTIONS_REGION`) |

### 6.2 iOS device test

The widget-config bug aside, test push + audio on a **real device** (Simulator drops APNs).
`aps-environment` is `development` — debug builds use APNs sandbox; the same .p8 covers both.

### 6.3 GitHub Actions (`.github/workflows/admin-deploy.yml`)

1. Mint a deploy SA for the new project — easiest:
   `firebase init hosting:github` against the new project (it creates the SA with the right
   roles and writes the secret), then discard the workflow files it generates and delete any
   extra secret names it created beyond the one you keep.
2. Update repo secrets: new `FIREBASE_SERVICE_ACCOUNT_LUMI_NINC_AU` (deploy SA JSON),
   `FIREBASE_SERVICE_ACCOUNT_KEY` (base64 admin SA from Phase 3),
   `NEXT_PUBLIC_FIREBASE_API_KEY`, `NEXT_PUBLIC_FIREBASE_APP_ID` (new web app values).
3. Edit the workflow: the hardcoded `.env.production` block (auth domain, project ID, storage
   bucket, sender ID), `firebaseServiceAccount:` secret name, `projectId: lumi-ninc-au`.
   `target: admin` stays (it's the target alias, resolved via `.firebaserc`).

### 6.4 Merge

PR the `feat/au-project-migration` branch → squash-merge. From merge onward, CI deploys the
admin portal to the new project. Local `.claude/settings.local.json` has `lumi-kakakids` in
allowlist entries — update at leisure.

---

## Phase 7 — Decommission old project

Only after a few days of green usage on the new project:

1. Old project Console → Project settings → **Delete project** (30-day soft delete — your
   rollback window).
2. Delete the `gs://lumi-kakakids-migration` export bucket (it contains all user data —
   don't leave it lying around) and the exported `users.json` if not already shredded.
3. Revoke/delete old service account keys on disk
   (`FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH` target, old base64 blob in shell history/notes).
4. Optional: after deletion settles, the old hosting site IDs (`lumi-kakakids`,
   `lumi-dev-admin`, `lumi-school-admin`) *may* become reclaimable if you ever want the
   shorter URLs back — not guaranteed.

---

## Deferred (post-migration, when you enable App Check for real)

Everything is env-gated off today, so none of this blocks the move:

- Register apps for **Play Integrity** (Android) / **App Attest + DeviceCheck** (iOS) in the
  new project's App Check console; new debug tokens for dev devices.
- New **reCAPTCHA Enterprise** key in the new GCP project for web
  (`LUMI_APP_CHECK_RECAPTCHA_KEY` dart-define + `NEXT_PUBLIC_APP_CHECK_*` in school-admin-web).
- Then flip `LUMI_APP_CHECK_ENABLED` / `NEXT_PUBLIC_APP_CHECK_ENABLED` /
  `*_APP_CHECK_ENFORCED` in that order.
