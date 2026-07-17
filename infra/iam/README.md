# Lumi least-privilege IAM

This directory is the source of truth for Lumi's project custom roles. Runtime
identities deliberately have no JSON keys and must not receive primitive
`Owner` or `Editor` roles.

## Runtime boundaries

| Workload | Service account | Project roles | Resource-scoped roles |
|---|---|---|---|
| Cloud Functions | `lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com` | Datastore User, App Check Token Verifier, Eventarc Event Receiver, Lumi Functions Auth Runtime, Lumi FCM Sender | Storage Object User on the Firebase bucket; Secret Accessor on the two SendGrid secrets; Lumi Service Account Signer on itself; Run Invoker on the isolated audio validator and each event-triggered Function service |
| School portal | `lumi-school-portal-runtime@lumi-ninc-au.iam.gserviceaccount.com` | Datastore User, Lumi Portal Auth Runtime | Storage Object User on the Firebase bucket |
| Super-admin portal | `lumi-super-admin-runtime@lumi-ninc-au.iam.gserviceaccount.com` | Datastore User, Lumi Portal Auth Runtime | Storage Object User on the Firebase bucket; Lumi Service Account Signer on itself |
| Audio validator | `lumi-audio-validator@lumi-ninc-au.iam.gserviceaccount.com` | None | Invoked only by the Functions runtime |

Two default identities retain narrow non-runtime duties. The Compute default
account is the configured Cloud Functions build worker and holds only Cloud
Build Builder. Firebase Scheduler continues to authenticate as the App Engine
default account, which has Run Invoker only on the 16 scheduled Function
services. Neither default identity has application-data, secret or project-wide
Editor access.

The signer role is self-bound: a portal/function may sign only as its own
identity. It contains `signBlob` for custom tokens/signed URLs and
`getOpenIdToken` for the Functions-to-validator authenticated call. Storage
access is bucket-bound. Secret access is secret-bound. The audio validator
continues to receive only base64 media bytes and has no data permissions.
Every newly deployed Eventarc-triggered Function must receive a service-level
`roles/run.invoker` binding for the Functions runtime. Do not replace these
named service bindings with project-wide Run Invoker. The production capability
canaries must exercise a new trigger before its migration is considered done.

## Migration and rollback

1. Create/update the custom roles from `roles/*.yaml` and create the three
   runtime service accounts with user-managed keys prohibited by practice.
2. Add the bindings above while the old default identities still exist.
3. Deploy a Firestore-only Function canary, then capability canaries for Auth,
   FCM, Storage/signing, secrets, scheduling and the validator invocation.
4. Move the portal backends one at a time and run authenticated read/write,
   user-management and upload/playback smoke tests.
5. Deploy all remaining Functions, confirm every Cloud Run revision uses the
   intended identity, then remove `Editor` from the App Engine and Compute
   default service accounts.
6. Reduce the GitHub deploy identity after runtime migration is stable.

Rollback does not require restoring `Editor`: direct a failed service/revision
back to its previous runtime identity or previous healthy Cloud Run revision,
then diagnose the missing narrow permission. Preserve old revisions until all
capability checks pass.
