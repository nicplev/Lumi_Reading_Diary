# Lumi — Security Findings Register

**Purpose:** the running record of every finding from the self-managed assessment + automated scans (ST4S **EV11** vulnerability-assessment evidence, **T1** risk-based triage). One row per finding: severity, status, owner, decision, resolution. Updated as scans run and fixes land.
**Sources:** the Opus/Fable orchestration (`SECURITY_ASSESSMENT_ORCHESTRATION_PLAN.md`), the mobile AP2 review, `npm/pnpm audit`, osv-scanner, semgrep. Deduped against the closed dry-run findings (`PENTEST_DRYRUN_FINDINGS_2026-07-20.md`).

Status: ☐ open · ◐ in progress · 🔍 confirmed, unfixed · ☑ fixed+verified · ⓘ accepted/by-design

---

## Application / rules findings

| ID | Finding | Sev | ST4S | Status | Resolution / decision |
|---|---|---|---|---|---|
| F-01 | Student `create` omitted server-owned-field denylist → forgeable live `access` entitlement (self-provisionable) | High/Med | S4, A13 | ☑ | Fixed `firestore.rules` (shared field list on create+update); emulator-confirmed + regression test (`0d31809`) |
| F-02 | School `create` omitted commercial-fields guard (subscription/access/accessMode/isDemo) | Med | S4 | ☑ | Fixed + regression test (`0d31809`) |
| F-03 | Class `update` let a teacher-of-class reassign teacherId/teacherIds ownership | Med-Low | S4 | ☑ | Fixed (teacher ownership lock; admin retains) + regression test (`0d31809`) |
| F-04 | `packages/server-ops` privileged ops carry no internal authz (single-layer; portal gate present) | Med (def-in-depth) | A5, S4, A13 | ☑ | Fixed + deployed (PR #561 / `6d5b795`): fail-closed `assertSuperAdmin(db, actor.uid)` on the 5 destructive super-admin ops (offboard / grantDevAccess / manageParentAccount / bulkDeleteParents / manageSchoolUserAuth); mirrors admin `isSuperAdminViaFirestore`; `authority.parity.test.ts`. Auto-deployed via admin-deploy |
| F-05 | App Check OFF on all callables (SMS/code/marketing abuse surface) | Low-Med | A13, S7 | ◐ | Known launch gate; staged rollout in `REMAINING_HARDENING_RUNBOOK.md` §6 |
| F-06 | Storage cover first-claim open to any authed non-demo user (world-readable catalogue; content-type client-declared) | Low | S4, PF51 | ⓘ accept-as-designed | Documented, intended tradeoff (`storage.rules.test.js:373-378`): storage rules can't read Firestore for role, accounts are invite-only, covers are non-personal. Enforced protections stand: uploaderUid must equal the caller, and no overwrite of another user's cover. Optional uplift: callable-mediated upload with a server-side role check |
| F-07 | `books/lookup` external-API amplification + ISBN param injection, no rate limit | Low | Q5 | ☑ | Fixed (F-07 PR): strict ISBN-10/13 validation (route regex + `isValidIsbn` guard) + per-user rate limit (60/min via `consumeRateLimit`). Portal tsc clean; deployed (school portal) |
| F-08 | CSRF on portal mutations rests on `SameSite=Lax` alone | Low | A13 | ⓘ | Accept-as-designed; revisit if a same-registrable-domain sibling is introduced |
| F-09 | `createUser` password min-6 → 14+/complexity (portal) | Low | **A2** | ☑ | Fixed + deployed (PR #554): shared validator on Add-Staff route+modal; temp generators 16+symbol; Firebase console policy Require/14/all-classes set. A2 true across surfaces |

## Mobile (AP2 / MASVS) findings

| ID | Finding | Sev | Status | Decision |
|---|---|---|---|---|
| M-01 | Hive offline caches unencrypted at rest (child PII) | Med | ⓘ known | Local-access-only; mitigated by backup exclusion. Optional: encrypt boxes with a Keychain/Keystore key |
| M-02 | Comprehension audio unencrypted pre-sync | Low-Med | 🔍 new | Transient; consider encrypt-at-rest for the staging dir |
| M-03 | iOS widget App Group plaintext child firstName | Low | 🔍 new | Low blast radius; note in PIA |
| M-04 | App Check backend enforcement OFF (=F-05) | Med | ◐ | Launch gate |
| M-05 | No TLS certificate pinning | Low/Info | ⓘ | Accepted (Firebase cert rotation) |
| M-06 | No root/jailbreak/anti-tamper | Low/Info | ⓘ | Advisory |
| M-07 | Firebase API keys in bundle | None | ⓘ | Not a vuln — client identifiers |
| M-08 | `debugPrint` in release | Low/Info | ⓘ | Hygiene; reviewed clean |

## Automated-scan findings (SCA + SAST)

Semgrep SAST baseline (`p/typescript`,`p/javascript`,`p/secrets`,`p/owasp-top-ten` over functions/portals/server-ops): **1 finding total** (SAST-01), 2 non-blocking parse errors, no secrets flagged — a clean baseline consistent with the gitleaks-clean history.

| ID | Finding | Sev | ST4S | Status | Decision |
|---|---|---|---|---|---|
| SCA-01 | `functions`: 9 transitive advisories (8 moderate, 1 high) under `firebase-admin` (`@google-cloud/firestore`→`google-gax`; `@google-cloud/storage`→`teeny-request`→`uuid`; `retry-request`) | High/Mod | T2, T3, AP1, EV11 | ◐ | No clean upgrade (`--force` breaks); track `firebase-admin` releases, bump when patched. Dependabot + osv-scanner now watch this |
| SAST-01 | `admin/src/lib/mfa/crypto.ts:44` — AES-256-GCM `createDecipheriv` without a pinned `authTagLength` (semgrep `gcm-no-tag-length`) | Low | Q5, EV13 | ☑ | Fixed (PR #557 / `96b4cce`): pinned `authTagLength:16` on cipher+decipher + reject any non-16-byte tag before `setAuthTag`; truncated-tag regression test added (admin suite 21/21, admin-ci green). Deployed via admin-deploy (auto) |

---

## Change log
| Date | Update |
|---|---|
| 2026-07-23 | Register created. F-01/F-02/F-03 fixed+verified; AP2 review folded in; SCA baseline (SCA-01) recorded; Dependabot + osv-scanner + semgrep added to watch dependencies/SAST going forward. |
| 2026-07-23 (overnight) | F-06 reclassified accept-as-designed (`storage.rules.test.js:373`). Semgrep SAST baseline run — 1 finding (SAST-01, low), otherwise clean. S4 cross-tenant isolation assurance test added + passing (4/4 in `security_poc.rules.test.js`). |
| 2026-07-24 | **F-01/F-02/F-03 DEPLOYED to production** (`firestore:rules` → `lumi-ninc-au`, PR #520 / `66339f0`) — now live-fixed. New hygiene note (HY-01, info): pre-existing unused `demoAdminReadOnly` function + invalid `request` var refs at `firestore.rules:186-190` (dead code, cleanup candidate; not a security issue). |
| 2026-07-24 | **A2 (F-09) done + deployed** (PR #554 / `2b29e9a`): temp-pw generators 16+symbol, portal Add-Staff 14+/complexity shared validator, Dart app validators; portal + `processStaffOnboardingEmail` deployed; Firebase console password policy set to Require/14/all-4-classes (evidence: password-policy screenshot → `~/lumi-security-evidence/A2-passwords/`, to be filed in the master pack by Nic). |
| 2026-07-24 | **SAST-01 + F-07 fixed** (one sync). SAST-01 (MFA-crypto `authTagLength` pin + truncated-tag rejection) merged PR #557 / `96b4cce`, admin 21/21. F-07 (books/lookup strict ISBN validation + 60/min per-user rate limit) merged in the F-07 PR, portal tsc clean. Both are low-severity; each deploys with its portal. |
| 2026-07-24 | **F-04 done + deployed** (PR #561 / `6d5b795`): fail-closed `assertSuperAdmin` guard on the 5 destructive super-admin server-ops (defence in depth), admin-ci + regression-gate green, auto-deployed via admin-deploy. **All code-security findings are now fixed and deployed** (SAST-01/F-07 confirmed live: admin-deploy + manual school-portal deploy). |
