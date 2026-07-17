# Google/Firebase and Twilio SendGrid evidence pack

**Captured:** 17 July 2026
**Purpose:** dated source material for Lumi's vendor review, APP 8 assessment,
school due diligence and later Australian privacy-counsel sign-off.

This folder preserves the official public terms that were current when the
review was performed. Vendor terms change. The live source must be checked
again before legal approval, before launch, after a material vendor change and
at least annually. The snapshots are evidence, not legal advice and not proof
of which legal entity accepted which agreement for Lumi's accounts.

## Archived sources

| Local evidence | Official source | SHA-256 |
| --- | --- | --- |
| `OAIC_APP8_Guidelines_v1.3_October_2025.pdf` | https://www.oaic.gov.au/__data/assets/pdf_file/0036/256959/APP-Guidelines-Chapter-8-Cross-border-disclosure-of-personal-information-October-2025-v1.3.PDF | `37b3f5f47ceb91591a7073622ea306a90747f0b3a7b77d49a99eb5c0d03ee047` |
| `raw/google-cloud-data-processing-addendum.txt` | https://cloud.google.com/terms/data-processing-addendum | `e2ed8c0d210334f5713cfda7b8ec70149584440a5f734c0ecaadffcad7abb312` |
| `raw/google-cloud-subprocessors.txt` | https://cloud.google.com/terms/subprocessors | `7f0be25795ade6816cd82e40afb301f8405a5e4b147bf5c34acec7c5be66b2f9` |
| `raw/google-cloud-service-specific-terms.txt` | https://cloud.google.com/terms/service-terms | `b355d64f16b5d028dc4a0e60f8037cff4ba4f5d9d3dc64b01efd3ebbabb462c6` |
| `raw/firebase-data-processing-security-terms.txt` | https://firebase.google.com/terms/data-processing-terms | `77da8560e06577c99f426c84dfda275bff45512b9cc944882d9d6a6fe6383702` |
| `raw/firebase-terms-of-service.txt` | https://firebase.google.com/terms | `b3a4382db2bc011f51e920961434b275c2d4bd34ef3f2428f823f0c15fd57763` |
| `raw/twilio-data-protection-addendum.txt` | https://www.twilio.com/en-us/legal/data-protection-addendum | `968399a58d851b2fef085f949423a9c857ef0ad0d573ff8256129cd23fcfb3bd` |
| `raw/twilio-subprocessors.txt` | https://www.twilio.com/en-us/legal/sub-processors | `0975bd97f6ff52d703341caa10da3ffc1829f950a66061fe083417fce740a041` |
| `raw/twilio-security-overview.txt` | https://www.twilio.com/en-us/legal/security-overview | `dbea3413836fc6c77a0ea4bfec5046ae643c69ae8b2c67601daf6e3f262b2331` |

The text files were mechanically converted from HTTP response snapshots
obtained directly from the named official HTTPS locations. Dynamic scripts and
embedded website configuration were intentionally removed: they are not legal
terms and would introduce third-party website tokens into Lumi's repository.
The source URL, capture date and transformed-file hash make this limitation
explicit; counsel must recheck the live page. The OAIC file is the unmodified
official 16-page PDF, version 1.3 dated October 2025.

## Findings established by the public terms

### Google Cloud and Firebase

- Google Cloud's current Data Processing Addendum is incorporated into the
  applicable agreement, treats Google as processor, restricts access to what is
  necessary for customer instructions, requires confidentiality and written
  subprocessor obligations, and states that Google remains liable for
  subcontracted obligations.
- It permits processing in countries where Google or its subprocessors maintain
  facilities, subject to any service-specific data-location commitment.
- Google commits to prompt incident notice without undue delay, customer
  deletion functionality, a recovery period and an outside deletion period of
  up to 180 days in the circumstances described by the DPA.
- Google's public subprocessor list includes multiple technical-support
  countries. For ordinary GCP technical support, the page says customer data is
  accessed only if the customer elects to share it in a support case. Lumi must
  continue to redact/minimise support material.
- Firebase has its own Data Processing and Security Terms for covered Firebase
  services. Firebase's terms page determines whether a service is governed by
  those terms or the Google Cloud agreement. A lawyer should assess Lumi's
  actual service-by-service combination, not assume one document covers every
  SDK merely because it is branded Firebase.

### Twilio SendGrid

- Twilio's April 2026 DPA includes the Australian Privacy Act 1988 in its
  definition of applicable data-protection law and applies to SendGrid
  customer content.
- The DPA says SendGrid content is deleted or returned at the customer's
  election on termination, while SendGrid backup content is automatically
  deleted one year after termination. This is longer than Lumi's intended
  operational email minimisation and must be considered by counsel.
- Twilio's current subprocessor page identifies DataBank, Lumen and Digital
  Realty as SendGrid infrastructure/storage subprocessors in North America and,
  for Digital Realty, the EU. Twilio Inc. may process for all services in the
  USA. SendGrid is therefore a cross-border service for Lumi.
- Lumi currently intends SendGrid for adult/school transactional messages only.
  Child names, reading details, comments and audio must remain out of email
  bodies, subject lines, metadata and attachments unless a separately approved
  necessity and secure method exists.

## Evidence still requiring a human/account action

Public terms do **not** prove the contracting party, billing country or date on
which Lumi accepted them. Before counsel signs off, retain outside the public
source repository in an access-controlled legal folder:

- [ ] Google Cloud/Firebase account or billing record naming the Lumi legal
  entity and showing the applicable online/offline agreement.
- [ ] Twilio SendGrid account record naming the Lumi legal entity and the terms
  incorporated into that account.
- [ ] Screenshots or exports of the current security/privacy notification
  addresses and subprocessor-change notification subscriptions.
- [ ] Any negotiated order form, support plan, DPA amendment or school-required
  addendum.
- [ ] Counsel's conclusion on whether each flow is a disclosure under APP 8 or
  remains a use under Lumi's effective control, and which APP 8.2 exception, if
  any, is relied on.

Do not place signatures, billing records, account numbers or private negotiated
agreements in this Git repository. Store those in an encrypted, access-limited
legal evidence location and reference their location from the approval record.
