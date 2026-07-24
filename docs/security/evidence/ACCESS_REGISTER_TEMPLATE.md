# Access Register (Template)

**ST4S item:** A7 (access review / revocation)
**Related:** A6/A13 (access control — `ACCESS_CONTROL_POLICY.md`), HR1/HR3
(`HR_SECURITY_PACK.md`), A10 (`DEVICE_STANDARD.md`)
**Version:** 0.1 DRAFT · **Date:** 2026-07-24
**Status:** Draft template for review — not yet populated, not yet signed

---

## 1. Purpose and scope

The access register is the single authoritative list of **who has access to
which system, at what level, and when that access was last reviewed**. It is the
driving artefact for A7 (periodic access review) and for HR offboarding
(`HR_SECURITY_PACK.md` §4 — a leaver's rows are exactly what must be revoked).
`ACCESS_CONTROL_POLICY.md` §9 names this register as a required standing document;
this file is its template and cadence.

Scope: every **human** principal (today: the director; on engagement: any
contractor or adviser) against every system that can reach Lumi code, the
production project, or student data. Application end-users (parents, teachers,
school admins) are **not** in this register — their access is governed
server-side by the security rules and membership documents
(`ACCESS_CONTROL_POLICY.md` §2–3) and reviewed through the membership/rollover
cadence, not here. This register is the **privileged / operator** access list.

**Truthfulness note.** This is a **template**. The rows below are illustrative
placeholders showing the required shape; the register is not populated and no
first review has been performed. It must not be submitted as A7 evidence until
Nic populates it with real principals and completes the first dated review. No
passwords, tokens, keys, MFA seeds, or personal identifiers appear here — the
register records *that* access exists and its level, never the credential itself.

## 2. What goes in the register

- **One row per (person × system).** A person with access to five systems has
  five rows (or one row with per-system columns — see §4 for the matrix form).
- **Access level**, using least-privilege language for that system (e.g. Owner /
  Editor / Viewer for GCP IAM; Org-Owner / Admin / Write / Read for GitHub;
  Account-Admin / App-Manager for the app stores; super-admin / none for the
  portals).
- **Business justification** — why this person needs this level (the
  least-privilege test).
- **MFA status** — whether MFA is enforced on that account (privileged accounts
  must be MFA-on per `ACCESS_CONTROL_POLICY.md` §6).
- **Date granted** and **date last reviewed** — the two dates A7 turns on.

The register records **no secrets**: no passwords, API tokens, service-account
keys, recovery codes, or MFA seeds. Those live in the password manager / secret
store; the register only asserts that access exists and at what level.

## 3. Systems in scope

Every system below is a place privileged access must be tracked. Populate a row
per person for each that applies.

| System | What it controls | Access-level vocabulary |
|---|---|---|
| **GCP / Firebase** (`lumi-ninc-au`) | Production project — Firestore, Storage, Functions, Auth, config, billing | IAM roles (Owner / Editor / specific roles); least-privilege |
| **GitHub** (repo/org) | Source code, CI/CD, deploy trust (WIF/OIDC), secrets | Org-Owner / Admin / Write / Read; token & SSH-key holders |
| **Apple Developer** | iOS signing, App Store Connect, TestFlight | Account-Holder / Admin / App-Manager / Developer |
| **Google Play Console** | Android app publishing, signing | Account-Owner / Admin / release permissions |
| **School admin portal** (`school-admin-web`) | School staff/admin operational access | via membership docs / super-admin (portal is not auto-deployed) |
| **Super-admin portal** (`admin/`) | Cross-tenant Lumi operations (`/superAdmins/{uid}`) | super-admin (Firestore doc, MFA-enforced) / none |
| **Marketing site** (`marketing-site/`) | Public site + demo/onboarding intake | deploy/hosting access |
| **Support / admin mailboxes** | `support@` and the demo/review operational mailboxes | Owner / delegated access |
| **Domain registrar** | Domain ownership + DNS control (registrar of record) | Account-Owner / delegate |
| **Cloudflare** | Edge / status worker (`status` banner) + any DNS/proxy | Account-Owner / member / API-token holders |
| **Password manager** | Custody of all the above secrets + recovery keys | Vault owner / member |
| **(Add any other)** | e.g. SendGrid, Twilio, analytics, error tracking, billing entity | per-system |

> Sub-processors/vendors (SendGrid, Twilio, etc.) that hold operator credentials
> should each get a row if a human logs into them; pure server-to-server vendors
> are tracked in the vendor register, not here — but any **console login** a human
> holds belongs in this register.

## 4. Register template (matrix form)

One row per person; a cell per system with the access level (or "—" for none).
Keep a companion "detail" row/tab per person for granted/reviewed dates and MFA
status where the matrix gets tight.

| Person (named) | Role | GCP/Firebase | GitHub | Apple Dev | Google Play | School portal | Super-admin portal | Mailboxes | Domain registrar | Cloudflare | Password mgr | MFA on all? | Last reviewed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Nic (Director) | Owner / all | Owner | Org-Owner | Account-Holder | Account-Owner | super-admin | super-admin | Owner | Account-Owner | Account-Owner | Owner | (confirm) | 2026-…-… |
| _(contractor/adviser)_ | _scoped role_ | _least-priv_ | Read/Write | — | — | — | — | delegated? | — | — | member | (confirm) | — |

### 4.1 Per-system detail (alternative long form)

If the matrix is unwieldy, use one row per (person × system):

| Person | System | Access level | Business justification | MFA enforced? | Date granted | Date last reviewed | Reviewer | Action (keep / reduce / revoke) |
|---|---|---|---|---|---|---|---|---|
| Nic | GCP/Firebase `lumi-ninc-au` | Owner | Sole operator | (confirm) | — | — | — | keep |
| Nic | GitHub | Org-Owner | Sole maintainer | (confirm) | — | — | — | keep |
| … | … | … | … | … | … | … | … | … |

## 5. Review cadence (A7)

| Trigger | Action | Frequency |
|---|---|---|
| **Annual review** | Walk every row: confirm the person still needs the access at that level; reduce to least privilege or revoke; confirm MFA; stamp "date last reviewed" and reviewer | **Annual** |
| **On role change** | Grant/reduce access for the new role same-day; add/adjust rows | On change |
| **On joiner** | Add rows only after HR1 screening + HR2 training + device standard met (`HR_SECURITY_PACK.md`, `DEVICE_STANDARD.md`); default least privilege | On event |
| **On leaver / for-cause** | Revoke every row same-day (immediately if malicious) per `HR_SECURITY_PACK.md` §4; the register is the checklist | On event |
| **Monthly IAM spot-check** | The GCP/Firebase IAM + deploy-identity subset is already reviewed monthly (`ACCESS_CONTROL_POLICY.md` §8); reconcile findings back into this register | Monthly (IAM subset) |

The **annual full-register review** is the A7 evidence: a dated pass where every
row's "last reviewed" is stamped and each access is confirmed keep/reduce/revoke
by a named reviewer.

## 6. Relationship to other controls

- **Access control policy.** The server-side application access model and the
  monthly IAM / privileged-session cadence live in `ACCESS_CONTROL_POLICY.md`
  §8; this register is the *human/operator* companion it §9 requires.
- **HR pack.** Screening (HR1) and offboarding (HR3) are driven from this
  register (`HR_SECURITY_PACK.md`).
- **Device standard.** Adding a person usually adds a device; keep the device
  register (`DEVICE_STANDARD.md` §4) in step with joiner/leaver events here.

## 7. Supporting evidence index

| Control | Evidence (owned by Nic) |
|---|---|
| Populated access register | This file, completed with real principals (restricted store if it grows detail) |
| First + annual review | Dated review pass with reviewer name and per-row keep/reduce/revoke |
| Monthly IAM subset | IAM export / capability canaries (`ACCESS_CONTROL_POLICY.md` §8) reconciled here |
| MFA on privileged accounts | `ACCESS_CONTROL_POLICY.md` §6 (admin TOTP runbook) |
| Offboarding driven by the register | `HR_SECURITY_PACK.md` §4 |

## 8. Known gaps / reviewer must confirm

- **NIC — not populated.** This is a template with placeholder rows. Nic must fill
  in every real (person × system) with access level, MFA status, and dates.
- **NIC — no first review yet.** A7 needs a **dated first review**: walk every row,
  confirm least privilege, stamp "last reviewed" and reviewer. Until that pass
  exists, A7 is not evidenced.
- **MFA coverage.** Confirm MFA is actually enforced on **every** privileged
  account listed (GCP/Firebase, GitHub, Apple, Play, registrar, Cloudflare,
  password manager, mailboxes), not just the admin portal — several of these
  columns say "(confirm)".
- **System list completeness.** Confirm the §3 list is complete for Lumi's real
  estate — add any missing console-login vendor (SendGrid, Twilio, error/analytics
  tooling, billing entity) as its own row.
- **Storage of detail.** If populated rows include sensitive detail, keep the full
  register in the restricted store and place only the review summary/outcome in
  the evidence pack (mirrors `HR_SECURITY_PACK.md` §2.2).
- **Sign-off.** This register is only A7 evidence once populated, first-reviewed,
  and signed by Nic.
