# Lumi Security Assessment — Live Status Board

**Last updated:** 2026-07-23 · **Branch:** `sec/security-assessment` · **Worktree:** `/Users/nicplev/lumi_reading_tracker-security-assessment`
**Companion:** `docs/security/SECURITY_ASSESSMENT_ORCHESTRATION_PLAN.md` (the plan) · `docs/ST4S_REMEDIATION_PLAN_2026-07-22.md` (the ST4S tracker, in the main checkout)

Status markers: ☐ not started · ◐ in progress · 🔍 under test / awaiting verification · ☑ done (verified + evidenced)

---

## ▶ Where we're up to (one glance)

- **Now:** **All code-security findings fixed + deployed** (F-01/02/03, A2, SAST-01, F-07, F-04); **S1/S3/S5 verified** (Wave 3 TLS scan); **EV11 report** produced; portal security headers deployed. **15 technical/policy evidence docs drafted** in the `docs/st4s-evidence-pack` worktree (pending review + sign-off). The security-code assessment is complete; what remains is document sign-off + your real-world tasks (GO1/GO2 officer letters, WWCC, access register, restore drill, external pen test EV10).
- **Boundary held:** no active production testing; Wave 3 (passive prod TLS scan) stays parked for an explicit hostname exception. Prod deploys (rules, portal, function) were done under explicit user authorisation.
- **Left:** the documents/evidence-pack workstream (running in the `docs/st4s-evidence-pack` worktree; first 3 technical docs drafted); the independent external pen test (EV10 — needs booking, scoping pack ready); F-05 App Check (launch-gated). **All code-security findings fixed + deployed; Wave 3 TLS scan done (S1/S3/S5 ✔).** (F-06/F-08 accept-as-designed; cross-tenant CG-sweep proven in #520.)

## How to track progress (3 ways)

1. **This file** — I update and commit it after every wave and every confirmed finding.
2. **`git log --oneline sec/security-assessment`** — every PoC, fix, and finding is its own commit whose message names the ST4S item it addresses. This is the audit trail.
3. **In-session** — I summarise each Opus agent's result and my (Fable) review as it comes in, before anything is marked ☑.

---

## Wave progress

| Wave | What | Environment | Status | Output |
|---|---|---|---|---|
| 0 — Source recon | 5 Opus agents map authz / rules / portals / vendor / env; Fable triage | Repo (read-only) | ☑ | 9 candidate findings (F-01…F-09), deduped vs closed list |
| 1 — Deep source analysis | Per-target Opus agents + local SCA/SAST | Repo (read-only) | ◐ | SCA (npm audit) + SAST (semgrep) run; register updated (SCA-01, SAST-01) |
| 2 — Emulator dynamic PoC | Client-SDK exploit tests in the emulator; each becomes a regression test | Emulator (`demo-lumi-secpoc`), synthetic only | ◐ | **F-01/F-02/F-03 ☑ confirmed+fixed+regression**; F-06 → accept-as-designed; cross-tenant CG sweep + callable-abuse PoCs remaining |
| 3 — Passive prod config | TLS/header profile of Lumi's own hostnames (read-only) | Prod hostnames | ☑ done (authorised 2026-07-24) | S1/S3/S5 ✔ — TLS 1.2+ only, TLS 1.3, valid certs (`TLS_CRYPTO_PROFILE_2026-07-24.md`) |
| 4 — Mobile static (AP2) | MASVS/MASTG static review | Repo (read-only) | ☑ | AP2 findings (below); MobSF/build left for tester |
| 5 — Continuous automation | Dependabot, osv-scanner, semgrep; findings register (ZAP deferred to prod-scan exception) | CI config | ◐ | AP1/T1/T2/EV11 controls |

---

## Findings register (this orchestration)

| ID | Finding (short) | Sev | Status | ST4S | Evidence when done |
|---|---|---|---|---|---|
| F-01 | Student `create` omits server-owned-field denylist → forgeable `access` entitlement | High/Med | ☑ **confirmed (emulator) + fixed + regression-tested** (`0d31809`) | S4, A13 | `security_poc.rules.test.js` F-01 |
| F-02 | School `create` omits commercial-field guard | Med | ☑ **confirmed + fixed + regression-tested** (`0d31809`) | S4 | `security_poc.rules.test.js` F-02 |
| F-03 | Class `update` authz off pre-image only → teacher reassigns ownership | Med-Low | ☑ **confirmed + fixed + regression-tested** (`0d31809`) | S4 | `security_poc.rules.test.js` F-03 |
| F-04 | `server-ops` single-layer authz → fail-closed super-admin guard | Med (def-in-depth) | ☑ **fixed + deployed** (PR #561, admin-deploy) | A5, S4, A13 | in-module `assertSuperAdmin` on 5 destructive ops |
| F-05 | App Check OFF on all callables | Low-Med | ☐ known launch gate | A13, S7 | Staged-rollout evidence |
| F-06 | Storage cover first-claim open to any authed non-demo user | Low | ⓘ accept-as-designed (`storage.rules.test.js:373`) | S4, PF51 | Intended tradeoff; enforced: uploaderUid=caller, no overwrite of others |
| F-07 | `books/lookup` external-API amplification + param injection | Low | ☑ **fixed** (F-07 PR); deploys with portal | Q5 | ISBN validation + 60/min rate limit |
| F-08 | CSRF on portal mutations rests on SameSite=Lax | Low | ☐ note | A13 | Decision note |
| F-09 | `createUser` password min-6 → 14+/complexity | Low | ☑ **fixed + deployed** (PR #554); part of A2 | **A2** | shared portal validator + console policy |

---

## Mobile (AP2) findings — MASVS/MASTG static review

Owner [SEC]. Overall posture is good: the one PII-bearing signup box is AES-256 encrypted with a Keychain/Keystore key, deep-link validation is strict (scheme/host/path allowlist, no query-param forwarding), no WebView, Analytics/Crashlytics off until adult opt-in, and `allowBackup=false` + data-extraction rules exclude every domain from cloud-backup/device-transfer (so plaintext caches don't leave the device). Residual items:

| ID | Finding | Sev | MASVS | Status |
|---|---|---|---|---|
| M-01 | Hive offline caches (students, reading_logs, pending_sync) unencrypted at rest — child PII | Med | STORAGE | Known/accepted; local-access-only (rooted/forensic) |
| M-02 | Comprehension **audio** (child voice) written unencrypted pre-sync, then deleted | Low-Med | STORAGE | **New**; transient; same access precondition |
| M-03 | iOS widget App Group stores child `firstName`+streak as plaintext JSON | Low | STORAGE | **New**; shared only with own widget |
| M-04 | App Check client wired but **backend enforcement OFF** (=F-05) | Med | RESILIENCE | Known launch gate |
| M-05 | No TLS certificate pinning | Low/Info | NETWORK | Acceptable with Firebase; note for tester |
| M-06 | No root/jailbreak/anti-tamper/obfuscation | Low/Info | RESILIENCE | Advisory (Dart AOT limits reversibility) |
| M-07 | Firebase API keys in bundle | None | STORAGE | **Not a vuln** — client identifiers; flagged to prevent false-positive |
| M-08 | `debugPrint` runs in release (reviewed: no secrets/PII logged) | Low/Info | RESILIENCE | Hygiene note |

MASTG gaps for the external mobile tester: at-rest inspection on rooted/jailbroken device, backup-vector extraction, deep-link fuzzing, App Check backend-enforcement replay, MITM with user CA, runtime/Frida tamper. Existing coverage credited: `test/security/android_backup_rules_test.dart` (backup/transfer exclusion).

## ST4S coverage map — what this assessment touches, by section

Owner tags: **[SEC]** this security orchestration · **[DOC]** separate documents/privacy workstream · **[NIC]** your real-world tasks (accounts, devices, screening, bookings). Readiness result column is from the 22 Jul check.

| ST4S | Topic | 22 Jul result | Owner | Assessment status | Remediation phase |
|---|---|---|---|---|---|
| S1 | TLS in transit | Not Ready | [SEC] | ☑ TLS 1.2+ only verified (Wave 3) | 3 |
| S3 | Encryption on upload | Not Ready | [SEC] | ☑ TLS 1.2+ only verified (Wave 3) | 3 |
| S4 | Per-school data separation | Ready | [SEC] | 🔍 validating (W1/W2) | — |
| S5 | Proper TLS certs | Ready | [SEC] | ☑ confirmed (Google Trust Services / Let's Encrypt, valid, Wave 3) | — |
| S7 | Server/endpoint protection | Not Ready | [NIC]+[SEC] | ☐ config statement | 2.3 |
| A2 | Password strength & storage | Answered Yes, not true | [SEC]+[NIC] | ☑ **done + deployed** (code #554 + console policy Require/14/all-classes) | 1.1 |
| A5 | MFA for privileged accounts | Not Ready | [NIC]+[SEC] | ☐ verify portal enforcement | 2.2 |
| A13 | Deny-by-default access | Ready | [SEC] | 🔍 validating (W1/W2) | — |
| A7 | Access review/revocation | Not Ready | [NIC]+[DOC] | ◐ register template drafted; Nic populates + reviews | 2.4 / 4 |
| T1 | Monitoring + annual pen test | Not Ready | [SEC]+[DOC]+[NIC] | ◐ Monitoring Plan drafted; scans live; external pen test (EV10) outstanding | 0.2 / 5 |
| T2 | Centrally managed patching | Not Ready | [SEC]+[DOC] | ◐ Dependabot live + EV12 patch process drafted | 4 / 5 |
| T3 | Patch deadlines 14d/48h | Ready (see honesty list) | [DOC] | ◐ EV12 patch process drafted | 4 / 5 |
| Q5 | Security testing per framework | Ready (med risk) | [SEC] | ◐ | 0.2 / 5 |
| AP1 | Scan every deploy + monthly | Not Ready | [SEC] | ☐ (Wave 5) | 5 |
| AP2 | Mobile tested per MASTG | Not Ready | [SEC] | ☐ (Wave 4) | 5.4 |
| PF51 | File-upload protections incl. AV | Ready (see honesty list) | [SEC]+[NIC] | 🔍 F-06 | 7 |
| EV10 | Penetration-test report | Not Ready | [SEC] interim + external final | ◐ interim assessment report done; independent external test still outstanding | 4 |
| EV11 | Vulnerability-assessment reports | Not Ready | [SEC] | ☑ report produced (`VULNERABILITY_ASSESSMENT_REPORT_2026-07-24.md`) | 4 / 5 |
| Privacy/T&C consent (web portals) | Not captured in portals | [SEC] code + [DOC] policy | ☐ | 1.2 / 6.5 |
| EV6–EV9, EV12, EV13 | Policy pack (InfoSec/BCP/DR/IRP/patch/SSDLC) | Not Ready | **[DOC]** | ◐ **all drafted** (EV6/EV7/EV8/EV9/EV12/EV13, evidence-pack worktree), pending review+sign-off (GO1/GO2 letters, restore drill) | 4 |
| HR1/HR2/HR3 | Screening / training / offboarding | Not Ready | [NIC]+[DOC] | ◐ standards drafted (HR pack); need Nic's WWCC + dated training + register | 0.1 / 4 |
| GO1/GO2 | Named security & privacy officers | Not Ready | [NIC]+[DOC] | ☐ separate | 0.3 |
| PR2 | Privacy policy content | Not Ready | **[DOC]** | ◐ rewrite drafted (adviser sign-off + APP 8 gate) | 6.1 |
| PR10 | Data shared with third parties | Not Ready (answered Yes) | **[DOC]** | ◐ audit drafted → answer "No"; adviser to confirm | 6.3 |
| PR17 | Sub-processors described publicly | Ready (med risk) | **[DOC]** | ◐ sub-processor table drafted; DPA reviews pending | 6.2 |
| INT7 | Written data agreements | Not Ready | [NIC]+[DOC] | ◐ DPA-record template drafted; Nic files acceptances | 6.4 |

---

## Workstream split — what is / isn't in this orchestration

**IN this security orchestration [SEC]:** vulnerability discovery + verification, code security fixes (rules gaps, A2 password code, App Check, portal consent-gate *code*), CI scanning automation, and the interim **EV10/EV11** test evidence. It validates the technical S/A/PF items and produces reproducible PoCs + regression tests.

**SEPARATE — the documents / privacy / terms workstream [DOC]:** the EV6–EV13 policy pack, HR pack, access-control / monitoring / device-standard docs, the **Privacy Policy rewrite (PR2)**, sub-processor table (PR17), data-sharing audit (PR10), sub-processor agreements (INT7), GO1/GO2 appointment letters, and the single consent version bump (6.5). This is drafting + your (and a privacy adviser's) sign-off — a different mode, different reviewer loop, no testing. **Recommended: run it as its own orchestration in its own worktree/branch** (e.g. `docs/st4s-evidence-pack`) so policy drafting and security-code changes never tangle in one PR. Not started; stand up on request.

**YOURS — real-world tasks [NIC]:** WWCC/screening (HR1), MFA on privileged accounts (A5), Mac/device settings (A10/S7), booking the external pen test (0.2), signing the officer letters (GO1/GO2). These can't be automated; the ST4S plan Phases 0 and 2 list them.

### Sequencing — docs follow the code they assert (truthfulness rule)

A control-assertion document may only be written once the control is **true and ☑ on this board** — writing it earlier repeats the ST4S *honesty-list* mistake (claiming 14-char passwords while code enforces 6; asserting "entitlement enforced server-side at a single point" while F-01 shows `create` bypasses it). So the [DOC] pack splits by dependency, and the security orchestration **leads**:

- **Tranche A — code-independent, may start now (genuinely parallel):** HR pack (HR1/2/3), GO1/GO2 letters, BCP/DR/IRP (EV7/EV8/EV9), device standard (A10), and the privacy/vendor docs that describe *existing data flows* — PR2 content, PR17 sub-processor table, PR10 data-sharing audit, INT7 agreements. These assert facts about org process and current architecture, not the controls under change. *(Caveat: the consent-mechanism claim in PR2 and the single re-acceptance version bump (6.5) are sequenced behind the portal consent-gate code in [SEC] 1.2.)*
- **Tranche B — must follow the [SEC] item it asserts:** EV6 InfoSec policy, access-control policy (A6/A7/A13), crypto profile (S1/S3 — needs Wave 3 scan results), EV11 vuln-assessment + monitoring plan (T1/AP1 — need Wave 5 scans running), EV12 patch process (T2 — needs Dependabot/scans), EV13 SSDLC (needs the CI gates in place), the **A2** answer, and the **Privacy/T&C consent** answer. Each is written against the *fixed* state and cites this board's ☑ + evidence.

**Rule:** the [DOC] workstream reads its truth from this board and the merged `sec/security-assessment` fixes; it never asserts a control still marked ☐/◐/🔍. This mirrors the ST4S plan's own phase order (Phase 1 code → Phase 3 crypto scan → Phase 4 docs → Phase 5 scans → Phase 6 privacy → Phase 7 re-run) and its golden rule.

---

## Change log

| Date | Update |
|---|---|
| 2026-07-23 | Board created. Wave 0 complete (5 Opus agents + Fable triage); F-01 source-verified. Awaiting Wave 1/2 go-ahead. |
| 2026-07-23 | Clarified doc↔code sequencing: control-assertion docs (Tranche B) gated on their [SEC] item being ☑; only code-independent docs (Tranche A) run truly in parallel. Corrects the earlier "fully parallel" framing. |
| 2026-07-23 (overnight) | Wave 2: F-01/F-02/F-03 confirmed in emulator, fixed in `firestore.rules`, regression-tested (`security_poc.rules.test.js`, wired into `test:rules`); full suite 172/172 green (commit `0d31809`). Wave 4 mobile AP2 static review completed (M-01..M-08). |
| 2026-07-24 | F-01/F-02/F-03 **merged (PR #520 → `66339f0`, regression-gate green) and DEPLOYED to prod** (`firestore:rules` → `lumi-ninc-au`). Client-flow safety verified pre-deploy. Rules compiled with only pre-existing warnings (unused `demoAdminReadOnly`, lines 186-190 — hygiene, not from this change). |
| 2026-07-24 | **A2 passwords done + deployed** (PR #554 → `2b29e9a`, regression-gate green): 3 temp-pw generators 12→16+symbol; portal Add-Staff min-6→14/complexity (shared validator, API+modal); shared Dart validator in the 3 signup screens. Portal + `processStaffOnboardingEmail` deployed. Firebase console password policy set to Require / min 14 / all four classes (screenshot evidence → `~/lumi-security-evidence/A2-passwords/`, to be filed in the master pack). App validators ship next app release. A2 true across all surfaces. |
| 2026-07-24 | **SAST-01 + F-07 done** (one sync). SAST-01 MFA-crypto `authTagLength` pin + truncated-tag test (PR #557, admin-ci + regression-gate green). F-07 books/lookup: strict ISBN validation + 60/min per-user rate limit (F-07 PR, portal tsc clean). Both merged; deploy with their portals. |
| 2026-07-24 | **F-04 done + deployed** (PR #561 / `6d5b795`): fail-closed `assertSuperAdmin` on the 5 destructive super-admin server-ops (offboard/grantDevAccess/manageParent/bulkDeleteParents/manageSchoolUserAuth); `authority.parity.test.ts` green in admin-ci; auto-deployed via admin-deploy. **This closes the last code-security finding — all are now fixed and deployed.** |
| 2026-07-24 | **Wave 3 (passive prod TLS scan) done** (authorised). All 6 Lumi endpoints: TLS 1.0/1.1 rejected, 1.2/1.3 supported, TLS 1.3 negotiated with AES-GCM, valid CA certs, HSTS present → S1/S3/S5 ✔. Evidence: `TLS_CRYPTO_PROFILE_2026-07-24.md`. Also: evidence-pack worktree stood up; first 3 technical docs (EV13 / monitoring / access-control) drafted. |
| 2026-07-24 | **Header hardening done + technical evidence docs drafted.** nosniff / X-Frame-Options / Referrer-Policy added to both portals (deployed + verified) + marketing config (PR #569). Evidence-pack now has **5 drafted technical docs** — EV13 SSDLC, Monitoring Plan (T1), Access Control Policy (A6/A7/A13), EV12 Patch Management (T2/T3), EV9 Incident Response (T6/T7) — pending review + sign-off (GO1/GO2 letters still needed). |
| 2026-07-24 | **Full evidence pack drafted (15 docs total).** Added EV6 InfoSec Policy, EV7 BCP, EV8 DR, device standard (A10), HR pack (HR1/2/3), access register (A7), sub-processor table (PR17), data-sharing audit (PR10), privacy policy rewrite (PR2 — adviser), INT7 record. All DRAFTS on `docs/st4s-evidence-pack` (commit `1e15d67`). Recurring blockers: GO1/GO2 letters unsigned, restore drill + WWCC + register + DPA acceptances pending, APP 8 sign-off, Cloudflare/support-mailbox not yet in the vendor register. |
