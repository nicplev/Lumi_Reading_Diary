# Lumi Security Assessment — Live Status Board

**Last updated:** 2026-07-23 · **Branch:** `sec/security-assessment` · **Worktree:** `/Users/nicplev/lumi_reading_tracker-security-assessment`
**Companion:** `docs/security/SECURITY_ASSESSMENT_ORCHESTRATION_PLAN.md` (the plan) · `docs/ST4S_REMEDIATION_PLAN_2026-07-22.md` (the ST4S tracker, in the main checkout)

Status markers: ☐ not started · ◐ in progress · 🔍 under test / awaiting verification · ☑ done (verified + evidenced)

---

## ▶ Where we're up to (one glance)

- **Now:** Wave 0 (source-assisted static recon) **complete**. Plan + this board written.
- **Blocked on you:** go-ahead for **Wave 1 + Wave 2** (deeper static + isolated emulator PoCs — zero prod exposure); decision on **Wave 3** (passive prod TLS scan, needs a narrow written exception).
- **Next action once approved:** write + run the first 6 emulator PoCs (F-01, F-02, F-03, F-06, cross-tenant collection-group sweep, callable App-Check-off abuse), each reviewed by Fable as it lands.

## How to track progress (3 ways)

1. **This file** — I update and commit it after every wave and every confirmed finding.
2. **`git log --oneline sec/security-assessment`** — every PoC, fix, and finding is its own commit whose message names the ST4S item it addresses. This is the audit trail.
3. **In-session** — I summarise each Opus agent's result and my (Fable) review as it comes in, before anything is marked ☑.

---

## Wave progress

| Wave | What | Environment | Status | Output |
|---|---|---|---|---|
| 0 — Source recon | 5 Opus agents map authz / rules / portals / vendor / env; Fable triage | Repo (read-only) | ☑ | 9 candidate findings (F-01…F-09), deduped vs closed list |
| 1 — Deep source analysis | Per-target Opus agents + local SAST (semgrep) / SCA (osv-scanner) | Repo (read-only) | ☐ | Confirmed candidates + PoC specs |
| 2 — Emulator dynamic PoC | Client-SDK exploit tests in the emulator; each becomes a regression test | Emulator (`demo-lumi-sec`), synthetic only | ☐ | CONFIRMED/REFUTED PoCs |
| 3 — Passive prod config | TLS/header profile of Lumi's own hostnames (read-only) | Prod hostnames | ☐ (needs written exception) | S1/S3/S5 evidence |
| 4 — Mobile static (AP2) | MASVS/MASTG static + MobSF on a local build | Local artifacts | ☐ | AP2 evidence |
| 5 — Continuous automation | Dependabot, osv-scanner, semgrep/CodeQL, monthly ZAP, findings register | CI (PRs) | ☐ | AP1/T1/T2/EV11 controls |

---

## Findings register (this orchestration)

| ID | Finding (short) | Sev | Status | ST4S | Evidence when done |
|---|---|---|---|---|---|
| F-01 | Student `create` omits server-owned-field denylist → forgeable `access` entitlement | High/Med | 🔍 source-verified, emulator PoC pending | S4, A13 | PoC test + rules fix + regression test |
| F-02 | School `create` omits commercial-field guard | Med | 🔍 | S4 | PoC + fix |
| F-03 | Class `update` authz off pre-image only → teacher reassign/inject | Med-Low | 🔍 | S4 | PoC + fix |
| F-04 | `server-ops` single-layer authz (gate currently present) | Med (def-in-depth) | ◐ prove gate completeness in W1 | A5, S4, A13 | Route-gate proof |
| F-05 | App Check OFF on all callables | Low-Med | ☐ known launch gate | A13, S7 | Staged-rollout evidence |
| F-06 | Storage cover first-claim open to any authed user | Low-Med | 🔍 | S4, PF51 | PoC + fix |
| F-07 | `books/lookup` external-API amplification + param injection | Low | ☐ verify W1 | Q5 | Rate-limit fix |
| F-08 | CSRF on portal mutations rests on SameSite=Lax | Low | ☐ note | A13 | Decision note |
| F-09 | `createUser` password min-6 | Low | ☐ fold into ST4S 1.1 | **A2** | Fix + evidence |

---

## ST4S coverage map — what this assessment touches, by section

Owner tags: **[SEC]** this security orchestration · **[DOC]** separate documents/privacy workstream · **[NIC]** your real-world tasks (accounts, devices, screening, bookings). Readiness result column is from the 22 Jul check.

| ST4S | Topic | 22 Jul result | Owner | Assessment status | Remediation phase |
|---|---|---|---|---|---|
| S1 | TLS in transit | Not Ready | [SEC] | ☐ (Wave 3) | 3 |
| S3 | Encryption on upload | Not Ready | [SEC] | ☐ (Wave 3) | 3 |
| S4 | Per-school data separation | Ready | [SEC] | 🔍 validating (W1/W2) | — |
| S5 | Proper TLS certs | Ready | [SEC] | ☐ confirm (Wave 3) | — |
| S7 | Server/endpoint protection | Not Ready | [NIC]+[SEC] | ☐ config statement | 2.3 |
| A2 | Password strength & storage | Answered Yes, not true | [SEC]+[NIC] | ◐ F-09 code + console policy | 1.1 |
| A5 | MFA for privileged accounts | Not Ready | [NIC]+[SEC] | ☐ verify portal enforcement | 2.2 |
| A13 | Deny-by-default access | Ready | [SEC] | 🔍 validating (W1/W2) | — |
| A7 | Access review/revocation | Not Ready | [NIC]+[DOC] | ☐ | 2.4 / 4 |
| T1 | Monitoring + annual pen test | Not Ready | [SEC]+[DOC]+[NIC] | ◐ | 0.2 / 5 |
| T2 | Centrally managed patching | Not Ready | [SEC]+[DOC] | ☐ (Wave 5 Dependabot) | 4 / 5 |
| T3 | Patch deadlines 14d/48h | Ready (see honesty list) | [DOC] | ☐ | 4 / 5 |
| Q5 | Security testing per framework | Ready (med risk) | [SEC] | ◐ | 0.2 / 5 |
| AP1 | Scan every deploy + monthly | Not Ready | [SEC] | ☐ (Wave 5) | 5 |
| AP2 | Mobile tested per MASTG | Not Ready | [SEC] | ☐ (Wave 4) | 5.4 |
| PF51 | File-upload protections incl. AV | Ready (see honesty list) | [SEC]+[NIC] | 🔍 F-06 | 7 |
| EV10 | Penetration-test report | Not Ready | [SEC] interim + external final | ◐ | 4 |
| EV11 | Vulnerability-assessment reports | Not Ready | [SEC] | ◐ | 4 / 5 |
| Privacy/T&C consent (web portals) | Not captured in portals | [SEC] code + [DOC] policy | ☐ | 1.2 / 6.5 |
| EV6–EV9, EV12, EV13 | Policy pack (InfoSec/BCP/DR/IRP/patch/SSDLC) | Not Ready | **[DOC]** | ☐ separate workstream | 4 |
| HR1/HR2/HR3 | Screening / training / offboarding | Not Ready | [NIC]+[DOC] | ☐ separate | 0.1 / 4 |
| GO1/GO2 | Named security & privacy officers | Not Ready | [NIC]+[DOC] | ☐ separate | 0.3 |
| PR2 | Privacy policy content | Not Ready | **[DOC]** | ☐ separate | 6.1 |
| PR10 | Data shared with third parties | Not Ready (answered Yes) | **[DOC]** | ☐ separate | 6.3 |
| PR17 | Sub-processors described publicly | Ready (med risk) | **[DOC]** | ☐ separate | 6.2 |
| INT7 | Written data agreements | Not Ready | [NIC]+[DOC] | ☐ separate | 6.4 |

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
