# Lumi Australian resource-location audit

**Audit date:** 17 July 2026
**Project:** `lumi-ninc-au` (`3795320704`)
**Scope:** Live Firebase/Google Cloud resources, operational logs, deployment
artifacts and known external service boundaries.

## TL;DR

Lumi's primary child-content plane is in Sydney: the production Firestore
database, user-content Storage buckets and all 77 live Functions/Cloud Run
services are in `australia-southeast1`. Future ordinary application logs now
route to an Australian log bucket with 30-day retention.

This does **not** mean all Lumi data stays in Australia. Firebase
Authentication is officially US-only. FCM, App Check, Analytics and
Crashlytics use global infrastructure. Google's unavoidable `_Required`
audit-log bucket is global. SendGrid and the mobile-store providers are also
cross-border services. The three application secrets were migrated during this
audit to Sydney-only payload replicas. The remaining exceptions require the
contractual/APP 8 review already tracked in the vendor register.

## Live location inventory

| Resource | Observed location | Result / note |
| --- | --- | --- |
| Firestore `(default)` | `australia-southeast1` | Pass. Native mode, PITR and deletion protection are enabled. |
| Firebase user-content Storage | `AUSTRALIA-SOUTHEAST1` | Pass. The default Firebase bucket and current child/user-content buckets are in Sydney. |
| Cloud Functions / Cloud Run | `australia-southeast1` | Pass. All 77 live services are in Sydney: 74 Functions-runtime services, the isolated audio validator and the two portals. |
| Current Functions source bucket | `australia-southeast1` | Pass. All 77 current function definitions reference `gcf-v2-sources-3795320704-australia-southeast1`. |
| Cloud Scheduler | `australia-southeast1` | Pass. All 17 jobs are in Sydney. Schedule time zones vary only to express business time. |
| Ordinary Cloud Logging | `australia-southeast1` | Remediated during this audit. `_Default` now routes future included logs to `lumi-au-default`, retained for 30 days. |
| Required Cloud audit logs | `global` | Exception. Google does not allow `_Required` to be redirected; retention is locked at 400 days. |
| Old `_Default` logs | `global` | Transitional exception. Entries written before the routing change remain for their existing 30-day retention and then expire. |
| Secret Manager payloads | `australia-southeast1` | Remediated. `ADMIN_SESSION_SECRET_AU`, `SENDGRID_API_KEY_AU` and `SENDGRID_SENDER_EMAIL_AU` each have one user-managed Sydney replica. Six live consumers were cut over and verified before the former automatically replicated secret resources were deleted. No child content is intended in these values. |
| Firebase Authentication | United States | Cross-border exception. Adult email/phone/password, IP and user-agent data are processed by the US-only service. |
| FCM / App Check / Analytics / Crashlytics | global infrastructure | Cross-border exception. Analytics and Crashlytics remain adult opt-in and default-off; no child content or Lumi UID is intended. |
| Legacy managed Functions source bucket | `US-CENTRAL1` | Legacy code-only exception. `gcf-sources-3795320704-us-central1` contains old deployment archives and no live Function references it. Redacted inspection found only source/build files and public project/config identifiers, not a secret value or identified child record. Do not delete it blindly: it is Google-managed and carries `DO_NOT_DELETE_THE_BUCKET.md`. |
| Google Speech-to-Text evaluation | `australia-southeast1` | Technically regional, but production AI processing remains disabled pending school authority, PIA and vendor/APP 8 approval. |
| SendGrid | overseas/global | Cross-border exception. Minimise email content and complete contract, subprocessor, retention and support-access review before release. |

## Changes made during the audit

1. Created `lumi-au-default` in `australia-southeast1` with 30-day retention.
2. Redirected the project `_Default` sink, preserving Google's standard
   exclusion filter for logs already handled by `_Required`.
3. Wrote a synthetic, non-personal routing canary for verification.
4. Found 12 Scheduler jobs still authenticating as the App Engine default
   account after their Cloud Run invoker grants had moved to the dedicated
   runtime identity. Three jobs were actively returning HTTP 403.
5. Migrated all 17 jobs to
   `lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com`, verified the
   five-minute deletion and notification workers returned success and updated
   their heartbeats, then removed the final obsolete default-account Run
   Invoker binding.
6. Removed direct account, school, child, record, email and object-path
   identifiers plus raw exception payloads from routine Functions logs. A
   source-wide regression now rejects their reintroduction. The production
   rollout updated 75 Functions with zero errors; post-deploy traffic reached
   the Sydney bucket without an error or prohibited identifier field.
7. Created three new user-managed Secret Manager resources with a single
   `australia-southeast1` replica and payload access only for the relevant
   dedicated runtime identity. The keyless admin deploy identity has
   secret-level metadata viewer only so Firebase can validate that the named
   version exists; it cannot access the payload. Payload equality and the SendGrid credential's
   `mail.send` scope were checked without printing values. Five email Functions
   and the super-admin backend were deployed and verified `ACTIVE`; the live
   admin login returned HTTP 200 and no post-cutover error log was found. The
   three automatically replicated predecessor resources were then deleted.

## Privacy interpretation

- AU resource placement reduces risk but does not, by itself, prove no
  overseas disclosure or access.
- Firebase states that Authentication runs only from US data centres and keeps
  logged IP addresses for a few weeks; other authentication data remains until
  deletion and can take up to 180 days to leave live and backup systems.
- Firebase describes FCM, App Check, Crashlytics and several other products as
  global services. Product location must be assessed separately rather than
  inherited from Firestore.
- Secret Manager's former automatic-replication exception is closed for Lumi's
  three application secrets. Future secrets must use user-managed Sydney
  replication and must not contain personal information.
- Required Cloud audit logs remain global even after regionalising ordinary
  logs. Application logs now exclude direct user/school/record identifiers and
  raw exception payloads by implementation and regression test; names, email
  addresses, message bodies, recordings and transcripts remain prohibited.

## Remaining actions

- [ ] Obtain owner/privacy-counsel approval of the Firebase/Google contract,
      subprocessor and APP 8 assessment, including US Authentication.
- [~] Complete SendGrid processing-country, subprocessor, support-access,
      retention and deletion evidence. Public Twilio DPA/subprocessor/security/
      retention evidence is captured; account acceptance and counsel review
      remain.
- [x] Migrate the three non-child-content secrets to new AU
      user-managed-replication secrets and delete the old global resources.
- [ ] Let the old global `_Default` log data age out for 30 days; retain the
      global `_Required` exception in school-facing disclosures.
- [ ] Review the legacy US Functions source bucket with Google/Firebase support
      before applying lifecycle cleanup or deletion.
- [ ] Repeat the resource inventory and sink check at each production release
      that adds a Firebase/Google Cloud product or external processor.

## Evidence and primary references

Live evidence was collected with read-only `gcloud`/Firebase Admin inventory
commands, followed by the two explicitly recorded remediations above. No secret
payload, child content, raw log body, audio or transcript was printed or
retained.

- [Firebase product and resource locations](https://firebase.google.com/docs/projects/locations)
- [Firebase privacy, service data and processing locations](https://firebase.google.com/support/privacy)
- [Cloud Firestore locations](https://firebase.google.com/docs/firestore/locations)
- [Secret Manager replication policies](https://cloud.google.com/secret-manager/docs/choosing-replication)
- [Cloud Logging locations](https://cloud.google.com/logging/docs/region-support)
- [Regionalising Cloud Logging](https://cloud.google.com/logging/docs/regionalized-logs)
