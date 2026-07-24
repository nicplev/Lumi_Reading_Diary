# Lumi — ST4S Remediation Plan & Master Checklist

**Version 2.0 — 23 July 2026** (refined against the actual codebase; supersedes the 22 July v1 draft)
**Baseline result:** ST4S Readiness Check, 22 July 2026 — **Not Ready to Submit, Tier 1**
**Owner:** Nic · **Code/config work:** Claude (this file is the shared tracker — Claude updates statuses and the change log at the bottom as work lands)

**The golden rule (kept from v1):** never tick a box because a document or setting *exists*. Tick it only when it is **live, tested, and the evidence is saved** in the evidence folder.

---

## 0. How to read this document

- **ST4S item codes** (S1, A5, HR1, EV…) match the codes in your Readiness Check results, so you can map every task back to the form.
- ⚠️ **Do not confuse tiers with items.** In ST4S question text, "**(T1, T2)**" means the requirement applies to **Tier 1 and Tier 2 products** — it does *not* refer to checklist items T1/T2 (which are about monitoring and patching). In this document, tiers are always written out as "Tier 1 / Tier 2".
- **Who does what:**
  - 🧑 **Nic** — real-world tasks: applications, console/account settings on your own devices and accounts, signing documents, booking things.
  - 🤖 **Claude** — code and repo changes (each lands as a PR and is recorded in the change log).
  - 🤝 **Both** — documents we draft together, then you review, approve and date.
- **Status markers used in tables:** ☐ not started · ◐ in progress · ☑ done (live + evidenced).
- Checkboxes (`[ ]`) inside phases are the working to-do list — tick them on the printed copy; Claude mirrors progress in this file.

---

## 1. Where you stand, in plain English

The Readiness Check came back **Not Ready** because of **19 "Not Ready" items**. On top of that, you answered **Yes to two things that aren't fully built yet** (your Notes-app list): the 14-character password rule (A2) and the "users must accept the latest Privacy Policy & Terms before continuing" requirement. Those two are the top priority — the submission already claims them, so we make them true first.

**Good news from the code review (things v1 of this plan missed):**

1. **The Flutter app already has a real Terms/Privacy consent gate** — versioned, with forced re-acceptance when the version changes (`lib/services/terms_acceptance_service.dart`, current version `2026-07-10`, enforced by the router). Only the **two web portals** (school portal and super-admin portal) are missing it. This is a much smaller job than "build consent from scratch".
2. **A large part of the evidence pack already exists** in `docs/security/` and `docs/privacy/` — a Privacy Impact Assessment, a data-breach response plan with a tabletop exercise record, a vendor & data-flow register, a full pen-test scoping pack with an RFQ email and vendor shortlist, and an in-house pen-test dry run with findings. Phase 4 maps each existing document to the ST4S evidence item it feeds, so you mostly *finish* documents rather than write them.
3. **Automated scanning already runs weekly** — a GitHub Action runs `npm audit`/`pnpm audit` on production dependencies plus a full-history secret scan (gitleaks). Phase 5 extends this to per-deploy scans and saved monthly reports instead of starting from zero.

**The honest bad news:** passwords today are enforced at **6–8 characters** depending on the screen (details in Phase 1), several "organisation" controls (screening, training, offboarding, named security/privacy officers) genuinely don't exist yet, and there is no penetration-test report. Those are exactly what Phases 0–6 fix.

---

## 2. The honesty list — answers to correct before resubmitting

These are answers in the current submission that must not be repeated until the control is real.

| ST4S item | What was answered | What is actually true today (verified in code, 23 Jul 2026) | What makes it true |
|---|---|---|---|
| **A2** — passwords 14+ chars, complexity, hashed/salted per OWASP | "Yes for all users – excluding students" | Hashing is fine (Firebase Auth uses scrypt). Length/complexity is **not**: app signup enforces 8 + upper/lower/digit, school-onboarding wizard 8 with **no** complexity, portal "Create user" only **6**, temp passwords are 12 chars with no symbols. | Phase 1.1 |
| **Privacy + T&Cs** — users must accept the latest versions before continuing | Answered as if implemented | **True in the mobile app** (versioned gate, re-consent on version bump). **Not true in the school portal or admin portal** — no acceptance is captured there at all. | Phase 1.2 |
| **T3** — security patches applied within 14 days / 48 hours if exploited | "Yes (Tier 1, Tier 2)" — Ready | Patching happens, but there is **no documented process and no records** proving the deadlines. In a Full Assessment this claim must be evidenced. | Phase 4 (patch policy EV12) + Phase 5 records |
| **PF51** — file uploads follow OWASP incl. AV scanning | "Yes – majority incl. AV scanning" — Ready (low risk) | Upload validation is strong (type/size/path rules) but there is **no antivirus/malware scanning** of uploaded files. | Either add scanning later or answer "majority, excluding AV" next time. Decide at Phase 7 |
| **S2-type: offline data on devices** (flagged in v1) | — | Offline caches (Hive) on phones/iPads are **not app-level encrypted**. Not in the Not-Ready list, but check what was answered for data-at-rest before resubmitting and answer accurately. | Verify at Phase 7; optional hardening later |

A truthful "No" is always safer than a "Yes" that collapses during the Full Assessment.

---

## 3. Master tracking table — every item from the results

This is the index. Each row points at the phase that fixes it. Claude keeps the Status column current.

| ST4S | Topic in plain words | Result 22 Jul | Fix in | Status |
|---|---|---|---|---|
| S1 | Encryption of data in transit (TLS) | Not Ready | Phase 3 | ☑ |
| S3 | Encryption when customer data is uploaded | Not Ready | Phase 3 | ☑ |
| S4 | Keeping each school's data separated | Ready | — | ☑ |
| S5 | Proper TLS certificates | Ready | — | ☑ |
| S7 | Protection on production servers (HIPS/AV/firewall) | Not Ready | Phase 2.3 | ☐ |
| S8 | Database hardening | Ready | — | ☑ |
| S9 | Separating internet-facing parts from databases | Ready (medium risk) | Later-uplift | ☐ |
| S10 | Documented system-hardening process | Ready (medium risk) | Later-uplift | ☐ |
| S11 | Perimeter controls (firewall/WAF/DDoS…) | Ready (medium risk) | Later-uplift | ☐ |
| S13 | Production data used in dev/test | Ready ("No") | — | ☑ |
| A1 | Unique accounts for all users | Ready (note: extra review later) | — | ☑ |
| A2 | Password strength & storage | **Answered Yes, not true yet** | **Phase 1.1** | ☑ |
| A5 | MFA for admins/support/privileged accounts | Not Ready | Phase 2.2 | ☐ |
| A6 | Role-based access, documented for all systems | Ready (medium risk) | Later-uplift | ☐ |
| A7 | Regular review/revocation of staff & contractor access | Not Ready | Phase 2.4 + Phase 4 | ☐ |
| A10 | Screen lock on the company's own computers | Not Ready | Phase 2.1 | ☐ |
| A11 | Password-reset process quality | Ready (medium risk) | Later-uplift | ☐ |
| A13 | Deny-by-default access | Ready | — | ☑ |
| A16B | Agreements for third-party service accounts | Ready (N/A) | — | ☑ |
| HR1 | Employment screening (WWCC / police checks) | Not Ready | Phase 0.1 + Phase 4 | ☐ |
| HR2 | Security awareness training program | Not Ready | Phase 4 | ☐ |
| HR3 | Same-day access removal when people leave | Not Ready | Phase 4 | ☐ |
| T1 | Continuous monitoring plan (monthly scans, annual pen test) | Not Ready | Phase 0.2 + Phase 5 | ☐ |
| T2 | Centrally managed patching | Not Ready | Phase 4 + Phase 5 | ☐ |
| T3 | Patch deadlines 14 days / 48 hours | Ready — **but see honesty list** | Phase 4 + 5 | ☐ |
| T6 | Incident response plan + incident register | Ready (medium risk) | Phase 4 (EV9) | ☐ |
| T7 | Breach notification to customers | Ready | — | ☑ |
| Q5 | Security testing per industry framework | Ready (medium risk) | Phase 0.2 + Phase 5 | ☐ |
| D3 | Backup restoration tested | Ready | Phase 4 (keep evidence, EV8) | ☐ |
| CC2 | PCI DSS | Ready (N/A — no payments in-product) | — | ☑ |
| GO1 | Named person responsible for cyber security | Not Ready | Phase 0.3 | ☐ |
| GO2 | Named Privacy Officer | Not Ready | Phase 0.3 | ☐ |
| PR1 | Privacy policy free & published | Ready | — | ☑ |
| PR2 | Privacy policy covers all required content | Not Ready | Phase 6.1 | ☐ |
| PR10 | Data shared with third parties beyond permitted cases | Not Ready (answered "Yes") | Phase 6.3 | ☐ |
| PR17 | Sub-processors fully described publicly | Ready (medium risk) | Phase 6.2 | ☐ |
| PF51 | File-upload protections incl. AV | Ready — **but see honesty list** | Phase 7 decision | ☐ |
| SC3 | Child-safety offences | Ready ("No") | — | ☑ |
| SC5 | Non-school users can't contact students | Ready (N/A) | — | ☑ |
| INT7 | Written data agreements with integrated third parties | Not Ready | Phase 6.4 | ☐ |
| AP1 | Vulnerability scan every deployment + monthly | Not Ready | Phase 5 | ☐ |
| AP2 | Mobile app tested per OWASP MASTG | Not Ready | Phase 5.4 | ☐ |
| EV | Evidence documents EV6–EV13 available | Not Ready | Phase 4 | ☐ |

---

# Phase 0 — Start these TODAY (they have waiting periods) 🧑

These cost little effort but have lead times of weeks. Kick them off before anything else.

### 0.1 Apply for your WWCC — fixes HR1
*In plain English: ST4S wants everyone who can touch student data to be screened. For a Victorian company that means a Working With Children Check (and ideally a National Police Check). Processing takes weeks, so apply now.*

- [ ] 🧑 Apply for a Victorian WWCC (Service Victoria, "Employee" type) if you don't hold a current one.
- [ ] 🧑 Optional but stronger: order a National Police Check.
- [ ] 🧑 Record in a restricted HR file (not in git): name, check type, reference number, date, expiry. Keep only the outcome, not the full certificate, in the evidence pack.
- [ ] 🧑 If anyone else (contractor, adviser) can access production data or the repo, list them and repeat.

**Done when:** every person with access to student data has a recorded, current check. → HR1 answer becomes "Yes (Tier 1, Tier 2)".

### 0.2 Book the external penetration test — feeds T1, Q5, AP2, EV10
*In plain English: the one evidence item you cannot write yourself is EV10, a pen-test report. The scoping pack, RFQ email and vendor shortlist are ALREADY WRITTEN in this repo — this is a send-three-emails task.*

- [ ] 🧑 Send `docs/security/PENETRATION_TEST_RFQ_EMAIL.md` to the firms in `docs/security/PENETRATION_TEST_VENDOR_SHORTLIST.md`, attaching `docs/security/PENETRATION_TEST_SCOPING_PACK.md`.
- [ ] 🧑 Pick a vendor, book a date, get the quote approved (this is the main cash cost of ST4S).
- [ ] 🤝 Until the external report exists, keep `docs/security/IN_HOUSE_PENTEST_PLAN.md` + `docs/security/PENTEST_DRYRUN_FINDINGS_2026-07-20.md` as interim evidence of testing activity.
- [ ] 🧑 After the test: fix findings, get the re-test letter, store the report in the evidence pack.

**Done when:** a signed engagement with a date exists (booking), then later the report + re-test (completion).

### 0.3 Appoint yourself in writing — fixes GO1 and GO2
*In plain English: ST4S doesn't require a security department — it requires a NAMED person with defined duties. A one-page signed letter each is enough for a sole founder, plus an external expert you can call.*

- [ ] 🤝 One-page **Security Lead appointment** (Nic) listing the exact GO1 duties: coordinating/reporting on cyber security, security risk management incl. supply chain, improvement activities, awareness & training, incident response.
- [ ] 🤝 One-page **Privacy Officer appointment** (Nic) listing the exact GO2 duties: internal privacy advice, OAIC liaison, handling privacy enquiries/complaints/access & correction requests, keeping the personal-information holdings record (the PIA + vendor register already largely are this), assisting PIAs, measuring performance against the privacy plan.
- [ ] 🧑 Name an external escalation contact for each role (privacy lawyer / security adviser) with contact details.
- [ ] 🧑 Sign, date, save to evidence pack. Put a monthly 30-min "security & privacy review" in your calendar and keep one-line minutes.

**Done when:** both letters are signed and the first monthly review has happened. → GO1/GO2 become "Yes, with all of the specified responsibilities (Tier 1, Tier 2)".

### 0.4 Create the evidence pack
- [ ] 🧑 Private folder (Google Drive/iCloud, **not** the git repo): subfolders `EV6`–`EV13`, `A2-passwords`, `A5-MFA`, `Consent`, `Crypto`, `HR`, `Vendors`, `Scans`, `Baseline`.
- [ ] 🧑 Save the 22 July 2026 Readiness Check results (your screenshots) into `Baseline`.

---

# Phase 1 — Make the two "Yes" answers true 🤖 (code — highest priority)

## 1.1 Passwords: 14+ characters with complexity everywhere — fixes A2

*In plain English: you told ST4S all non-student passwords are 14+ characters with complexity. Today the app asks for 8, the portal accepts 6, and generated temporary passwords are 12 with no symbols. We change every place a password is set, and turn on Firebase's own policy so the rule is enforced server-side, not just by screen validation.*

**Current state (verified in code — this table is the work list):**

| # | Where | File | Today | Target |
|---|---|---|---|---|
| a | Parent signup (app) | `lib/screens/auth/widgets/parent_registration_modal.dart:306` (+ hint texts) | 8 + upper/lower/digit | 14 + upper/lower/digit/symbol |
| b | Teacher signup (app) | `lib/screens/auth/widgets/teacher_registration_modal.dart:284` (+ hint texts) | 8 + upper/lower/digit | same |
| c | School-onboarding admin password (app) | `lib/screens/onboarding/school_registration_wizard.dart:452` | 8 only, **no complexity** | same |
| d | School portal "Create user" | `school-admin-web/src/app/api/users/route.ts:40` + `create-user-modal.tsx:47` | **min 6** | same |
| e | Temp-password generator ×3 (portal bulk import, functions staff onboarding, demo access) | `school-admin-web/src/lib/utils/temp-password.ts:15`, `functions/src/temp_password.ts:18`, `packages/server-ops/src/utils/tempPassword.ts:20` | 12 chars, no symbols | 16 chars incl. ≥1 symbol |
| f | Firebase Auth server-side policy | Firebase Console → Authentication → Settings → Password policy | none | 14 min, require upper+lower+digit+symbol, **Require** mode |

Checklist:

- [ ] 🤖 Update app validators + helper/error text (rows a–c). Keep one shared validator so the rule can't drift between screens again.
- [ ] 🤖 Update portal schema + modal (row d), including the "Min 6 characters" placeholder.
- [ ] 🤖 Update all three temp-password generators (row e) — 16 chars with a guaranteed symbol from a safe set (e.g. `!@#$%^*-_?`). ⚠️ These must satisfy the console policy **by construction**, because passwords set through the Admin SDK bypass the console policy check.
- [ ] 🤖 Cleanup task while we're here: temp passwords for bulk staff import are stored **in plaintext** in the admin-only `staffCredentials` subcollection (`school-admin-web/src/lib/firestore/users.ts:171`). Delete the stored credential once the user first signs in / changes password, so plaintext secrets don't live forever.
- [ ] 🧑 Turn on the Firebase Console password policy (row f) — screenshot for evidence.
- [ ] 🤝 Test matrix: new parent signup, new teacher signup, school-onboarding wizard, portal create-user, bulk staff import temp password works at first login, forced change on first login still works, Firebase-hosted **password reset page** rejects a 13-char password (the reset flow uses Firebase's hosted page, so the console policy is what protects it — verify it does).
- [ ] 🤝 Note for evidence: existing users are unaffected until they next change their password (Firebase doesn't retro-lock accounts). That's fine — record it. Students remain excluded (they don't have passwords), same as the "excluding students" answer, which ST4S accepts with a note.
- [ ] 🧑 Save evidence: console screenshot, PR links, short screen-recording of a weak password being rejected in each surface.

**Done when:** a 13-character or symbol-less password is rejected on every surface in the table, and demo/review accounts still log in. → A2 stays "Yes for all users – excluding students", but now it's true.

## 1.2 Terms & Privacy acceptance in the web portals — makes the Privacy/T&C answer true

*In plain English: the mobile app already blocks anyone who hasn't accepted the CURRENT version of the Terms & Privacy Policy, and re-blocks them when the version changes. The school portal and admin portal don't ask at all. We copy the app's pattern to the portals.*

**Already done (keep as evidence):** `lib/services/terms_acceptance_service.dart` (version `2026-07-10`, fields `termsAccepted/-At/-Version/-Platform` on the user doc) + router gate at `lib/core/routing/app_router.dart:222` + `lib/screens/auth/terms_acceptance_screen.dart` (unchecked-by-default checkbox, links to both documents).

- [ ] 🤖 **School portal:** acceptance interstitial after login for teachers and school admins — same user-doc fields, server-checked (session/auth-context in `school-admin-web/src/lib/auth/`), blocking all authenticated pages until the current version is accepted; re-blocks when the version constant is bumped.
- [ ] 🤖 **Super-admin portal:** same gate (cheap once the pattern exists; it's an internal tool, so this is belt-and-braces).
- [ ] 🤖 Keep ONE version constant per document surface and a checklist rule: the app constant and portal constant must be bumped together (they cover the same legal documents at `.../legal/privacy` and `.../legal/terms`).
- [ ] ⏸️ **Sequencing:** do NOT bump the version yet. Phase 6.1 rewrites the Privacy Policy for PR2 — bump once, after that lands, so every user re-accepts a single time (Phase 6.5).
- [ ] 🤝 Test each role: teacher first login, admin first login, old-version user forced to re-accept, decline → signed out, deep link → still gated.
- [ ] 🧑 Evidence: screen recordings + a Firestore export showing acceptance records with versions and server timestamps.

**Done when:** no user type — app or portal — can use Lumi without having accepted the current versions.

---

# Phase 2 — One afternoon on your Mac and your accounts 🧑

*In plain English: four Not-Ready items (A10, A5, S7, A7) are really about YOUR laptop and YOUR admin logins, not the product. This is a single sitting of settings work, then a short write-up in Phase 4.*

### 2.1 Screen lock — fixes A10
- [ ] 🧑 System Settings → Lock Screen: screen saver/display off at ≤ 15 min idle; **require password immediately** after sleep or screen saver.
- [ ] 🧑 Confirm FileVault is ON (Privacy & Security → FileVault) — also feeds the device standard.
- [ ] 🧑 Check every machine used for Lumi work (laptop, the iPad used for kiosk testing — auto-lock ≤ 15 min there too).
- [ ] 🧑 Evidence: settings screenshots per device. The one-page device standard is written in Phase 4.

### 2.2 MFA on every privileged account — fixes A5
- [ ] 🧑 Inventory and switch on MFA (prefer passkeys/authenticator over SMS) for: Google account(s) behind Firebase/GCP, GitHub, Apple Developer, Google Play Console, Cloudflare, domain registrar for lumi-reading.com, the support/admin mailboxes, password manager.
- [ ] 🧑 Verify both portals enforce MFA for privileged human logins (school-admin MFA shipped earlier — see `docs/ADMIN_TOTP_MFA_RUNBOOK.md`; confirm the super-admin portal path is covered and close any gap).
- [ ] 🧑 Store recovery codes in the password manager, never in the repo.
- [ ] 🧑 Evidence: per-account screenshots of MFA enforced. → A5 becomes "Yes – all of the above (Tier 1, Tier 2)".

### 2.3 Endpoint & server protection — fixes S7
*The production "servers" are Google-managed (Cloud Run / Cloud Functions / Firestore — Google provides the infrastructure intrusion protection), and the ST4S question also covers "all end points", i.e. your Mac. Minimum for Ready is "Yes – some of the above", which this achieves honestly.*
- [ ] 🧑 macOS: turn ON the application firewall; confirm Gatekeeper/XProtect active (default); FileVault from 2.1.
- [ ] 🧑 Optional uplift: a lightweight EDR/AV product on the Mac.
- [ ] 🤝 One paragraph in the hardening doc (Phase 4): which protections are Google-managed vs. Lumi-managed (shared-responsibility statement + link to Google's security docs).
- [ ] Evidence: screenshots + the paragraph. → S7 becomes "Yes – some of the above".

### 2.4 Access register — fixes A7 (with the policy in Phase 4)
- [ ] 🤝 One-page register: every person (you, any contractor/adviser) × every system (GCP/Firebase, GitHub, portals, mailboxes, stores, registrar, Cloudflare) × access level × date last reviewed.
- [ ] 🧑 Calendar: annual review + review on any role change. First review = now (that's your first record).
- [ ] Evidence: the register with review date. → A7 becomes "Yes (Tier 1, Tier 2)".

---

# Phase 3 — Prove the encryption story (S1, S3) 🤖🧑

*In plain English: these two "Not Ready" results are mostly an answering problem — the option chosen described weaker crypto (SHA-224, TLS "or above" ambiguity) than the platform actually uses. Google's stack is TLS 1.2+ with modern ciphers and AES-256 at rest. We scan every public endpoint, fix anything weak, write a one-page "crypto profile", and then the truthful answer meets the minimum.*

**Endpoint inventory to scan (verified from config):**

| Endpoint | What it is |
|---|---|
| `https://lumi-reading.com` | marketing site (Firebase Hosting) |
| `https://lumi-school-admin-au.web.app` | school portal (Next.js SSR on Cloud Run) |
| `https://lumi-dev-admin-au.web.app` | super-admin portal |
| `https://lumi-ninc-au.web.app` | default Firebase Hosting site |
| `https://lumistatus.aged-morning-985b.workers.dev/status` | Cloudflare status worker (public, non-personal data) |
| `validateComprehensionAudioMedia` HTTPS URL (australia-southeast1) | the one direct-HTTP Cloud Function |
| Firebase Auth / Firestore / Storage APIs | Google-managed endpoints the app talks to |

- [ ] 🤖 Run a TLS scan (e.g. `testssl.sh`, or Qualys SSL Labs for the public sites) against each row; record the **weakest accepted protocol and cipher** per endpoint.
- [ ] 🤖 If anything accepts below TLS 1.2, fix it (most likely candidate: the workers.dev endpoint — if it can't be pinned to TLS 1.2+, note that it serves only a public status banner, no customer data, and consider moving it behind a custom domain with min-TLS set).
- [ ] 🤝 Write the one-page **crypto profile** for the evidence pack: TLS 1.2+ only (scan results attached), AES-256 at rest (Google-managed), passwords hashed with scrypt (Firebase Auth), certificates SHA-256 ECDSA/RSA-2048 (from the scans).
- [ ] 🧑 Evidence: scan outputs + the one-pager.

**Done when:** every endpoint carrying customer data proves TLS 1.2+ only. → S1 and S3 can truthfully take the option matching "Encryption: AES-128+ / Hashing: SHA-256+ / TLS 1.2 or above only (Tier 1)".

---

# Phase 4 — The document pack ✍️ 🤝 (one writing sprint)

*In plain English: ST4S's Full Assessment asks for eight named documents (EV6–EV13) plus the HR and patching policies behind several Not-Ready answers. You already have more than half the raw material. This table is the sprint plan — each doc is a focused 1–3 page write-up, drafted by Claude, reviewed/signed/dated by you.*

| Doc | ST4S items it fixes | What already exists in the repo | Gap to close | Status |
|---|---|---|---|---|
| **EV6** Information Security Policy | Q7, EV, underpins GO1 | Nothing formal (hardening checklists exist) | Write 4–8 pages: management commitment, legal compliance, roles (GO1/GO2 letters referenced), least-privilege + MFA, reporting duty, annual review | ☐ |
| **EV7** Business Continuity Plan | EV | Nothing | Write: what schools do if Lumi is down (status banner runbook `docs/status-messages.md` feeds this), comms, workarounds, recovery priorities | ☐ |
| **EV8** Disaster Recovery Plan | EV, D3 evidence | Backup behaviour known; D3 answered Yes | Write: RTO/RPO, Firestore PITR/backup steps, restore runbook; run + record one restore drill | ☐ |
| **EV9** Incident Response Plan | EV, T6 uplift, T7 | `docs/privacy/DATA_BREACH_RESPONSE_AND_TABLETOP.md` (incl. tabletop record!) | Uplift to full IRP + add an **incident register template** with every T6 field: date occurred, date discovered, description, actions taken, person reported to | ☐ |
| **EV10** Penetration Testing Report | EV, T1, Q5, AP2 | Scoping pack, RFQ, shortlist, in-house dry-run findings | External test from Phase 0.2 | ☐ |
| **EV11** Vulnerability Assessment Reports | EV, T1, AP1 | Weekly CI audits run but reports aren't saved | Phase 5 makes scans produce **saved monthly reports** + a findings register | ☐ |
| **EV12** Patch Management Process | EV, T2, T3 | Practice exists (Dependabot-less audits, manual updates) | Write: sources watched (GitHub advisories, Firebase/Flutter releases, macOS), deadlines **14 days / 48 hours if exploited**, verification that patches applied & stay applied, patch register | ☐ |
| **EV13** Secure SDLC | EV, Q5 | `docs/privacy/RELEASE_PRIVACY_SECURITY_REVIEW.md` (release gate), branch→PR→review→CI workflow is real | Write it down as a lifecycle: design review → PR review → CI tests/rules tests → release gate → rollback | ☐ |
| **HR pack** (screening, training, offboarding) | HR1, HR2, HR3 | Nothing | 3 short docs: screening standard (WWCC per Phase 0.1); annual training program (identify who/when/how + the 7 content bullets from HR2 — a yearly self-run course with dated completion records is acceptable for a sole founder); offboarding checklist with **same-day** revocation (immediate if malicious) using the Phase 2.4 register | ☐ |
| **Access control policy** | A6, A7, A13 | RBAC is real in code/rules | 1–2 pages: role model (parent/teacher/school-admin/super-admin), deny-by-default, review cadence | ☐ |
| **Monitoring plan** | T1 | Weekly CI security workflow | 1 page: monthly vuln scans (Phase 5), annual pen test (Phase 0.2), risk-based triage of findings | ☐ |
| **Device standard** | A10 | Phase 2.1 settings | Half page: auto-lock ≤15 min, FileVault, auto-updates, no shared accounts + device register | ☐ |

- [ ] 🤝 Draft order (dependencies first): EV6 → HR pack → EV12 → monitoring plan → EV9 → EV13 → access policy → device standard → EV7 → EV8.
- [ ] 🧑 You review/sign/date each; save PDFs to the evidence pack. Keep sources in `docs/` (they're good repo docs too — nothing personal goes in git).

**Done when:** every row is ☑ and signed. → EV becomes "Documentation is available and can be provided"; Q7, HR1–3, T1, T2, A7 answers flip to Yes.

---

# Phase 5 — Automate the scanning 🤖 (AP1, AP2, T1, T2, Q5, EV11)

*In plain English: ST4S wants scans on every deployment plus at least monthly, with reports you can show. Weekly dependency audits already run in CI — we add per-deploy checks, a monthly web scan, a monthly saved report, and a mobile-app assessment.*

**Already in place (verified):** `.github/workflows/security-review.yml` — weekly `npm audit`/`pnpm audit` (high severity, prod deps) + rules tests; `.github/workflows/secret-scan.yml` — gitleaks full-history secret scan.

- [ ] 🤖 **Per-deploy scan (AP1 "upon each deployment"):** add a dependency-audit step to the deploy path for functions and portals (predeploy hook or deploy script), and to `scripts/flutter-build.sh` for app releases (osv-scanner covers `pubspec.lock` as well as npm lockfiles).
- [ ] 🤖 **Dependabot:** add `.github/dependabot.yml` (npm, pub, GitHub Actions) so patches arrive as PRs — this is the "centrally managed" evidence for T2.
- [ ] 🤖 **Monthly web scan:** OWASP ZAP baseline scan against the three public sites + portal login pages, scheduled monthly in CI; save the HTML report as a build artifact and file it in the evidence pack (this is EV11's monthly report).
- [ ] 🤖 **Findings register:** one markdown table (finding, severity, owner, decision, fixed date) — feeds T1's "risk-based approach" and EV11.
- [ ] 🤝 **Mobile (AP2):** run a MASVS/MASTG self-assessment checklist against the Flutter app + a MobSF static scan of the built IPA/APK; file both. The external pen test (Phase 0.2) covers the rest → answer at least "security testing partially satisfies the guidance".
- [ ] 🧑 Evidence: first saved reports from each scanner.

**Done when:** a deploy without a scan is impossible, a monthly report lands in the evidence pack automatically, and the register exists. → AP1 "Yes – meets all requirements", T1 "Yes", T2 "Yes – all of the above", AP2 at least "partially".

---

# Phase 6 — Privacy content & third parties ✍️ (PR2, PR17, PR10, INT7)

### 6.1 Rewrite the Privacy Policy to cover every PR2 bullet
*File: `school-admin-web/src/app/legal/privacy/page.tsx` (the app links to this same page). Raw material: `docs/privacy/PRIVACY_IMPACT_ASSESSMENT.md`, `docs/privacy/VENDOR_DATA_FLOW_REGISTER.md`, `docs/privacy/APP_8_CROSS_BORDER_DISCLOSURE_LAWYER_BRIEF.md`.*

- [ ] 🤖 Draft covering, explicitly and in order: (1) kinds of personal information collected; (2) how it's collected and held; (3) purposes of collection/use/disclosure; (4) how to access & correct it; (5) how to complain and how complaints are handled; (6) whether info goes overseas; (7) which countries (Australia primary — australia-southeast1; name the countries for push notifications (Apple/Google) and any US-touching sub-services per the vendor register).
- [ ] 🧑 Have your privacy adviser sanity-check it (you have the APP 8 brief for exactly this).
- [ ] 🤖 Update the `lastUpdated` date. **Do not bump the consent version until 6.5.**

### 6.2 Publish the full sub-processor table — upgrades PR17
- [ ] 🤖 Add to the policy (or a linked page): for each sub-processor — name, contact/website, data types, purpose, lawful basis, processing/storage countries. Source: `docs/privacy/VENDOR_DATA_FLOW_REGISTER.md`. → PR17 becomes "Yes – all of the above (Tier 1)".

### 6.3 Data-sharing audit — fixes PR10
*You answered "Yes, we share user data outside the permitted cases" — almost certainly a misreading. Sharing with processors (Google/Firebase) to run the service is NOT "sharing with third parties" in this question's sense.*
- [ ] 🤝 List every flow where user data leaves Lumi's systems; confirm each fits a permitted case (consent / legal requirement / service operation via processors). Book-lookup APIs get ISBN/title only — no student data (verify + note).
- [ ] 🧑 If nothing falls outside the permitted cases (expected): answer becomes "No (Tier 1, Tier 2)". Keep the audit note as evidence.

### 6.4 Sub-processor agreements — fixes INT7
- [ ] 🧑 Record acceptance of each vendor's data-processing terms: Google Cloud/Firebase DPA (accepted in console — export/screenshot it), Cloudflare DPA, Apple & Google developer agreements, any email provider. File copies in `docs/privacy/vendor-evidence/` + the evidence pack.
- [ ] 🤝 Add a one-line rule to EV6: no new vendor/SDK until the register + DPA check is done. → INT7 becomes "Yes (Tier 1, Tier 2)".

### 6.5 The single consent re-acceptance event
- [ ] 🤖 After 6.1/6.2 ship: bump the terms/privacy version constants (app + portals from Phase 1.2) so **every user re-accepts the new policy once**.
- [ ] 🧑 Evidence: acceptance-record export after the bump.

---

# Phase 7 — Re-run the Readiness Check ✅

- [ ] 🤝 Walk this file top to bottom; anything not ☑ keeps its honest current answer.
- [ ] 🧑 Decide the two judgment calls from the honesty list: PF51 (add AV scanning vs. answer "majority, excluding AV") and the data-at-rest answer re offline caches.
- [ ] 🧑 Re-run the check in a fresh session. Expected answer changes, in one view:

| Item | New answer (only if its phase is ☑) |
|---|---|
| S1, S3 | The TLS 1.2-only / SHA-256+ option (Tier 1) |
| S7 | Yes – some of the above |
| A2 | Yes for all users – excluding students (now true) |
| A5 | Yes – all of the above |
| A7, HR1, HR3, INT7 | Yes (Tier 1, Tier 2) |
| A10 | Yes, all of the above |
| HR2 | Yes – all of the above |
| T1, AP1 | Yes – meets all requirements |
| T2 | Yes – all of the above |
| GO1, GO2 | Yes, with all of the specified responsibilities |
| PR2 | Yes – includes all of the above |
| PR10 | No |
| AP2 | Yes – at least partially satisfies |
| EV | Documentation is available and can be provided |
| Privacy/T&C consent | Yes — truthfully, on every surface |

- [ ] 🧑 Save the new result to the evidence pack next to the baseline.

---

## Later uplift — "Ready" items you can upgrade when time allows

Not needed for a Ready outcome; each removes a "medium risk" note in the Full Assessment.

| Item | One-line action |
|---|---|
| S9/S11 | Document network segregation + which perimeter controls Google provides; consider WAF/App Check enforcement rollout |
| S10 | Fold the existing hardening checklists into one reviewed-annually hardening doc |
| A6 | Extend the access-control policy to explicitly cover *every* system, not just the product |
| A11 | Add identity verification + forced first-use change to every reset path (partially exists via `mustChangePassword`) |
| T6 | Covered once EV9's incident register is in use — then answer "Yes – all of the above (Tier 1)" |
| Q5 | After the pen test + ZAP + SSDLC doc, answer "fully satisfies" |
| PF51 | Add malware scanning for uploads (e.g. scanning pipeline on Storage) |
| A1/A2 student exclusion | Keep the note that students authenticate without passwords; ST4S reviews this in the Full Assessment |
| Offline caches | Encrypt Hive boxes with a Keychain/Keystore-held key (real hardening, not required for Tier 1 Ready) |
| Portal idle timeout | Portals have a 5-day absolute session, no idle logout; consider a shorter idle timeout for admin surfaces |

---

## Claude's change log

*Every code/config change made under this plan gets a row. Claude updates this table and the Status columns above as PRs land.*

| Date | Phase/Item | Change | PR | Status |
|---|---|---|---|---|
| 2026-07-23 | — | Plan v2: rewritten against verified codebase state; master table + phased checklist created | — | ☑ |
| 2026-07-24 | S4/A13 | F-01/F-02/F-03 create-time field-forgery rules gaps found, fixed + deployed to prod (`firestore:rules`); emulator regression tests added (`security_poc.rules.test.js`). Strengthens S4/A13. | #520 | ☑ |
| 2026-07-24 | A2 (Phase 1.1) | Passwords enforced at 14+/complexity everywhere: temp-pw generators 12→16+symbol, portal Add-Staff min-6→14, shared app+portal validators; Firebase console password policy set to Require/min-14/all-4-classes. Portal + `processStaffOnboardingEmail` deployed. A2 now true across all surfaces. | #554 | ☑ |
| 2026-07-24 | Q5 | Low-severity hardening: SAST-01 (super-admin MFA-crypto GCM `authTagLength` pin + truncated-tag rejection) and F-07 (books/lookup strict ISBN validation + per-user rate limit) fixed. Each deploys with its portal. | #557 + F-07 | ☑ |
| 2026-07-24 | A5/S4/A13 | F-04 defence-in-depth: fail-closed `assertSuperAdmin` guard added inside the 5 destructive super-admin server-ops (were single-layer, gated only by the portal route). Deployed via admin-deploy. | #561 | ☑ |
| 2026-07-24 | EV11 / EV10 | Vulnerability Assessment Report produced (`docs/security/VULNERABILITY_ASSESSMENT_REPORT_2026-07-24.md`) — full findings, remediation + verification, ST4S mapping. Satisfies EV11; interim input to EV10 (independent external pen test still outstanding). | — | ☑ (EV11) |
| 2026-07-24 | S1/S3/S5 (Phase 3) | Authorised passive TLS scan of all 6 public endpoints: TLS 1.2+ only (1.0/1.1 rejected), TLS 1.3 + AES-GCM, valid CA certs (Google Trust Services / Let's Encrypt), HSTS. Crypto profile: `docs/security/TLS_CRYPTO_PROFILE_2026-07-24.md`. S1/S3/S5 can take the strong TLS option. | — | ☑ |
| 2026-07-24 | S11 / Phase 4 | Portal security headers (nosniff / X-Frame-Options / Referrer-Policy) deployed to both portals + marketing (#569). Five technical evidence docs **drafted** in the evidence-pack worktree (pending sign-off): EV13 SSDLC, Monitoring Plan (T1), Access Control Policy (A6/A7/A13), EV12 Patch Management (T2/T3), EV9 Incident Response (T6/T7). | #569 | ◐ drafts |

---

## Appendix — verified code facts this plan is built on (23 Jul 2026)

- **Password enforcement today:** app signup 8 + upper/lower/digit (`parent_registration_modal.dart:306`, `teacher_registration_modal.dart:284`); school wizard 8 only (`school_registration_wizard.dart:452`); portal create-user min 6 (`api/users/route.ts:40`); temp-password generators 12 chars, no symbols, in 3 copies (`school-admin-web/src/lib/utils/temp-password.ts`, `functions/src/temp_password.ts`, `packages/server-ops/src/utils/tempPassword.ts`); staff temp credentials stored plaintext in `staffCredentials` (admin-only); seeded demo/review scripts already require ≥16 chars; no in-app change-password screen (resets via Firebase-hosted links); demo passwords rotate nightly via 40-byte throwaway.
- **Consent today:** full versioned gate in the app (`terms_acceptance_service.dart`, version `2026-07-10`; router redirect `app_router.dart:222`); fields on user doc incl. platform + server timestamp; **no consent capture in either web portal**; legal pages live at `lumi-school-admin-au.web.app/legal/{privacy,terms}` (updated 15 Jul / 28 Jun 2026); marketing site has no legal pages.
- **Public endpoints:** 4 Firebase Hosting sites (project `lumi-ninc-au`, australia-southeast1 backends), `lumi-reading.com`, Cloudflare status worker (`lumistatus.aged-morning-985b.workers.dev`), one direct-HTTP function (`validateComprehensionAudioMedia`); everything else is SDK-mediated Google endpoints.
- **Scanning today:** weekly `security-review.yml` (npm/pnpm audit, high, prod deps + rules tests), `secret-scan.yml` (gitleaks v8.30.1, full history); **no** Dependabot, osv-scanner, CodeQL, or web scanning; `scripts/audit-function-health.sh` covers runtime health, not vulnerabilities.
- **Sessions:** both portals 5-day absolute session cookies, revocation-aware, no idle timeout (school portal re-validates a tab hidden ≥60 s on refocus); mobile app has no idle logout.
- **Existing doc base:** `docs/security/` (hardening checklist, pen-test scoping pack + RFQ + vendor shortlist, in-house pen-test plan + dry-run findings, residency/cost/ops audits) and `docs/privacy/` (PIA, breach response + tabletop, release privacy/security gate, responsible-AI policy, vendor & data-flow register, APP 8 brief, ST4S prep).
