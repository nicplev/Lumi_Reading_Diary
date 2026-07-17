# Lumi operations health audit

**Audit date:** 17 July 2026
**Project:** `lumi-ninc-au`

## TL;DR

Backups, monitoring, dedicated runtime identities and current application
services are healthy. This audit found and repaired a live Scheduler identity
drift that was returning 403 for three jobs. The high-frequency jobs recovered
under the dedicated runtime identity and wrote current successful heartbeats.

The remaining operational evidence is mostly human: confirm that the synthetic
security alert reached both inboxes, assign named incident roles, prove the
support mailbox is monitored and complete vendor/privacy approval.

## Checks

| Control | Evidence | Status |
| --- | --- | --- |
| Scheduled jobs | 17 enabled jobs in `australia-southeast1`; all now mint OIDC as the dedicated Functions runtime | Pass after remediation |
| Deletion worker | Post-fix Scheduler status cleared; `processPendingUserDeletions` heartbeat is current and `ok` | Pass |
| Notification dispatcher | Post-fix Scheduler status cleared; dispatcher heartbeat is current and `ok` | Pass |
| Scheduler least privilege | Each scheduled Cloud Run service grants Run Invoker to the runtime identity; obsolete App Engine default invoker removed | Pass |
| Functions/Run health | 75 Functions deployed with zero errors; all 77 live Sydney Functions/Run services subsequently reported active/ready with dedicated identities retained | Pass |
| Alerts | 13 enabled production policies, each attached to both security email channels; temporary delivery-test policy disabled | Technical pass; inbox receipt confirmation open |
| Firestore recovery | Seven-day PITR and deletion protection enabled; prior timed restore drill matched sampled production counts | Pass |
| Log residency | Future ordinary logs route to the 30-day Sydney bucket; required audit logs remain global | Pass with documented platform exception |
| Log minimisation | Routine application logs omit direct account/school/child/record identifiers and raw exceptions; a source-wide regression enforces this | Pass; Functions 139/139 |
| Account/student deletion | Idempotent server workflow, scheduled retries and minimal completion receipts are deployed | Pass; user's final destructive UI smoke test remains self-tracked |
| Recurring review | Weekly/manual security workflow and release privacy/security gate are checked in | Pass |

## Incident found and fixed

Recent deployments left Cloud Run with the intended invoker—the dedicated
Functions runtime—but 12 older Scheduler jobs still requested OIDC tokens as
the App Engine default account. `processPendingUserDeletions`,
`dispatchScheduledNotificationCampaigns` and `sendReadingReminders` had begun
returning HTTP 403. The repair migrated all 17 jobs to the dedicated identity.
The two five-minute workers then ran successfully and updated their Firestore
heartbeats. The hourly reminder job also ran successfully at 03:00 UTC with the
corrected identity. After the final deployment, the five-minute workers ran
again at 03:11 UTC with clear Scheduler status and fresh `ok` heartbeats.

No project-wide Run Invoker role was added. The final resource-scoped App Engine
default-account binding was removed after every job had migrated.

## Open human/external items

- [ ] Confirm the test security alert arrived at both `nic@lumi-reading.com`
      and `nicxplev@gmail.com`.
- [ ] Name the primary incident commander, privacy lead and technical backup.
- [ ] Confirm `support@lumi-reading.com` is MFA-protected and monitored, and
      record its provider, delegates and retention.
- [ ] Complete school emergency contacts and the Firebase/SendGrid APP 8 and
      contract evidence.
- [ ] Repeat signed IPA/AAB scans and store-attested App Check canaries after
      Apple/Google organisation enrolment.
