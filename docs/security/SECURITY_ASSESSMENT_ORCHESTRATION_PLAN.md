# Lumi — Automated Security-Testing Orchestration Plan

**Version 1.0 — 23 July 2026**
**Author:** Security Lead (Nic) + Claude (Fable orchestrator)
**Purpose:** Run an authorised, safe, self-managed security assessment that (a) targets the highest-value areas identified by the Project Black pen-test proposal, (b) maps every result to a specific ST4S gap, and (c) is executed by a fleet of Opus 4.8 sub-agents whose work is reviewed as it lands by the Fable orchestrator.
**Companion docs:** `docs/ST4S_REMEDIATION_PLAN_2026-07-22.md` (the ST4S tracker), `docs/security/PENETRATION_TEST_SCOPING_PACK.md` (the external-vendor SOW gate), `docs/security/PENTEST_DRYRUN_FINDINGS_2026-07-20.md` (already-closed findings — dedup source), `docs/privacy/VENDOR_DATA_FLOW_REGISTER.md` (the vendor-exclusion boundary).

> **Golden rule (shared with the ST4S plan):** a finding is only real when it is *reproduced* (emulator PoC or verified source path) and its severity is reconciled against live context. Static suspicion ≠ confirmed vulnerability.

---

## 0. TL;DR

- **This is NOT the external pen test.** It is a self-managed, source-code-assisted assessment that (1) de-risks and *scopes* the paid external engagement, (2) produces interim EV10/EV11 evidence, and (3) closes rules-test gaps as regression tests. The independent external report is still required for ST4S EV10 — see `PENETRATION_TEST_SCOPING_PACK.md`.
- **Wave 0 (source-assisted static recon) is DONE this session** — 5 Opus 4.8 agents mapped the backend authz, Firestore/Storage rules, both portals, the vendor/known-issue boundary, and the test/emulator environment. Fable synthesised, de-duplicated against the closed known-issues list, and verified the top finding against source.
- **Headline Wave 0 result:** one **new** rules gap not in the closed list — the student-`create` path lets a forged `access` entitlement map through (§9, F-01). Verified in source; emulator PoC pending.
- **The proposal is competent but generically framed.** Lumi's real authz boundary is *Firestore Security Rules + Cloud Functions callables + `packages/server-ops` + Next.js session gating*, not a REST API. **Take Option 2 (source-code-assisted)** and require Firestore/Storage rules emulator testing with a client SDK. Detail in §3.
- **Dynamic testing runs against the Firebase Emulator with synthetic data only** — there is no staging project (`.firebaserc` has only `default → lumi-ninc-au`, production). Prod is passive/read-only, and only under a narrow written exception. §8.
- **Awaiting your sign-off:** approve Wave 2 (emulator dynamic PoCs, zero prod risk) and decide on Wave 3 (passive prod TLS/header scan). §10.

---

## 1. What we are assessing, grounded in the code

Lumi Reading is a **Firebase/GCP serverless application**, project `lumi-ninc-au`, region `australia-southeast1`:

| Surface | Reality (verified Wave 0) | Primary authz mechanism |
|---|---|---|
| **Firestore** | ~60 logical collections; `rules_version '2'`; no `{document=**}` wildcard | `firestore.rules` (1458 lines) — the crown-jewel boundary |
| **Cloud Storage** | 1 client-facing bucket (audio, covers, logos) | `storage.rules` (158 lines); server re-validates audio bytes |
| **Cloud Functions** | 81 Gen2 workloads: ~35 callables, 1 IAM-locked HTTP, ~20 scheduled, ~27 event triggers | Per-callable `request.auth` + role/membership + credential-derived tenant |
| **`packages/server-ops`** | ~13 privileged modules (delete parent, offboard school, grant dev-access, create school, bulk-import) | **No internal authz** — single-layer, gated only by the calling portal route |
| **School portal** | `school-admin-web/` Next.js SSR, 20 pages / 79 API routes, teacher + schoolAdmin | `__session` JWT (HS256, `jose`), revocation-aware, membership-bound |
| **Super-admin portal** | `admin/` Next.js SSR, ~38 pages / ~66 API routes, global superAdmin | HMAC cookie + `timingSafeEqual`, per-request `/superAdmins/{uid}` recheck, TOTP |
| **Marketing site** | `lumi-reading.com`, 2 lead forms → unauthenticated callables | Rate-limited; App Check off |
| **Mobile** | Flutter iOS/Android, ~41 routes; talks **directly to Firestore/Storage via SDK** | Same `firestore.rules`/`storage.rules` as the app |
| **AI pipeline** | `functions/src/ai_evaluation/` — Vertex/Gemini, Sydney-pinned, **DARK** (kill-switch off, no school entitled) | Double fail-closed gate + deny-all on job/eval docs |

**The single most important architectural fact:** the mobile app *and* the web app *and* a raw client SDK all hit the same Firestore/Storage rules. "Mobile security" and "web security" are not separate server surfaces — they converge on the rules. A tester who fuzzes HTTP endpoints but doesn't exercise the rules with a client SDK will miss the real bugs (as the dry-run's own gap on student-`create` shows).

---

## 2. Vendor boundary (the exclusion list)

Per `VENDOR_DATA_FLOW_REGISTER.md`, we test **Lumi's configuration and use** of each service, **never the vendor's own infrastructure**:

- **In scope as Lumi config:** Firestore rules, Storage rules, Cloud Functions/Run/Eventarc/Scheduler authz + IAM/SA scoping, Firebase Auth/MFA/SMS flows + rate limits, App Check enforcement posture, Secret Manager usage (never values), Analytics/Crashlytics off-by-default gating, FCM/APNs token & payload minimisation, SendGrid template escaping (no child data in subjects), Google Books / Open Library request minimisation (ISBN/title only).
- **Out of scope (vendor infra):** Google/Firebase platform internals, SendGrid/Twilio, Apple/Google stores, Open Library/Google Books services themselves.
- **Configured but PROHIBITED as live data flows (do not treat as production paths):** Speech-to-Text, Anthropic/Gemini eval (dark), OpenAI (research), Stripe (design-only).

---

## 3. Assessment of the Project Black proposal (do not assume it is complete)

**Verdict:** a solid, industry-standard OWASP 2025 + SANS CWE-25 web+mobile proposal, but **generically framed for a traditional server/REST stack**. Adjust before signing.

| # | Proposal position | Reality at Lumi | Action |
|---|---|---|---|
| 1 | Methodology & examples are REST/`ActionResult`/`/api/v1/...` centric | Primary boundary is **declarative Firestore rules + callables + session-gated Next routes**; bugs live in create-vs-update rule asymmetries, `get` vs `list`, collection-group semantics, client-SDK direct access | **Insist on Firestore/Storage rules emulator testing with the client SDK.** Share `firestore.rules`, `storage.rules`, and `functions/test/firestore.rules.test.js`. |
| 2 | "Full test coverage for all API routes and dynamic pages" in **6 days** | ~145 portal routes + ~35 callables + ~60 collections + rules + mobile is a lot for 6 days of genuine coverage | Prefer **source-assisted (Option 2)** — it is explicitly higher-coverage-per-day and matches a declarative-logic codebase. Our Wave 0–2 output further shrinks their scope. |
| 3 | No mention of **AI/LLM testing** | ST4S has an AI module; Lumi has a Vertex/Gemini comprehension pipeline + a prompt-injection regression harness (`functions/scripts/ai-eval-prompt-regression.mjs`) | Add AI gate-bypass / prompt-injection / PII-leakage to scope (even though dark) — or note we cover it self-managed. |
| 4 | Assumes a **non-prod equivalent env** + **WAF IP-whitelisting** | **No staging project exists**; **no WAF** (Firebase Hosting + Cloud Run; App Check is the nearest control and it is OFF) | Tell them env = **Firebase Emulator + a disposable throwaway project** (prod identities are hardcoded — a faithful staging deploy needs de-hardcoding first, `docs/LUMI_SCALE_TEST_PLAN.md` P0). No WAF to whitelist. |
| 5 | Staffing CVE pedigree = WordPress/PHP/network-appliance SQLi/LFI/RCE | Lumi is **Firebase/Flutter/serverless** — different bug classes | Not a blocker *if* source-assisted; a reason to insist on it and to hand over the rules test suite. |
| 6 | Mobile & web tested separately; "server-side reuse not retested" | Mobile & web **share the rules boundary** | Confirm the rules ARE the shared server boundary for both, so it isn't tested once and assumed for the other. |
| 7 | Data-handling assumptions (backups, 30-day source deletion, no destructive tests) | Aligns with our rules | SOW must additionally pin: **synthetic data only, no real child data, AU handling, destruction of all test artifacts (not just source) in 30 days**. |

**Commercial note:** Option 2 (source-assisted) is AUD **11,880** vs Option 1 (grey box) **14,520** — cheaper *and* a better fit. Our self-managed waves should be shared with the vendor to tighten scope and avoid paying them to re-derive Wave 0/known-closed findings.

---

## 4. Mapping — pen-test category → Lumi surface → ST4S gap

This is the backbone: every test we run traces to an ST4S item.

| Pen-test category (proposal) | OWASP / CWE | Lumi surface to test | ST4S item(s) |
|---|---|---|---|
| Access Control | A01, A07, CWE-862/287/306/269/863/276/639 | Firestore rules tenant + role boundaries; `server-ops` authz; portal route authz; callable authz | **S4, A13, A5, A6, A7** |
| Auth / password strength | A07, CWE-521/287 | Portal create-user min-length; signup validators; MFA enforcement; session/revocation | **A2, A5, A11** |
| Input handling / injection | A05, CWE-89/78/79/434/22/94/502 | Portal routes (low SQLi surface — Firestore); ISBN param injection; upload validation; HTML in emails | **PF51**, Q5 |
| Cryptographic | A04, CWE-327 | TLS profile of public hostnames; at-rest (Google-managed); scrypt hashing | **S1, S3, S5** |
| Security misconfig / supply chain | A02, A03, CWE-798 | App Check OFF; IAM/SA scoping; dependency vulns; committed-secret scan | **S7, S9, S10, S11, T2, T3, AP1** |
| Business logic / SSRF / CSRF | CWE-840/918/352 | Entitlement mint (F-01); books/lookup external-call amplification; CSRF posture; demo/impersonation logic | Q5, access-model integrity |
| AI module | (ST4S AI) | AI eval gate bypass; prompt injection; transcript/PII leakage | **AI_T1#, AI_SF6#, AI_L1**, PR-series |
| Mobile (MASVS/MASTG) | — | Hive at-rest (known open); baked secrets; TLS/pinning; deep-links | **AP2** |
| Engagement as a whole | — | Report + vuln register + monthly cadence | **EV10, EV11, T1, Q5** |

---

## 5. Highest-value targets (Wave 0 output, deduped vs closed findings)

Ranked by value to **both** security and ST4S. The 9 dry-run findings + all July criticals are **already closed** (`PENTEST_DRYRUN_FINDINGS_2026-07-20.md`) — we do **not** re-derive them; only App Check (#8) remains open as a launch gate.

1. **Firestore rules create/update asymmetry (F-01, NEW).** Student `create` omits the server-owned-field denylist that `update` enforces → forged `access` entitlement. Also school `create` (subscription/access/accessMode/isDemo) and class `update` (teacherId/studentIds injection). **→ S4/A13.**
2. **`packages/server-ops` single-layer authz.** Delete-any-parent / offboard-school / grant-dev-access / create-school have no internal authorization — only the portal route's session gate stands between a caller and cross-tenant destruction. Prove *every* admin route gates before *every* privileged call. **→ A5/S4/A13.**
3. **App Check OFF on all callables.** Enables scripted abuse of unauthenticated/low-auth callables — SMS toll-fraud (`requestSmsVerification`), code enumeration, marketing spam. Known-open launch gate. **→ A13, S7.**
4. **Unauthenticated code callables leak child names.** `verifyStudentLinkCode` returns a child's first+last name for a valid 8-char code; rate-limited but App-Check-less. **→ S4, PR-series.**
5. **Storage cover-create surface.** Any authenticated user can first-claim any unclaimed ISBN cover (world-readable, client-declared content-type). **→ S4, PF51.**
6. **Cross-tenant collection-group isolation.** Structurally sound (no client CG rule; schoolId-bound paths) but **untested** for the negative case — must be proven, not assumed. **→ S4.**
7. **Portal residuals.** `books/lookup` external-API amplification (no rate limit, param injection); CSRF rests on `SameSite=Lax` alone; `createUser` password min-6. **→ PF51/A2/Q5.**
8. **AI pipeline (dark).** Gate bypass, prompt injection, transcript/PII leakage — test as-is against the fail-closed gates. **→ AI module.**
9. **Mobile static (AP2).** Hive at-rest unencrypted (known), baked secrets, TLS/pinning, deep-links. **→ AP2.**
10. **CI scanning gaps.** No Dependabot / SAST / OSV-scanner / DAST / container scan. **→ AP1, T1, T2, EV11.**

---

## 6. The orchestration model

The pattern already demonstrated in Wave 0: **Opus 4.8 agents fan out per surface; Fable reviews, de-dupes, adversarially verifies, ranks, and maps to ST4S as results land.**

### Waves

| Wave | What | Environment | Risk | Gate |
|---|---|---|---|---|
| **0 — Source recon** *(DONE)* | 5 Opus agents map authz/rules/portals/vendor/env; Fable triages | Repo (read-only) | None | — |
| **1 — Deep source analysis** | Opus agents per target (§5), each emits candidate findings with file:line + exploit hypothesis + proposed PoC; + local SAST (semgrep) + SCA (osv-scanner) read-only over the repo | Repo (read-only) | None | Auto-OK |
| **2 — Emulator dynamic PoC** | For each candidate needing dynamic proof, write/extend `@firebase/rules-unit-testing` + callable emulator tests that attempt the exploit as a client SDK; each = CONFIRMED/REFUTED PoC + a regression test | **Firebase Emulator** (`demo-lumi-sec`), synthetic data only | None to prod | **Your sign-off** |
| **3 — Passive prod config** | TLS profile (testssl/SSL Labs), security headers, "auth-required" confirmation of public endpoints — **no writes, no real data, read-only** | Prod hostnames | Low, passive | **Narrow written exception** |
| **4 — Mobile static (AP2)** | MASVS/MASTG static review + MobSF scan of a locally-built IPA/APK + `scripts/security/scan-secrets.sh` | Local build artifacts | None | Auto-OK |
| **5 — Continuous automation** | Add Dependabot, osv-scanner, semgrep/CodeQL, monthly ZAP baseline (gated like W3), findings register | CI (PRs) | None | Auto-OK (ZAP gated) |

**No prod exploitation, ever.** DAST/ZAP against prod is baseline-passive only and gated; all offensive PoCs run in the emulator.

### Fable review protocol (the "review as it comes in" layer)

For every agent result:
1. **Dedup** against the closed known-issues register — drop anything already fixed (the 9 dry-run findings + July criticals).
2. **Reconcile** cross-agent conflicts against live context (e.g. F-01's "free AI" impact is blunted because AI is dark; state the *actual* blast radius).
3. **Adversarially verify** every High/Critical before it is "CONFIRMED": Fable re-reads the source path *and/or* spawns 2–3 skeptic Opus agents prompted to **refute**; majority-refute kills it. Static-only findings are capped at PLAUSIBLE until an emulator PoC lands.
4. **Score** — CVSS v4.0 + business-impact weighting (child data > entitlement/licensing > within-tenant integrity > info).
5. **Map** to the ST4S item + the evidence artifact (EV10/EV11) it feeds.
6. **Gate** — only CONFIRMED, deduped, ST4S-mapped findings enter the report; passing emulator PoCs are committed as regression tests.

### Finding schema (agent output contract)

```
{
  id, title, surface, file, line,
  class: { owasp, cwe },
  st4s_item,
  severity: Critical|High|Medium|Low|Info,
  cvss_v4: <vector|null>,
  confidence: static|dynamic-confirmed|refuted,
  dedup_key,                       // matched against known-issues register
  exploit_hypothesis,              // one paragraph, no secrets/PII
  proposed_verification,           // exact emulator test or passive check
  live_impact_reconciliation,      // actual blast radius given current context
  remediation
}
```

Agents are hard-constrained: read-only unless the wave says emulator; **never print secrets, tokens, passwords, recovery codes, keys, PII, recordings, or raw DB content** — reference by variable name / file location only; return analysis, not file dumps.

---

## 7. What each Wave-1/2 Opus agent does (concrete)

1. **Rules-asymmetry agent** → all create-vs-update guard gaps across `firestore.rules`; produce the exact denied-field lists per collection; PoC list. (Seeds F-01, F-02, F-03.)
2. **Server-ops-gate agent** → enumerate every `admin/**/route.ts` mutator; prove `verifySession()` precedes every `@lumi/server-ops` call; flag any single unguarded path (= full cross-tenant compromise).
3. **Callable-abuse agent** → each callable's App-Check-off + rate-limiter posture; model SMS/code/marketing abuse under a spoofed client; identify the sole guard and whether it is evadable by varying uid/IP.
4. **Tenant-isolation agent** → design the cross-tenant collection-group sweep PoCs (`students`, `readingLogs`, `comprehensionEvals`, `allocations`) that must be *denied*.
5. **Storage agent** → cover-poisoning PoC + audio create-only regression (guard against the PR#481 split-rule bug) + the `firestore.get()`-in-storage-rules trap (currently correctly avoided).
6. **AI-pipeline agent** → gate bypass (kill-switch + entitlement), deny-all on job/eval docs, prompt-injection against the live harness, transcript/identifier leakage.
7. **Crypto/config/IAM agent** → runtime SA scoping, custom-token minting (impersonation), signed-URL scoping, TLS scan design for Wave 3.
8. **SCA/SAST agent** → run `osv-scanner` over `pubspec.lock` + npm/pnpm lockfiles and `semgrep` over the repo (read-only); triage against the already-clean baseline in `IN_HOUSE_PENTEST_PLAN.md`.

---

## 8. Safety & rules of engagement (binding)

- **Scope:** only Lumi-owned code, the Firebase Emulator (`demo-lumi-*`), and — passively, read-only, under a written exception — Lumi's own prod hostnames. Never a real school/tenant.
- **Data:** **synthetic only.** Seed via the emulator (`FIRESTORE_EMULATOR_HOST` / `FIREBASE_AUTH_EMULATOR_HOST` exported) or the fail-closed load harness (`load-tests/`, refuses `lumi-ninc-au`, requires `LUMI_LOADTEST_ACK`). **Never** run `scripts/seed_class_3a_mock.js` or any ADC-resolving demo seeder without the emulator host exported — they default to **production**.
- **Emulator bring-up:** `scripts/with-jdk21.sh firebase emulators:start --config firebase.deletion.json --only auth,firestore,storage,functions --project demo-lumi-sec` (JDK 21 required; `singleProjectMode:false` keeps suites isolated). Data is discarded on exit.
- **Vendor boundary:** §2 — test config/use, never vendor infra.
- **Prohibited outright:** DoS/volumetric/load against prod, password spraying, credential stuffing, phishing/social engineering, destructive exploits, data exfiltration, stealth/evasion, unbounded fuzzing.
- **Prod:** passive/read-only only, under a narrow written exception; **stop immediately** on any chance of touching real users, real data, cost, quota, or availability.
- **Secrets/PII hygiene:** never print or commit secrets, tokens, passwords, recovery codes, keys, PII, recordings, or raw DB content — anywhere (logs, terminal, screenshots, reports, git). Reference by location only. Reports are scrubbed before saving.
- **Never trust client-side checks** — confirm every important control server-side (rules / callable / route), per the high-risk-area rule.
- **Authorisation:** this self-managed emulator work is authorised by this plan on Nic's approval; the *external* engagement remains gated by a signed SOW (`PENETRATION_TEST_SCOPING_PACK.md` §7).

---

## 9. Wave 0 results (completed this session)

Method: 5 Opus 4.8 agents, read-only, source-assisted; Fable synthesis + source verification of the top finding.

**Overall posture is strong.** Tenant isolation is structurally sound (every role decision derives from a server-written membership doc, never a client claim; no `{document=**}`; no client collection-group rule). Both portals close the historical cookie-forgery / IDOR / self-provisioning / claims-clobber classes with visible fixes. Callables are consistently well-authorised. The risk concentrates in **create-vs-update rule asymmetries** and the **single-layer `server-ops` authz**.

| ID | Finding | Sev (Fable) | Confidence | ST4S | Status |
|---|---|---|---|---|---|
| **F-01** | Student `create` omits the server-owned-field denylist (`firestore.rules:532`); `access` map forgeable → bypasses `studentAccessLive`; `grantAccessOnStudentCreate` bails on pre-seeded `access` (`whole_school_access.ts:51`). Reachable by schoolAdmin/teacher, and via self-provisioned school. **Within-tenant licensing/authz bypass; blast radius currently limited (AI dark, within own tenant).** | **High** (control-bypass framing) / Med (current impact) | Source-verified by Fable; emulator PoC pending | S4, A13 | **NEW — verify in Wave 2, fix + regression test** |
| F-02 | School `create` omits commercial-field guard (subscription/access/accessMode/isDemo) (`firestore.rules:352`) | Medium | Static | S4 | Verify Wave 2 |
| F-03 | Class `update` authz keys off pre-image only → teacher can reassign `teacherId`/inject `studentIds` (`firestore.rules:626`) | Med-Low | Static | S4 | Verify Wave 2 |
| F-04 | `server-ops` privileged ops carry no internal authz — single-layer defense (all `admin` routes currently gate, so not live-exploitable) | Med (def-in-depth) | Static (gate confirmed present) | A5, S4, A13 | Prove gate completeness Wave 1 |
| F-05 | App Check OFF on all callables (SMS/code/marketing abuse surface) | Low-Med | Known-open launch gate | A13, S7 | Tracked (staged rollout) |
| F-06 | Storage cover first-claim open to any authed user (`storage.rules:66`) | Low-Med | Static | S4, PF51 | Verify Wave 2 |
| F-07 | `books/lookup` external-API amplification + param injection, no rate limit | Low | Static | Q5 | Verify Wave 1 |
| F-08 | CSRF on portal mutations rests on `SameSite=Lax` alone | Low (def-in-depth) | Static | A13 | Note |
| F-09 | `createUser` password min-6 (`api/users/route.ts:40`) | Low | Static | **A2** | Fold into ST4S Phase 1.1 |

**Rules-test gaps to close as regression tests** (from the rules agent): student-`create` forged-`access` (F-01, **zero coverage today**), student-`create` other server fields, school-`create` commercial fields (F-02), class `teacherId` reassignment (F-03), cross-tenant collection-group denial (F-06-adjacent), storage cover poisoning (F-06).

---

## 10. Decision points (need Security Lead sign-off)

1. **Approve Wave 1 + Wave 2?** Wave 1 (deeper static + local SAST/SCA) is zero-risk. Wave 2 (emulator PoCs, synthetic data, fully isolated) has **no prod exposure** and produces the CONFIRMED findings + regression tests. *Recommended: yes.* First 6 PoCs ready to write: F-01, F-02, F-03, F-06, cross-tenant CG sweep, callable App-Check-off abuse.
2. **Grant a narrow written exception for Wave 3?** Passive, read-only TLS/header scan of Lumi's own public hostnames (feeds S1/S3/S5/S7). No writes, no data, stop-on-anomaly. *Recommended: yes, scoped to a listed hostname set.* Otherwise defer.
3. **External engagement:** proceed with Project Black **Option 2 (source-assisted, AUD 11,880)**, amended per §3 (rules emulator testing, AI module, synthetic-data/destruction clauses, emulator+throwaway-project env, no-WAF note)? Share Wave 0–2 output to tighten scope. *Recommended.*
4. **Confirm the RoE in §8** as binding for all self-managed work.

---

## Appendix A — Emulator PoC targets (Wave 2, first batch)

All against `demo-lumi-sec`, synthetic data, client SDK via `@firebase/rules-unit-testing`, in the style of `functions/test/firestore.rules.test.js`:

1. **F-01:** as schoolAdmin, `create` `students/{x}` with `access:{status:'active',expiresAt:+1y}`; assert it currently succeeds (bug) → after fix, denied. Full chain: self-signup → create school → admin bootstrap → access-seeded student.
2. **F-02:** `create` `schools/{s}` with `subscription`/`access`/`accessMode`/`isDemo`; assert what persists.
3. **F-03:** as class teacher, `update` class changing `teacherId`/`teacherIds` + injecting foreign `studentIds`.
4. **F-06:** as unrelated authed user, upload `image/jpeg`-declared bytes to `community_books/covers/{unclaimed}.jpg`; then attempt overwrite of another user's cover (must deny — PR#481 regression guard).
5. **Cross-tenant CG sweep:** school-A teacher runs `collectionGroup` over `students`/`readingLogs`/`comprehensionEvals`/`allocations`; assert denial/constraint.
6. **Callable abuse:** with App Check emulated off, script `requestSmsVerification` / `verifyStudentLinkCode` and confirm the Firestore rate-limiter is the only guard and cannot be evaded by rotating uid/IP.

## Appendix B — Agent invocation template

```
model: opus (4.8) · subagent_type: general-purpose (read-only) or emulator-runner (Wave 2)
constraints: read-only unless Wave 2 emulator; never print secrets/tokens/PII/recordings/raw DB
             content — reference by location only; return the finding schema (§6), not file dumps.
context: this plan §4–5 (targets + ST4S mapping) + the closed known-issues register (dedup).
output: structured findings (schema §6), ranked, with file:line evidence + proposed PoC.
review: Fable dedups → reconciles → adversarially verifies High/Critical → CVSS+ST4S → gate.
```

## Change log

| Date | Change |
|---|---|
| 2026-07-23 | v1.0 — plan created; Wave 0 (5 Opus agents) complete; F-01 source-verified; proposal assessed; RoE set. |
