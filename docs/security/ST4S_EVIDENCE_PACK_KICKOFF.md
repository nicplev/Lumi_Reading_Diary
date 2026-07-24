# ST4S Evidence-Pack Workstream — Kickoff

**Worktree:** `/Users/nicplev/lumi_reading_tracker-evidence-pack` · **Branch:** `docs/st4s-evidence-pack`
**Separate from** the completed code-security work (which is merged + deployed on `main`).
**Golden rule:** only write a control assertion once it is **true, live, and evidenced** — cite the deployed fixes; never claim a control that isn't real (the ST4S honesty-list rule).

## Already true (cite these in the docs)
- **F-01/F-02/F-03** create-time rules-forgery fixes — deployed (`firestore:rules`), emulator regression tests in `functions/test/security_poc.rules.test.js`.
- **A2** — 14+/complexity everywhere: shared app+portal validators, 16-char/symbol temp generators, **Firebase console password policy set to Require/14/all-classes** — deployed.
- **SAST-01** MFA-crypto hardening + **F-04** fail-closed `assertSuperAdmin` on destructive server-ops — deployed (admin-deploy).
- **F-07** books/lookup ISBN validation + rate limit — deployed (school portal).
- **CI scanning** — Dependabot + osv-scanner + semgrep + secret-scan (gitleaks); findings register.
- **EV11** Vulnerability Assessment Report — `docs/security/VULNERABILITY_ASSESSMENT_REPORT_2026-07-24.md`.

## Document backlog (from ST4S plan Phase 4 + 6)
| Doc | ST4S | Tranche | Needs legal/sign-off? | Source material |
|---|---|---|---|---|
| **EV13 Secure SDLC** | EV13, Q5 | B (now unblocked) | No | CI workflows, `RELEASE_PRIVACY_SECURITY_REVIEW.md`, branch→PR→CI→deploy, new scanners |
| **Monitoring Plan** | T1 | B | No | CI scanners, EV11, external-pentest plan, findings register |
| **Access Control Policy** | A6/A7/A13 | B | Nic sign-off | RBAC model, `firestore.rules`, deployed F-01..F-04, MFA (A5) |
| **EV6 Information Security Policy** | EV, Q7, GO1 | B | Nic sign-off | references GO1/GO2 letters (pending), least-privilege+MFA, this SDLC |
| **EV12 Patch Management Process** | EV, T2, T3 | B | Nic sign-off | Dependabot, audit cadence, 14d/48h deadlines, patch register |
| **EV9 Incident Response Plan + register** | EV, T6, T7 | A | Nic sign-off | `docs/privacy/DATA_BREACH_RESPONSE_AND_TABLETOP.md` |
| **EV7 BCP / EV8 DR** | EV, D3 | A | Nic sign-off | status-banner runbook, backup/PITR, restore drill |
| **HR pack** (screening/training/offboarding) | HR1/2/3 | A + Nic | Nic | WWCC (0.1), access register (2.4) |
| **Device standard** | A10 | A + Nic | Nic | Mac settings (2.1) |
| **Monitoring/crypto/etc.** | S1/S3/S7 | — | — | Wave 3 TLS scan (pending), crypto profile |
| **Privacy pack** (PR2/PR17/PR10/INT7) | PR-series | A/DOC | **Privacy adviser** | PIA, vendor register, APP 8 brief |

## First batch (being drafted now — truthful technical docs, no legal review)
1. **EV13 Secure SDLC** · 2. **Monitoring Plan (T1)** · 3. **Access Control Policy (A6/A7/A13)**
Each drafted from repo evidence + the deployed controls above. Review, then commit → PR → merge from this worktree.

## How to run this workstream
- Draft each doc from its source material; keep it factual and cite file paths.
- Route the sign-off docs to Nic; route the privacy pack to the privacy adviser (the APP 8 brief exists for exactly this).
- Do **not** submit anything to ST4S until reviewed + signed.
