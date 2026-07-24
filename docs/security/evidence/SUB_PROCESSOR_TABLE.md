# Lumi Sub-Processor Table (public disclosure draft)

> ## ⚠️ PRIVACY/LEGAL-SENSITIVE DRAFT — PRIVACY ADVISER MUST REVIEW BEFORE PUBLICATION
> This is a **draft** for the appointed Australian privacy adviser to review. It
> is intended to become a public-facing sub-processor disclosure, so no row may
> be published, linked from the live privacy policy, or given to a school until
> the privacy adviser has signed it off. It does **not** modify any live page.
> Nothing here is legal advice.

**ST4S item:** PR17 (sub-processors fully described publicly)
**Version:** 0.1 — DRAFT for review, not yet signed
**Date:** 2026-07-24
**Status:** Draft for review — not yet signed
**Primary source:** `docs/privacy/VENDOR_DATA_FLOW_REGISTER.md` (v1.0, reviewed 17 July 2026)

---

## 1. Purpose

This table lists the third-party sub-processors that support the Lumi Reading
service, so a school can see who processes personal information on Lumi's behalf,
what each one touches, why, and where. It is derived entirely from the internal
vendor and data-flow register; where the register marks a vendor's contractual
status as **Conditional** or **Blocked**, that is reflected here rather than
smoothed over.

A note on terminology: a *sub-processor* is a service Lumi uses to **operate the
service on Lumi's (and the school's) instructions**. Using a sub-processor to run
the service is **not** the same as sharing data with an independent third party
for that party's own purposes — see `DATA_SHARING_AUDIT.md` (PR10).

## 2. Active sub-processors

| Sub-processor / service | Website / contact | Personal information touched | Purpose | Lawful basis (operational) | Processing / storage countries |
|---|---|---|---|---|---|
| **Google Cloud Firestore** (Google LLC / Google Cloud) | cloud.google.com · cloud.google.com/terms/data-processing-addendum | School, child, adult, roster, reading and messaging records | Primary application database that stores and serves all school-scoped records | Service operation — processor acting on Lumi/school instructions under the Google Cloud DPA (APP 6 primary purpose) | Storage & processing: **Australia — `australia-southeast1` (Sydney)** |
| **Google Cloud Storage** (Google Cloud) | cloud.google.com | Optional validated comprehension audio, school logos, book covers | Object storage for user-uploaded media and assets | Service operation — processor under the Google Cloud DPA | User-content buckets: **Australia (`australia-southeast1`)**. A legacy managed code-source bucket exists in the **US** (no user content intended) |
| **Cloud Functions / Cloud Run / Eventarc / Cloud Scheduler** (Google Cloud) | cloud.google.com | All record types, **transiently**, during server logic | Server-side authorisation, aggregation, notifications, deletion and media validation | Service operation — processor under the Google Cloud DPA | **Australia (`australia-southeast1`)** — all 77 live application workloads and all 17 Scheduler jobs verified in-region |
| **Google Cloud Logging** (Google Cloud) | cloud.google.com | Application/security events. Direct account/school/child/record identifiers and raw exceptions are **prohibited** in application log payloads; an admin identity can appear in Google's required audit logs | Operational and security logging; platform audit trail | Service operation — processor under the Google Cloud DPA | Future ordinary logs: **Australia (`australia-southeast1`)**. Pre-change ordinary logs and unavoidable `_Required` audit logs are **global** |
| **Google Cloud Secret Manager** (Google Cloud) | cloud.google.com | Application secrets only (SendGrid credentials, portal session secret) — **no child content intended** | Secure storage of service credentials | Service operation — processor under the Google Cloud DPA | **Australia (`australia-southeast1`)** — single AU replica (former globally-replicated resources deleted 17 July 2026) |
| **Firebase Authentication / Identity Platform** (Google LLC) | firebase.google.com · firebase.google.com/terms/data-processing-terms | **Adult** UID, email/phone, MFA factors, sign-in and recovery metadata | Account authentication, MFA, and recovery for parents/carers and staff | Service operation — processor under the Firebase Data Processing & Security Terms | **United States** — Firebase documents Authentication as a US-only processing service |
| **Firebase Cloud Messaging (FCM)** (Google LLC) | firebase.google.com | Device push token; adult-facing notification content (may reveal limited reading context) | Delivery of reminders, achievement and comment notifications, school announcements | Service operation — processor under the Firebase terms | **Global** platform service |
| **Apple Push Notification service (APNs)** (Apple Inc.) | developer.apple.com/notifications | Device push token; adult-facing notification content | Push-notification delivery to Apple devices | Service operation — platform provider under Apple developer terms | **Global** platform service |
| **Firebase App Check** (Google LLC) | firebase.google.com | App/device attestation tokens — **no intended content data** | Client attestation / anti-abuse (enforcement not yet switched on) | Service operation — processor under the Firebase terms | Google service; **global** support may apply |
| **Firebase Analytics** (Google LLC) | firebase.google.com | Pseudonymous, optional usage events — **no child/account identifiers, no Lumi UID, no detailed reading fields** | Product-usage insight to improve the app | **Adult opt-in consent** (off by default; withdrawable) | **May process outside Australia** |
| **Firebase Crashlytics** (Google LLC) | firebase.google.com | Optional crash stack traces and app/device diagnostics — **no Lumi UID; child content prohibited** | Diagnose and fix crashes | **Adult opt-in consent** (off by default; withdrawable) | **May process outside Australia** |
| **Twilio SendGrid** (Twilio Inc.) | twilio.com · twilio.com/en-us/legal/data-protection-addendum | Adult/school transactional email content; may include adult/school data and temporary credentials — **child data excluded by policy** | Onboarding, school/staff service and operational email | Service operation — processor under the Twilio DPA (which names the Australian Privacy Act 1988) | SendGrid infrastructure in **North America / EU** (DataBank, Lumen, Digital Realty); Twilio Inc. may process in the **USA** |
| **Google Books API** (Google LLC) | developers.google.com/books | **ISBN / title only** — no identity data | Look up public book metadata and covers | Service operation — **no personal information sent** | Google public API; may process **globally** |
| **Open Library / Internet Archive** | openlibrary.org | **ISBN / title / work ID only** — no identity data | Look up public book metadata, descriptions and cover images | Service operation — **no personal information sent** | Overseas public service |
| **Apple App Store** (Apple Inc.) | apple.com/legal | Adult/device account, purchase and store-diagnostic data governed by the platform | App distribution and platform account management | Platform/contract necessity — governed by Apple developer + platform terms | Platform-defined **global** processing |
| **Google Play** (Google LLC) | play.google.com | Adult/device account, purchase and store-diagnostic data governed by the platform | App distribution and platform account management | Platform/contract necessity — governed by Google Play developer terms | Platform-defined **global** processing |
| **Support mailbox provider** *(provider not yet named — see gaps)* | Public contact: `support@lumi-reading.com` | Privacy, access, correction, deletion and incident reports (potentially any record type a requester includes) | Receive and action privacy and support requests | Service operation — processor | **Not yet recorded** — provider identity and location to be captured |

## 3. Sub-processors configured but prohibited for production personal data

These are recorded here for completeness because they are technically configured
but are **not** permitted to receive production personal information. Per the
vendor register they are gated `Blocked` / `Not approved` and must not appear in
a "we use these today" public statement.

| Service | Proposed purpose | Status |
|---|---|---|
| Google Cloud Speech-to-Text | Transcribe optional comprehension audio (AI feature) | **Blocked** — AI kill switch off; no connected pipeline |
| Google Vertex AI (Gemini) | Proposed transcript comprehension evaluation, Sydney-regional | **Blocked** — feature disabled in production; PIA/counsel approval pending |
| Anthropic / OpenAI / other LLMs | Evaluation alternatives from cost research only | **Not approved / superseded** (design moved to Vertex-AU; no production call) |
| Stripe | Future direct-sales design only | **Not implemented** — no dependency, secret or data flow |

## 4. Lawful-basis caveat (adviser must confirm)

"Lawful basis" above states the **operational** basis Lumi relies on to run the
service. Whether Lumi is itself an APP entity, and whether Lumi or the school is
the controller for each flow, is **not yet determined** — it is an open question
for counsel (`APP_8_CROSS_BORDER_DISCLOSURE_LAWYER_BRIEF.md` §4). The adviser
should confirm the correct legal characterisation (processor vs controller;
APP 6 primary-purpose vs consent) before this column is published.

## 5. Evidence index

| Claim | Evidence |
|---|---|
| Vendor list, data types, purposes, locations, statuses | `docs/privacy/VENDOR_DATA_FLOW_REGISTER.md` (v1.0, 17 Jul 2026) |
| AU region of Firestore/Storage/Functions/Scheduler | `docs/security/AU_RESOURCE_LOCATION_AUDIT_2026-07-17.md`; PIA §4 |
| Firebase Auth US-only path | Firebase Data Processing & Security Terms; PIA §3.1; APP 8 brief §5 |
| SendGrid NA/EU/US sub-processors | `docs/privacy/vendor-evidence/2026-07-17/README.md`; Twilio subprocessor snapshot |
| Book APIs receive ISBN/title only | PIA risk P-12; live privacy page §4; register rows for Google Books / Open Library; and `DATA_SHARING_AUDIT.md` |
| Google/Firebase/Twilio DPAs captured (dated, hashed) | `docs/privacy/vendor-evidence/2026-07-17/README.md` |
| Secrets migrated to AU-only replicas | APP 8 brief §7; register row (Secret Manager) |

## 6. Known gaps / adviser must confirm

- **Contractual status is Conditional for most core vendors.** The register
  marks Firestore, Storage, Functions, Logging, Firebase Auth, FCM/APNs and
  SendGrid as `Conditional` pending DPA/support-access/APP 8 review. This table
  must not be published in a way that implies those reviews are complete.
- **Support mailbox provider is not named.** The provider identity, delegate
  list and mailbox retention are still open (register: "Open release action").
  Fill this row before publication.
- **Cloudflare is not in the vendor register.** A Cloudflare Worker serves the
  in-app status banner (`lumistatus.*.workers.dev`) and the marketing/portal
  sites may transit Cloudflare. If Cloudflare processes any personal information
  (e.g. IP addresses at the edge), it belongs in this table and in the register.
  Adviser to confirm scope; see `INT7_SUBPROCESSOR_AGREEMENTS_RECORD.md`.
- **Lawful-basis / controller determination pending counsel** (see §4).
- **Legal-entity naming.** The public table should name the Lumi contracting
  entity (and ABN) once confirmed; account-acceptance evidence proving which
  entity accepted each DPA is held outside Git (register "Evidence still
  required").
- **US/global flows require APP 8 sign-off** before this is presented as a
  settled cross-border disclosure statement.
- **Sign-off.** Requires the privacy adviser's review and Nic's approval before
  it is linked from any live page or given to a school.
