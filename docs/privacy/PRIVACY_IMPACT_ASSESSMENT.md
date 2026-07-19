# Lumi Privacy Impact Assessment

**Version:** 1.0 working assessment
**Assessment date:** 17 July 2026
**Owner:** Lumi founder / privacy lead (approval pending)
**Scope:** Flutter parent and teacher apps, school portal, super-admin portal,
Firebase/GCP production services, comprehension recording, optional diagnostics,
support and the proposed AI comprehension evaluation.
**Decision:** Conditional technical go for the core reading diary; no-go for
provider-connected AI processing and no broad school launch until the open
high-risk actions below have an accountable owner and evidence.

This is an operational privacy assessment, not legal advice. It follows the
OAIC's ten-step PIA process and must be reviewed by Australian privacy counsel
before Lumi relies on a legal conclusion.

## 1. Threshold assessment

A PIA is required. Lumi handles identifiable information about children,
parents, carers, teachers and schools, including educational activity,
free-text messages and optional voice recordings. A compromise or incorrect
tenant boundary could expose children across families or schools.

The OAIC recommends a PIA for projects involving personal information and
treats it as an ongoing process, not a one-time document:

- https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/privacy-impact-assessments/10-steps-to-undertaking-a-privacy-impact-assessment
- https://education.oaic.gov.au/elearning/pia/topic1.html

## 2. Purpose and necessity

| Information | Purpose | Strictly necessary? | Default / minimisation |
| --- | --- | --- | --- |
| Child name, class and school | Show the correct roster and bind access | Yes for the school service | School-scoped; no public directory |
| Reading date, minutes, title and completion | Reading diary and teacher progress view | Yes, except optional notes/feelings | Required fields are narrow; optional fields may be omitted |
| Parent/teacher identity and contact | Authentication, authority, recovery and service messages | Yes | Role comes from server-owned membership, not client claims |
| Parent–child and teacher–class links | Authorisation | Yes | Authoritative school records; no client self-grant |
| Comments | Optional parent–teacher communication | No | Per-school feature switch; access follows the parent log and class |
| Comprehension voice recording | Optional teacher review | No | Off by default per school; explicit parent action; separate retention |
| Product analytics | Improve product use | No | Adult opt-in, off by default, no Lumi UID or detailed reading attributes |
| Crash reports | Diagnose failures | No | Adult opt-in, off by default, no Lumi UID attached |
| ISBN/title sent to public book APIs | Book metadata | Helpful but replaceable by manual entry | No school, account or child identifier sent |
| AI transcript/evaluation | Proposed comprehension feedback | No | Production kill switch off; no provider secret or connected pipeline |

## 3. Information flows

The detailed register is `VENDOR_DATA_FLOW_REGISTER.md`. The main paths are:

1. An adult authenticates through Firebase Authentication, which Firebase
   documents as a US-only processing service.
2. The app reads and writes school-scoped data in Firestore under Security
   Rules that bind the account to the school, class, child and record.
3. Optional audio uploads to a create-only pending Storage path. An isolated
   AU Cloud Run worker decodes and canonicalises bytes without receiving child,
   school, log or account identifiers. The privileged Function publishes the
   validated object and server receipt.
4. Push notification tokens and adult notification content flow through FCM
   and the device platform. Transactional adult email flows through SendGrid.
5. Optional Analytics and Crashlytics traffic is disabled until an adult opts
   in on that device.
6. ISBN/title-only book lookups go directly to Google Books or Open Library.
7. AI provider processing is prohibited until a separate approved PIA update,
   contract, APP 8 assessment, retention decision and spend controls exist.
8. Future ordinary application/security logs are retained for 30 days in an
   Australian Cloud Logging bucket. Google's required audit logs and ordinary
   logs written before 17 July remain global platform exceptions.

## 4. Current controls

- Firestore and Storage Rules have explicit cross-school, cross-class and
  cross-family negative tests; subcollections do not rely on inheritance.
- Roles and system fields are server-owned. Dedicated keyless runtime service
  accounts replaced default-account Editor access.
- App Check is integrated and release builds fail closed if it is omitted, but
  managed-service enforcement awaits store-signed attestation evidence.
- Analytics and Crashlytics are independently off by default and adult
  controlled. Physical iPhone traffic evidence confirmed withdrawal.
- Voice is off by default per school. On first opt-in, the portal requires a
  school admin to confirm authority and family notice/opt-out responsibility
  and choose 30, 90 or 365-day retention. Versioned evidence is written by
  the server; Firestore/Storage clients cannot forge it, and uploads fail closed
  without current evidence. The AI pipeline remains off.
- Account and student deletion are idempotent server jobs; pending audio is
  removed after 24 hours and deletion receipts after 90 days.
- Firestore has seven-day point-in-time recovery and deletion protection.
- Thirteen production anomaly policies, a project budget and a security/cost
  dashboard are live.
- Routine Functions logs omit direct account, school, child, record, email and
  object-path identifiers and use bounded error codes instead of raw exception
  payloads. A source-wide test rejects regressions.
- Firestore, user-content Storage, all live application workloads and future
  ordinary logs are in `australia-southeast1`; the documented US/global
  service exceptions are tracked in the vendor register and
  `docs/security/AU_RESOURCE_LOCATION_AUDIT_2026-07-17.md`.
- Public privacy, terms and support pages return HTTP 200.

## 5. Privacy risk register

Likelihood and impact are rated Low / Medium / High after current controls.

| ID | Risk | Likelihood | Impact | Required treatment | Status |
| --- | --- | --- | --- | --- | --- |
| P-01 | Teacher/parent can access another class, family or school | Low | High | Maintain rule tests for every changed collection and production denial canaries | Controlled; review every auth/data release |
| P-02 | Client forges role, ownership, timestamps, stats or system fields | Low | High | Keep roles/system fields server-owned and schemas allow-listed | Controlled |
| P-03 | Voice recorded without documented school authority or retained too long | Low | High | First-enable server gate records authority/notice declarations and 30/90/365-day retention; uploads fail closed without current evidence; legacy 7-day deletion commitments remain enforced; audit enabled schools quarterly | Technical gate implemented; each school must still make and honour its decision |
| P-04 | Transcript/audio disclosed to an overseas AI provider or used for training | Medium if enabled | High | Keep kill switch off; execute DPA; document countries/subprocessors, ZDR/training, deletion and APP 8 steps; approve a new PIA | Blocked by design / no-go |
| P-05 | Optional SDK sends data before consent or policy differs from runtime | Low | Medium | Keep native+Dart defaults off; repeat store-signed traffic capture and questionnaires every SDK change | Store evidence open |
| P-06 | App Check enforcement locks out real users or is left unenforced indefinitely | Medium | Medium | Observe store-attested valid traffic, stage enforcement, monitor denials and maintain rollback | Store evidence open |
| P-07 | Deletion fails partially, misses a subcollection/object or backup copy | Low | High | Retain integration tests and job receipts; complete signed-in device retest; document PITR/beyond-use period | Device retest open |
| P-08 | Overseas provider/support access is not contractually assessed | Medium | High | Technical locations are inventoried and dated public Google/Firebase/Twilio terms are retained; complete account-acceptance, support-access and APP 8 approval for US Authentication, global services/logs and SendGrid | Open release blocker |
| P-09 | Unbounded reads/listeners expose more data than needed and create cost pressure | Low | Medium | Retain pagination, summary, listener and 30/100/1,000-student regression evidence | Controlled; review every data/UI release |
| P-10 | Security alert is missed or incident response is improvised | Low | High | Reconfirm both alert inboxes, roles and six-monthly tabletop cadence | Dual delivery and operational roles verified; Privacy/Legal Lead remains unappointed |
| P-11 | Support/access/deletion requester impersonates a parent or school | Medium | High | Verify authority through existing account and school contact; never act from an unverified email alone; log decisions | Procedure defined; exercise required |
| P-12 | Book lookup leaks child context through titles/searches | Low | Medium | Send only ISBN/title; never include child, school, notes or account identifiers; retain manual entry | Controlled |

## 6. APP and children's-code alignment

- **APP 1 / governance:** this PIA, the vendor register, release gate and breach
  plan establish documented practices. Named ownership and counsel approval
  remain open.
- **APP 3 / collection:** the purpose table records necessity; voice,
  diagnostics and AI are not treated as necessary core data.
- **APP 5 / notice:** the live privacy page describes categories, providers,
  location, optional diagnostics and deletion. First audio opt-in now records
  the school's authority and its commitment to notify families, explain purpose
  and retention, and offer a practical opt-out. The school must still deliver
  that notice; the checkbox is evidence, not a substitute for it.
- **APP 6 / use and disclosure:** school use is role/class/child-scoped. New
  vendors or AI purposes require change review.
- **APP 8 / overseas recipients:** dated public contract/subprocessor evidence
  is retained, but Lumi account-acceptance, overseas support-access and counsel
  approval are not complete. The technical audit confirms US-only Firebase
  Authentication plus global Firebase, required-log and SendGrid paths; these
  are not made Australian by Firestore's Sydney region. The three application
  secrets were separately migrated to Sydney-only payload replicas.
  The OAIC notes that reasonable steps may be
  required before disclosure and an entity may remain accountable for an
  overseas recipient: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-8-app-8-cross-border-disclosure-of-personal-information
- **APP 10 / quality:** schools and parents can correct records; support must
  verify authority before making corrections.
- **APP 11 / security and destruction:** technical controls are strong, but
  provider deletion verification, retention schedules and the device deletion
  retest remain. OAIC guidance requires active security measures and reasonable
  destruction/de-identification when data is no longer needed:
  https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-11-app-11-security-of-personal-information
- **APP 12/13 / access and correction:** requests use the school or
  `support@lumi-reading.com`; the response workflow must record identity,
  authority, scope, decision and completion.

The Children's Online Privacy Code is still an exposure draft as at this
assessment. Lumi should nevertheless apply best interests, high privacy by
default, strict necessity and accessible deletion now. Final legal applicability
must be rechecked when the Code is registered by 10 December 2026:
https://www.oaic.gov.au/privacy/privacy-registers/privacy-codes/childrens-online-privacy-code

## 7. Recommendations and release decision

### Must close before processing real school voice or AI data

- [x] Require and record the enabling school's authority declaration, family
  notice/opt-out commitment and chosen 30/90/365-day audio retention period
  before collection. *(Implemented as a first-opt-in portal gate with protected
  audit evidence and fail-closed upload enforcement. Each school remains
  responsible for the declared notice/authority process.)*
- [~] Complete Google/Firebase and SendGrid DPA/subprocessor/location/support
  evidence and an APP 8 decision approved by counsel. *(Official public terms,
  subprocessors, security and retention evidence are retained with hashes;
  private Lumi account-acceptance evidence and counsel approval remain.)*
- [ ] Keep AI provider processing disabled until a separate approved PIA and
  vendor controls exist.
- [x] Confirm both security alert inboxes and the support mailbox are monitored.
  *(Support is owner-confirmed daily and MFA-protected. Nicholas Plevritis
  confirmed on 17 July 2026 that synthetic Cloud Monitoring incident
  `0.oabm7h2yj055` arrived in both the primary and backup security inboxes.)*
- [ ] Complete the user's signed-in account/student deletion device test.

### Must close before public store launch

- [ ] Obtain store-signed App Attest/Play Integrity evidence and stage App Check
  enforcement without breaking supported versions.
- [ ] Make live App Store/Play privacy questionnaires match the final binary.
- [ ] Scan final signed artifacts and register production signing identities.
- [ ] Obtain owner and Australian privacy-counsel approval of this PIA.

### First-month work

- [x] Finish pagination/load tests. *(Stable 30-record pages, sharded daily
      summaries and 30/100/1,000-student profiles are complete.)*
- [ ] Tune alert thresholds after a pilot.
- [ ] Review retention and destruction evidence monthly during beta.
- [ ] Run the breach tabletop every six months and after a material incident.

## 8. Approval and review

| Role | Name | Decision | Date |
| --- | --- | --- | --- |
| Product/privacy owner | Pending | Pending | — |
| Technical/security reviewer | Pending | Pending | — |
| Australian privacy counsel | Pending | Pending | — |

Review this assessment on every release that changes authentication, child
data, Storage, voice/AI, analytics, vendors, retention or deletion, and at least
quarterly while schools are in beta.
