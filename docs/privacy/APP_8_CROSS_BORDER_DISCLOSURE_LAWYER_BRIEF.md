# Lumi APP 8 cross-border disclosure brief and lawyer checklist

**Prepared:** 17 July 2026
**Owner:** Nicholas Plevritis, Director of Lumi
**Legal status:** working brief for Australian privacy-counsel review; not legal
advice and not an approval to commence a new data flow.

## TL;DR

Australian Privacy Principle 8 is about what an APP entity must do before it
discloses personal information to an overseas recipient. The usual rule is to
take reasonable steps to ensure the recipient does not breach the APPs in its
handling of the information. Section 16C can make the Australian APP entity
accountable for an overseas recipient's conduct as if it were the entity's own.

For Lumi, Australian-hosted Firestore, Storage and Functions reduce risk but do
not settle APP 8. Firebase Authentication, global Firebase services, Google
support/subprocessors, required global logs, SendGrid and app-platform services
can still involve overseas handling or access. The correct legal answer also
depends on whether Lumi is an APP entity, whether Lumi or the school is the
controller/APP entity for each data flow, whether a cloud arrangement is a
disclosure or remains a use under Lumi's effective control, and the relevant
state/territory school privacy law and contract.

Lumi should design to the higher standard even if the federal small-business
exemption currently applies. Schools can still impose equivalent or stricter
contractual and state-law requirements, and the exemption or the law may
change. No production AI/LLM processing is approved by this document.

## 1. What APP 8 requires

APP 8.1 says that before an APP entity discloses personal information about an
individual to an overseas recipient, it must take reasonable steps in the
circumstances to ensure that recipient does not breach the APPs other than APP
1 in relation to the information.

The obligation is connected to several other principles:

- **APP 6 — use and disclosure:** the overseas disclosure must still be for the
  collection's primary purpose, be consented to, or fit another APP 6 basis.
- **APP 5 — notification:** collection notices and the privacy policy should
  accurately explain likely overseas recipients/countries where practicable.
- **APP 11 — security and destruction:** Lumi must take reasonable security
  steps and destroy or de-identify information when no longer needed, subject
  to lawful retention.
- **Section 16C:** if APP 8.1 applies, an overseas recipient's APP-inconsistent
  conduct can be attributed to the Australian APP entity. Taking reasonable
  steps does not automatically remove that accountability.

The OAIC describes “reasonable” as an objective, fact-specific test that the
entity must be able to justify. Relevant factors include sensitivity, likely
harm, the relationship with the recipient, technical/operational safeguards,
practicability, time and cost. Child identity, educational history, family
links, messages and voice data justify a stronger response than ordinary
business contact data.

## 2. Disclosure versus use in a cloud service

APP 8 is engaged by a **disclosure** to an overseas recipient. The OAIC says a
disclosure generally occurs when information is made accessible outside the
entity and subsequent handling is released from the entity's effective
control. Routing encrypted information through an overseas server does not by
itself necessarily amount to a disclosure.

Providing information to an overseas contractor will usually be a disclosure.
In limited circumstances it may remain a use by the APP entity where the entity
keeps effective control. The OAIC's cloud example points to:

- a binding contract limiting the provider to storage/access services on the
  entity's instructions;
- equivalent obligations imposed on subcontractors;
- the entity retaining practical control over access, change, retrieval and
  permanent deletion;
- clear limits on who else can access the information and why; and
- adequate security for storage and management.

Even if counsel concludes a particular hosted flow is a use rather than a
disclosure, Lumi may still “hold” the information and remain responsible under
APPs including APP 11. The distinction does not make vendor security,
retention, deletion or access controls optional.

## 3. APP 8.2 exceptions

Counsel must identify any exception actually relied on. Lumi should not assume
an exception merely because a vendor has a privacy policy or international
certification.

The main statutory paths include:

1. **Comparable law or binding scheme:** Lumi reasonably believes the recipient
   is subject to substantially similar protection and individuals have
   accessible enforcement mechanisms.
2. **Express informed consent:** before consent, the individual is expressly
   told that APP 8.1 will not apply if they consent, and then consents. This can
   remove important accountability and is a poor default for a children's
   school service. It requires specific legal drafting and should not be buried
   in general terms.
3. **Required or authorised by Australian law or court/tribunal order.** A
   foreign law alone is not this exception.
4. **Permitted general situations**, such as a necessary response to a serious
   threat or certain serious misconduct, where the statutory test is met.
5. Additional agency/enforcement exceptions that generally are not ordinary
   commercial grounds for Lumi.

Lumi's current risk treatment should be contractual/technical reasonable steps,
data minimisation and accurate notice. It should not rely on a blanket child or
parent waiver of APP 8 accountability.

## 4. Does the Privacy Act apply to Lumi?

The OAIC says most businesses with annual turnover of AUD 3 million or less are
small businesses and generally exempt, but lists exceptions. Coverage can also
depend on activities, related bodies and handling of health information.

That does not resolve Lumi's obligations because:

- private schools are often APP entities; public schools are generally subject
  to state or territory privacy frameworks instead;
- a school contract may require Lumi to comply with the school's privacy duties
  regardless of Lumi's turnover;
- Lumi may act as a contractor/processor while the school remains responsible,
  or Lumi may independently determine some purposes and have its own duties;
- child voice or other records could become more sensitive depending on use;
- the small-business exemption, children's code and broader Privacy Act reforms
  can change; and
- good privacy controls remain commercially necessary for school procurement.

### Counsel decision required

- [ ] Is the Lumi operating entity currently an APP entity, and under which
  provision or exception?
- [ ] Does Lumi voluntarily opt in to Privacy Act coverage, or contractually
  commit to APP-equivalent handling?
- [ ] For government, Catholic and independent schools in each launch state,
  which federal/state education and privacy regimes apply?
- [ ] For each data category, is the school, Lumi or both determining purpose
  and means?
- [ ] Does any information become health information or another specially
  regulated category through product use?

## 5. Lumi's current cross-border inventory

| Service/flow | Current technical state | APP 8 question for counsel |
| --- | --- | --- |
| Firestore | Child/school database in Sydney | Do Google/subprocessor/support access rights create a disclosure, or does the contract preserve effective control? |
| Cloud Storage | Covers/audio in Sydney; strict Rules, signed URLs and deletion | Same effective-control question; assess voice sensitivity, support access and backup deletion |
| Cloud Functions/Run | Application workloads in Sydney using dedicated identities | Assess transient processing, logging and global control/support paths |
| Firebase Authentication | Adult identifiers and credentials; documented as US-only/global path | Identify recipient/countries, lawful purpose, notice, retention and enforceable protections |
| FCM/APNs | Device tokens and deliberately limited notification content | Assess Google/Apple global handling and ensure payload minimisation remains adequate |
| App Check | Device/app attestation metadata; no intended child content | Record overseas recipient/purpose and keep payload content-free |
| Analytics/Crashlytics | Optional, adult-controlled and off by default; child/account identifiers prohibited | Confirm whether to retain at all; align overseas notice and store disclosures with observed traffic |
| Cloud Logging/audit | Ordinary future logs routed to Sydney; required audit logs can remain global | Confirm whether minimised identifiers and global required logs are acceptable |
| Secret Manager | Application secrets only, not child content; all three active payloads were migrated to Sydney-only replicas and the global originals deleted on 17 July 2026 | Usually not personal information, but document admin/support access and avoid secrets containing personal data |
| Twilio SendGrid | Adult/school transactional email; North American/US and EU subprocessors | Confirm APP 8 treatment, notices, DPA adequacy, one-year termination-backup term and minimised templates |
| Google Books/Open Library | ISBN/title only; no school, account or child identifier | Confirm that continued strict field minimisation keeps risk low |
| Apple/Google stores | Adult account/device/distribution information | Finalise after organisation enrolment and platform agreements |
| Speech-to-Text/LLM | **Production processing disabled** | New vendor review, school authority, specific notice/consent analysis, no-training/ZDR terms, retention, deletion and new PIA required before enablement |

The technical location inventory is in
`docs/security/AU_RESOURCE_LOCATION_AUDIT_2026-07-17.md`. The dated public
vendor terms are under `docs/privacy/vendor-evidence/2026-07-17/`.

## 6. Reasonable-steps checklist for each overseas recipient

For Google/Firebase, SendGrid and every future overseas provider, complete and
retain the following:

### Purpose and minimisation

- [ ] State the exact product purpose and why local/on-device processing is not
  reasonably sufficient.
- [ ] List every field sent, including metadata, IP/device data, logs and
  support attachments.
- [ ] Remove child names/content and school identifiers unless strictly needed.
- [ ] Confirm the provider cannot use content for advertising, model training or
  unrelated product development without a separately approved instruction.

### Recipient and country

- [ ] Identify the contracting provider entity.
- [ ] Identify storage, ordinary processing, support/admin and subprocessor
  countries; distinguish each rather than saying only “global”.
- [ ] Subscribe to subprocessor/terms change notices and assign an owner.
- [ ] Record onward-transfer restrictions and the provider's liability for
  subprocessors.

### Contract and effective control

- [ ] Retain the DPA, master/online terms, service-specific terms, order form and
  account acceptance evidence.
- [ ] Confirm purpose limitation, confidentiality, personnel access, security,
  incident notification, audit evidence and cooperation with rights requests.
- [ ] Confirm Lumi can access, correct, export, delete and retrieve data and can
  terminate the service without losing required evidence.
- [ ] Confirm deletion from active systems, replicas and backups, including
  maximum periods and legal holds.
- [ ] Confirm equivalent obligations apply to subprocessors.

### Security and operations

- [ ] Record encryption in transit/at rest, tenant isolation, IAM/MFA, audit
  logging, vulnerability management and independent certifications.
- [ ] Give provider access only to dedicated least-privilege identities.
- [ ] Redact support cases and grant temporary support access only when needed.
- [ ] Test deletion, export, incident contacts and provider kill switches.
- [ ] Set a review date and evidence owner.

### Notice and individual/school rights

- [ ] Update the privacy policy and school notice with recipients/countries
  where practicable, purposes and complaint/contact paths.
- [ ] Ensure school contracts identify approved subprocessors and change
  notification/objection processes.
- [ ] Verify access, correction, deletion and complaint workflows traverse the
  vendor, including backup limitations.
- [ ] Do not use the APP 8.2 informed-consent exception without counsel's exact
  advice and wording.

## 7. Work completed before counsel review

- [x] Firestore, child-content Storage and application workloads located in
  `australia-southeast1`.
- [x] Dedicated keyless least-privilege runtime identities and Scheduler audit.
- [x] Firestore/Storage cross-school/class/family denial test matrix.
- [x] Audio off by default; first school opt-in records authority, family notice
  commitment and 7/30/90/365-day retention; upload fails closed.
- [x] Optional Analytics/Crashlytics off by default with adult controls and
  physical iPhone network evidence.
- [x] Account/student deletion workflow and automated cascade tests.
- [x] PITR, restore drill, monitoring, confirmed dual-recipient alerts and
  documented breach plan.
- [x] Production application logs stripped of child/account/school identifiers
  and raw exception payloads.
- [x] Dated public Google/Firebase/Twilio/OAIC evidence pack captured with
  SHA-256 hashes.
- [x] Operational incident roles assigned to Nicholas Plevritis, with Kylie
  Plevritis authorised to act for Lumi if Nicholas is unavailable.
- [x] `ADMIN_SESSION_SECRET_AU`, `SENDGRID_API_KEY_AU` and
  `SENDGRID_SENDER_EMAIL_AU` created with single `australia-southeast1`
  replicas to replace the former unsuffixed global resources;
  six live consumers verified healthy on dedicated identities and the three
  former globally replicated resources deleted.
- [ ] External Australian privacy/legal lead appointed.
- [ ] Account-specific contract/acceptance evidence retained outside Git.
- [ ] Physical signed-in account/student deletion test completed.
- [ ] Store privacy questionnaires and production attestation evidence completed
  after Apple/Google organisation enrolment.

## 8. Lawyer meeting pack

Give counsel these files:

1. This brief.
2. `PRIVACY_IMPACT_ASSESSMENT.md`.
3. `VENDOR_DATA_FLOW_REGISTER.md`.
4. `DATA_BREACH_RESPONSE_AND_TABLETOP.md`.
5. `AU_RESOURCE_LOCATION_AUDIT_2026-07-17.md`.
6. `LUMI_SECURITY_HARDENING_CHECKLIST_2026-07-15.md`.
7. The dated `vendor-evidence/2026-07-17/` pack.
8. The then-current public privacy policy, school agreement/DPA and family audio
   notice.
9. Private account-specific Google/Twilio acceptance/billing evidence.

Ask counsel to deliver a written decision that:

- identifies Lumi's legal entity and current Privacy Act coverage;
- allocates school/Lumi roles per data flow and school type/state;
- classifies each overseas flow as disclosure or use/effective control;
- states which APP 8.1 reasonable steps and APP 8.2 exceptions are relied on;
- approves or amends the privacy policy, school DPA/contract, family notice and
  audio wording;
- approves the Google/Firebase and SendGrid treatments or lists mandatory
  changes;
- gives a position on government-school state privacy requirements;
- confirms the NDB decision process and names/engages the privacy/legal lead;
- records whether Lumi should voluntarily opt into Privacy Act coverage; and
- provides a review trigger and expiry date for the advice.

## 9. Sign-off record

| Decision | Counsel conclusion | Evidence/reference | Approver | Date/expiry |
| --- | --- | --- | --- | --- |
| Lumi is/is not an APP entity | Pending | — | Pending | — |
| Google/Firebase cross-border treatment | Pending | — | Pending | — |
| SendGrid cross-border treatment | Pending | — | Pending | — |
| School contract/DPA wording | Pending | — | Pending | — |
| Family/audio notice wording | Pending | — | Pending | — |
| NDB/privacy legal lead | Pending | — | Pending | — |
| AI/LLM processing | **Not approved** | Production kill switch remains off | Counsel required before change | — |

## 10. Official starting sources

- OAIC, APP 8 guideline, updated 3 October 2025:
  https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-8-app-8-cross-border-disclosure-of-personal-information
- OAIC, sending personal information overseas:
  https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/handling-personal-information/sending-personal-information-overseas
- OAIC, small business guidance:
  https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/organisations/small-business
- OAIC, state and territory privacy legislation:
  https://www.oaic.gov.au/privacy/privacy-legislation/state-and-territory-privacy-legislation
- Privacy Act 1988, current authorised text:
  https://www.legislation.gov.au/C2004A03712/latest/text
- Google Cloud Data Processing Addendum:
  https://cloud.google.com/terms/data-processing-addendum
- Google Cloud subprocessors:
  https://cloud.google.com/terms/subprocessors
- Firebase Data Processing and Security Terms:
  https://firebase.google.com/terms/data-processing-terms
- Twilio Data Protection Addendum:
  https://www.twilio.com/en-us/legal/data-protection-addendum
- Twilio subprocessors:
  https://www.twilio.com/en-us/legal/sub-processors
