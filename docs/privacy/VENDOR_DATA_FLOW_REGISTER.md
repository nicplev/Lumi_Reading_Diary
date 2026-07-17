# Lumi Vendor and Data-Flow Register

**Version:** 1.0 · **Reviewed:** 17 July 2026
**Owner:** Privacy lead (approval pending)

This register distinguishes a configured service from an approved disclosure.
`Blocked` means no production personal information may be sent until every
listed gate is closed.

## Active vendors and platforms

| Provider / service | Data and purpose | Known processing/storage | Child data? | Controls | Evidence still required | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Google Cloud Firestore | School, child, adult, roster, reading and messaging records | `(default)` database in `australia-southeast1` | Yes | Rules, tenant/class/family binding, PITR, deletion protection, dedicated runtime IAM | DPA/subprocessor and overseas support-access review | Conditional |
| Google Cloud Storage | Optional validated audio, school logos and book covers | User-content buckets verified in `australia-southeast1`; legacy managed code-source bucket exists in US | Yes for voice | Storage Rules, create-only pending path, isolated decoder, signed URLs, retention/deletion | DPA, support/access countries, deletion-from-backup statement | Conditional; voice authority open |
| Cloud Functions / Cloud Run / Eventarc / Scheduler | Server authorisation, aggregation, notifications, deletion and media validation | All 77 live application workloads and all 17 Scheduler jobs verified in `australia-southeast1` | Yes transiently | Dedicated keyless identities, least privilege, alerting, Scheduler drift audit | DPA/support-access review | Conditional |
| Cloud Logging | Application/security events and required Cloud audit trail | Future ordinary logs in `australia-southeast1`; pre-change ordinary logs and unavoidable `_Required` audit logs are global | Direct account/school/child/record identifiers and raw exceptions are prohibited in application payloads; admin identity can appear in required audit logs | AU sink, 30-day ordinary retention, 400-day platform-locked required retention, source-wide payload-minimisation regression | DPA/support-access and required-global-log APP 8 review | Conditional |
| Secret Manager | SendGrid credentials and portal session secret | Three active payloads use one user-managed replica in `australia-southeast1`; the former automatically replicated resources were deleted on 17 July 2026 | No child content intended | Narrow secret-level access; dedicated runtime identities; no client exposure; live consumers verified before old-resource deletion | Keep secrets free of personal data and re-audit replication/IAM on each new secret | Controlled technical location |
| Firebase Authentication / Identity Platform | Adult UID, email/phone, factors, sign-in and recovery | Firebase documents Authentication as US-only | Adult data | MFA support, rate limits, 500/day verification cap, abuse alerts, server membership checks | Contract, US processing/support access, retention and APP 8 approval | Conditional |
| Firebase Cloud Messaging + Apple Push Notification service | Device token and adult-facing notification delivery | Global platform services | May reveal limited reading context in a notification | Token pruning, shared-token suppression, permission controls | Final payload inventory, DPA/platform terms and overseas assessment | Conditional |
| Firebase App Check | App/device attestation tokens | Google service; global support may apply | No intended content data | Release build guard, replay-resistant limited-use tokens | Store-signed evidence and final enforcement plan | Conditional |
| Firebase Analytics | Pseudonymous optional usage events | May process outside Australia | No child/account identifiers intended | Off by default, adult opt-in, no Lumi UID/detailed reading fields, withdrawal capture | Final store questionnaire and Google retention configuration | Optional / conditional |
| Firebase Crashlytics | Optional crash stack, app/device diagnostics | May process outside Australia | Child content prohibited | Off by default, adult opt-in, no Lumi UID, queued-report deletion | Synthetic opted-in crash inspection and final questionnaire | Optional / conditional |
| Twilio SendGrid | Adult onboarding, school/staff service and operational email | Overseas service; public subprocessor evidence records SendGrid infrastructure in North America/EU and Twilio, Inc. in the US | Avoid child data; templates may contain adult/school data and temporary credentials | API key in AU-replicated Secret Manager; narrow runtime-only access; server-only sends | Retain Lumi account acceptance/contracting-entity evidence outside Git; counsel review of DPA, support access, retention and APP 8 treatment | Conditional / legal review open |
| Google Books API | ISBN/title search and public book metadata | Google public API; may process globally | No identity data intended | Request includes only ISBN/title; API-key target restriction; manual entry fallback | Confirm privacy terms and remove/replace obsolete key if unnecessary | Low risk |
| Open Library / Internet Archive | ISBN/title search, description and cover images | Overseas public service | No identity data intended | Request includes only ISBN/title/work ID; manual entry fallback | Record current privacy/retention terms | Low risk |
| Apple App Store / Google Play | Distribution, purchase/account and store diagnostics governed by platform | Platform-defined global processing | Adult/device data; store age context may apply | No ad SDK; privacy disclosures prepared | Organisation enrolment, final questionnaires, agreements and signed artifact evidence | Store blocked |
| Support mailbox provider | Privacy, access, correction, deletion and incident reports | Not recorded | Potentially yes | Stable `support@lumi-reading.com` address and public support page; owner confirmed daily monitoring and MFA on 17 July 2026 | Name provider, record/restrict delegates and define mailbox retention | Open release action |

## Configured but prohibited for production personal data

| Provider / service | Proposed purpose | Current control | Approval gates | Status |
| --- | --- | --- | --- | --- |
| Google Cloud Speech-to-Text | Transcribe optional comprehension audio | API enabled and AU model evaluated; production AI kill switch off; no connected provider pipeline | School authority, PIA update, DPA/location/support analysis, retention, accuracy review, cost cap | Blocked |
| Anthropic | Proposed transcript comprehension evaluation | No secret, dependency or production call; kill switch off | DPA, APP 8 assessment, subprocessors/countries, no-training/ZDR evidence, retention/deletion, spend cap, approved PIA | Blocked |
| OpenAI / other LLMs | Evaluation alternatives mentioned in cost research only | No production integration or secret | Full new-vendor review and approved PIA | Not approved |
| Stripe | Future direct-sales design only | No dependency, secret, webhook or data flow | Payment threat model, contract/DPA, PCI scope, webhook controls and PIA update | Not implemented |

## Data-flow rules

1. Never put a child name, school, note, recording, transcript, access token,
   email or UID into logs, Analytics, Crashlytics, public book APIs or support
   screenshots unless the incident lead has approved a necessary redacted copy.
2. A Firebase resource's Australian region does not prove that Authentication,
   Analytics, Crashlytics, FCM, support or subprocessors stay in Australia.
3. No new SDK, API, subprocessors or vendor secret may be added until this
   register records purpose, data, location, retention, deletion, contract,
   security owner and APP 8 decision.
4. SendGrid email templates must minimise personal information and must not
   place child data in subject lines. Temporary credentials must be one-time or
   forced to rotate at first use.
5. Voice or transcript data must never leave the approved flow merely because
   a provider offers an API or an Australian endpoint.

## Vendor review checklist

For every conditional or proposed vendor, retain dated evidence for:

- [ ] Contract/DPA and service-specific terms
- [ ] Subprocessor list and accessible countries
- [ ] Primary storage and processing locations
- [ ] Overseas support/admin access
- [ ] Encryption and tenant isolation
- [ ] Retention defaults and configurable limits
- [ ] Deletion, backup and legal-hold behaviour
- [ ] Training/secondary-use and advertising terms
- [ ] Breach notification commitment and contact
- [ ] Export/portability and exit plan
- [ ] APP 8 assessment and approving person

The OAIC's current APP 8 guidance is the legal review starting point:
https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-8-app-8-cross-border-disclosure-of-personal-information

## Evidence captured 17 July 2026

- [x] Official current Google Cloud DPA, subprocessors and service-specific
  terms captured with hashes.
- [x] Official Firebase data-processing/security terms and Terms of Service
  captured with hashes.
- [x] Official Twilio DPA, subprocessors, security overview and SendGrid
  retention/deletion guidance captured with hashes.
- [x] Official OAIC APP 8 Guidelines v1.3 PDF captured with a hash.
- [ ] Retain private account-specific proof of the Lumi contracting entity,
  billing account and accepted versions of online terms outside Git.
- [ ] Have Australian privacy counsel approve the resulting APP 8 treatment.

Public evidence and its provenance are in
`docs/privacy/vendor-evidence/2026-07-17/README.md`. Public terms alone do not
prove which Lumi entity accepted them and are not legal approval.
