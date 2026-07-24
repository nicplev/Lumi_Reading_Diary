# Sub-Processor / Integrated-Vendor Data-Agreement Record (template)

> ## ⚠️ PRIVACY/LEGAL-SENSITIVE — PRIVACY ADVISER MUST REVIEW
> This record captures acceptance of each vendor's data-processing terms.
> **Contracting entity confirmed** (2026-07-24): every account is under **Lumi
> Education Pty Ltd, ABN 45 700 349 015**; the **support mailbox provider is
> Google Workspace**. The agreements are **in force** (incorporated in the terms
> already accepted to operate each account). The remaining INT7 step is Nic
> **filing the dated console acceptance proof** per vendor in the access-controlled
> legal folder, then setting each row to `Yes`. Do not store signed/account
> artefacts in Git — reference their access-controlled location only. Not legal advice.

**ST4S item:** INT7 (written data agreements with integrated third parties)
**Version:** 0.2 — entity + support provider confirmed 2026-07-24; acceptance proof to be filed
**Date:** 2026-07-24
**Owner of actual acceptances:** Nic (Lumi owner/director)
**Evidence location:** `docs/privacy/vendor-evidence/` (public terms, dated + hashed) + an access-controlled legal folder outside Git (account-acceptance proof)

---

## 1. Purpose

INT7 asks whether Lumi has **written data agreements** with the third parties it
integrates. This record captures, per vendor: the agreement name, whether/when it
was accepted, the contracting Lumi entity, and where the evidence lives. It works
with the vendor register (`docs/privacy/VENDOR_DATA_FLOW_REGISTER.md`) and the
dated public-terms pack (`docs/privacy/vendor-evidence/2026-07-17/`).

**Important distinction (from `vendor-evidence/2026-07-17/README.md`):** capturing
a vendor's *public* terms proves the terms existed and their content on a date; it
does **not** prove which Lumi legal entity **accepted** them, when, or on which
billing account. INT7 needs the latter — the acceptance record — which only Nic
can produce from the vendor consoles/accounts.

## 2. Acceptance record (Nic completes)

Fill each row from the vendor console / account. Use **role labels**, never
personal emails or phone numbers, for any named contact. Set "Accepted?" to
`Yes` only when the acceptance evidence is captured and filed.

All accounts are contracted under **Lumi Education Pty Ltd (ABN 45 700 349 015)** —
confirmed 2026-07-24. "Accepted?" distinguishes an agreement that is *in force*
(incorporated in terms already accepted to operate the account) from the ST4S
evidence artefact — a **dated console export/screenshot of the acceptance** — which
Nic still files in the access-controlled legal folder before a row is complete.

| # | Vendor / integration | Agreement name | Accepted? | Date accepted | Contracting Lumi entity | Acceptance evidence location |
|---|---|---|---|---|---|---|
| 1 | **Google Cloud** (Firestore, Storage, Functions/Run, Logging, Secret Manager) | Google Cloud **Data Processing Addendum** (+ service-specific terms) | ◑ In force — DPA auto-incorporated in accepted Cloud terms; **console proof to file** | On account/billing setup (capture exact) | Lumi Education Pty Ltd (ABN 45 700 349 015) | Public terms: `vendor-evidence/2026-07-17/raw/google-cloud-data-processing-addendum.txt`. Account-acceptance proof: *[legal folder]* |
| 2 | **Firebase** (Authentication, FCM, App Check, Analytics, Crashlytics) | Firebase **Data Processing and Security Terms** | ◑ In force — incorporated in accepted Firebase terms; **console proof to file** | On project setup (capture exact) | Lumi Education Pty Ltd (ABN 45 700 349 015) | Public terms: `vendor-evidence/2026-07-17/raw/firebase-data-processing-security-terms.txt`. Account proof: *[legal folder]* |
| 3 | **Twilio SendGrid** (email) | Twilio **Data Protection Addendum** | ◑ Confirm/accept in console — **proof to file** | — (capture on acceptance) | Lumi Education Pty Ltd (ABN 45 700 349 015) | Public terms: `vendor-evidence/2026-07-17/raw/twilio-data-protection-addendum.txt`. Account proof: *[legal folder]* |
| 4 | **Cloudflare** (status-banner Worker; any CDN/edge in front of sites) | Cloudflare **Data Processing Addendum** | ☐ Accept in dash + **add to vendor register** — proof to file | — | Lumi Education Pty Ltd (ABN 45 700 349 015) | Public terms: *[capture to `vendor-evidence/`]*. Account proof: *[legal folder]* |
| 5 | **Apple** (App Store distribution, APNs) | Apple **Developer Program License Agreement** (+ any Apple DPA/addendum) | ◑ In force — DPLA accepted (required to publish); **export to file** | On developer enrolment (capture exact) | Lumi Education Pty Ltd (ABN 45 700 349 015) | Enrolment/agreement export: *[legal folder]* |
| 6 | **Google Play** (distribution) | Google Play **Developer Distribution Agreement** (+ Play data terms) | ◑ In force — DDA accepted (required to publish); **export to file** | On console enrolment (capture exact) | Lumi Education Pty Ltd (ABN 45 700 349 015) | Enrolment/agreement export: *[legal folder]* |
| 7 | **Google Workspace** (support mailbox — `support@lumi-reading.com`) | Google Workspace **Data Processing Amendment** (Google Cloud/Workspace terms) | ◑ In force — incorporated in accepted Workspace terms; **admin-console proof to file** | On Workspace setup (capture exact) | Lumi Education Pty Ltd (ABN 45 700 349 015) | Public terms: capture Workspace DPA to `vendor-evidence/`. Admin proof: *[legal folder]* |

*(Google Books and Open Library are public metadata APIs receiving ISBN/title
only — no personal information — so they are not data-processing counterparties.
Record their public privacy/retention terms in the vendor register for
completeness, but no DPA is expected. Confirm with the adviser.)*

## 3. The one-line vendor-gate rule (feeds EV6)

To keep this record complete over time, adopt the following standing rule (to be
added to the EV6 change/vendor-management control):

> **No new SDK, API, sub-processor or vendor secret may be added to production
> until the vendor register records its purpose, data, location, retention,
> deletion, contract/DPA, security owner and APP 8 decision, and this INT7 record
> has the accepted data agreement filed.**

This mirrors data-flow rule 3 already in the vendor register
(`VENDOR_DATA_FLOW_REGISTER.md` §Data-flow rules) and makes it a release gate.

## 4. Evidence index

| Item | Location |
|---|---|
| Dated + hashed public terms (Google/Firebase/Twilio/OAIC) | `docs/privacy/vendor-evidence/2026-07-17/README.md` |
| Vendor register (purpose/data/location/status per vendor) | `docs/privacy/VENDOR_DATA_FLOW_REGISTER.md` |
| Companion public sub-processor table | `SUB_PROCESSOR_TABLE.md` (PR17) |
| Cross-border/APP 8 legal framing | `APP_8_CROSS_BORDER_DISCLOSURE_LAWYER_BRIEF.md` |
| Account-acceptance / billing proof | Access-controlled legal folder outside Git (do not commit) |

## 5. Known gaps / adviser must confirm

- **Acceptance proof still to be filed (the one open INT7 action).** The agreements
  are in force, but the *dated console export/screenshot* per vendor is not yet
  filed. Nic captures each and files it in the access-controlled legal folder, then
  sets the row to `Yes` with the exact date.
- **Cloudflare is not yet in the vendor register.** A Cloudflare Worker serves the
  in-app status banner and Cloudflare may sit in front of the sites; capture its
  DPA and add it to the register (and to `SUB_PROCESSOR_TABLE.md`) — or record a
  reasoned finding that it processes no personal information.
- **Support mailbox provider — named.** Confirmed 2026-07-24 as **Google Workspace**
  (Google LLC); capture its Workspace Data Processing Amendment + admin-console
  proof like the other Google services.
- **Contracting entity / ABN — confirmed.** All accounts are under **Lumi Education
  Pty Ltd, ABN 45 700 349 015** (2026-07-24). Reconcile with the APP 8 brief §4
  entity framing.
- **Do not store secrets, billing records, account numbers or signed private
  agreements in Git** — reference their access-controlled location only
  (`vendor-evidence/2026-07-17/README.md` closing note).
- **Sign-off.** The privacy adviser confirms this record satisfies INT7 once the
  rows are completed with real, filed evidence.
