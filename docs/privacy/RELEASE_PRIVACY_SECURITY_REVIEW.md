# Release Privacy and Security Review Gate

**Owner:** Release approver · **Cadence:** every relevant pull request and
release; full review quarterly during beta.

## When this gate is mandatory

Complete and link this review whenever a change touches:

- authentication, sessions, roles, membership, tenancy or impersonation;
- Firestore/Storage Rules, schemas, indexes, queries or listeners;
- child, parent, school or staff personal information;
- audio, camera, photos, transcripts, AI or automated decisions;
- Analytics, Crashlytics, notifications, logging or support tooling;
- a vendor, SDK, API, secret, subprocessor or processing location;
- retention, deletion, export, backup or recovery;
- payments, entitlements or public abuse-sensitive endpoints.

## Pull-request gate

- [ ] State what personal data and principals the change affects.
- [ ] Describe the expected school → class → child → record/object binding.
- [ ] Add positive and negative tests, including cross-tenant denial.
- [ ] Validate every accepted write field/type/range and lock system fields.
- [ ] Check subcollections and Storage separately; inspect all overlapping
  Rules matches because any matching `allow` grants access.
- [ ] Confirm queries are scope-bound, limited/paginated or intentionally
  bounded by a short date window; explain listener disposal.
- [ ] Confirm no secret, Admin credential or billable unrestricted key enters a
  client, build artifact, log or Remote Config.
- [ ] Identify new collection/use/disclosure and update the PIA, vendor register,
  privacy notice and store labels where relevant.
- [ ] Define retention/deletion for new data and add it to both account and
  student deletion inventories.
- [ ] Verify App Check/auth/rate limits on abuse-sensitive endpoints.
- [ ] Record deployment, rollback, monitoring and production canary evidence.

## Release evidence

- [ ] Functions/unit tests pass.
- [ ] Firestore and Storage Rules emulator suites pass.
- [ ] Flutter analysis and focused tests pass.
- [ ] Portal typecheck/build/tests pass where changed.
- [ ] Production dependency audits have no accepted critical/high finding; any
  exception has owner, rationale and deadline.
- [ ] Gitleaks scans commits and final artifacts.
- [ ] Reviewed rules/config match live deployment hashes.
- [ ] Physical supported-device negative/error-path smoke tests are recorded.
- [ ] Store-signed App Check/API-key identity is positive-tested when available.
- [ ] Alerts/dashboards and budget thresholds fit the expected new load.
- [ ] Final privacy questionnaires match actual runtime SDK traffic.

## Recurring schedule

| Review | Cadence | Evidence |
| --- | --- | --- |
| Automated Functions/Rules/dependency review | Weekly and on demand | `.github/workflows/security-review.yml` |
| IAM keys/roles and deploy WIF | Monthly and after deployment changes | IAM export + capability canaries |
| Vendor/subprocessor/APP 8 register | Quarterly and before new vendor use | Dated register approval |
| Retention/deletion sample | Monthly during beta | Synthetic job/object evidence |
| PIA | Quarterly and every high-privacy-risk change | Signed assessment version |
| Breach tabletop | Six-monthly and after material incident | Scenario/action record |
| Store labels/SDK traffic | Every signed release with SDK/data change | Packet endpoint summary + questionnaires |
| Alert delivery | Quarterly | Synthetic incident receipt in both inboxes |

An unchecked mandatory item blocks release unless the named privacy/security
approver records a time-limited exception. Store-enrolment blockers may defer
only store-specific evidence; they do not waive local, backend or documentary
controls.
