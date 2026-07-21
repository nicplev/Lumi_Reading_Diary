# Lumi — Production Readiness

**Updated:** 2026-07-21 · **Owner:** Nicholas Plevritis
**Purpose:** one place to see the whole runway — what's done, what's a launch
gate, and what needs a human decision. This is the top-level view; the
detailed source docs are cited per row.

> **Where this is authoritative:** for a status at-a-glance, trust THIS doc, the
> `REMAINING_HARDENING_RUNBOOK.md`, and
> `docs/security/LUMI_SECURITY_HARDENING_CHECKLIST_2026-07-15.md`. The checkbox
> states inside `docs/PRODUCTION_HARDENING_PLAN.md`, `README.md`
> "Development Status", and `PUBLIC_BETA_PLAN.md` are **stale** — do not read
> status from them.

---

## At a glance — three gates hold up almost everything

1. **🔑 Organisation store enrolment (DUNS number).** The Firebase backend is
   live in prod, but **no mobile app has shipped to Apple/Google**. Enrolment
   is blocked on a DUNS number, which cascades into: real code signing, store
   submission/TestFlight, production App Attest / Play Integrity, App Check
   enforcement, live store privacy questionnaires, and final signed-artifact
   scans. Nothing app-facing launches until this clears. **External/business —
   Nic.**
2. **⚖️ Australian privacy counsel (still unappointed).** Blocks approval of the
   PIA, the APP 8 position, and the AI-eval notice/consent — and is the
   accountable-owner gap flagged in P-10. **Nic.**
3. **🤖 AI comprehension eval enablement** is a *separate* track from the core
   app launch. The pipeline is fully built but **dark**; turning it on for any
   school needs counsel sign-off, a consent-enforcement build, representative
   recordings, two residency evidence legs, and per-school DoE screening (§4).

Everything else is either **done** (§1) or **buildable/queued** behind these.

---

## 1. Done — the solid foundation

**Security / authorization perimeter** (strong; independently reviewed)
- ✅ All 2026-07 security criticals fixed + deployed and re-verified still-closed
  (portal cookie bypass, cascade-delete authz, teacher self-provision, reset
  IDOR, code enumeration) — `REMAINING_HARDENING_RUNBOOK.md` §1.
- ✅ In-house dry-run review (2026-07-20/21): no Critical/High; tenant isolation
  sound; **all findings closed** — teacher-scope cluster (#497–#499), unlink
  (#498), email HTML escaping (#506), `/schools` commercial-field lock (#507),
  storage pending-audio overwrite race (fixed in the comprehension-recordings
  work). See `docs/security/PENTEST_DRYRUN_FINDINGS_2026-07-20.md`.
- ✅ **Super-admin portal MFA** — TOTP (authenticator) enforced, encrypted
  secret, peer-reset + break-glass recovery; deployed + live-tested (#501, #505).
- ✅ Deletion cascade extended to AI eval + audio artifacts (#464); tested.

**Backend / infra**
- ✅ Firestore, Storage, ~47 Functions, both portals live in `australia-southeast1`.
- ✅ **Node 22 + firebase-functions v7** across all functions (Phase 5, #249) —
  Node-20 decommission handled.
- ✅ Keyless least-privilege runtime identities; AU-only Secret Manager replicas;
  PITR + restore drill; monitoring + dual-recipient alerts; breach plan.
- ✅ Teacher comprehension-recordings inbox shipped backend/portal side (#503;
  indexes READY, ruleset matches source) — *device QA still open, see §5*.

**QA with physical-device evidence captured** (synthetic/demo data)
- ✅ Physical student + account deletion cascade; offline access-revocation;
  release-mode consent capture; teacher audio playback/deletion; demo portal
  boundary. Automated suites green (Functions, Rules, Storage, integration).

---

## 2. App store launch — the critical path (blocked on the DUNS gate)

All rows are **launch blockers**; most unblock once organisation enrolment clears.
Sources: `LUMI_SECURITY_HARDENING_CHECKLIST_2026-07-15.md`, PIA §7,
`docs/app-store/submission-checklist.md`, `password-autofill-setup.md`.

| # | Item | Status | Owner |
|---|---|---|---|
| S1 | **Apple + Google organisation enrolment (DUNS)** — the root gate | ⛔ blocked | Nic (business) |
| S2 | Android release still **debug-signed**; no Play App Signing fingerprints registered in Firebase | ⛔ | Nic + code (after S1) |
| S3 | Production **App Attest / Play Integrity** attestation evidence | ⛔ (needs S1) | Nic |
| S4 | **App Check enforcement** flip — must stay OFF until store-signed attestation traffic is verified (also closes dry-run finding #8) | ⛔ deferred | Nic + code (after S3) |
| S5 | Final **signed AAB/IPA secret scan** (gitleaks clean on source; signed artifacts pending) | ⛔ (needs S1) | Nic |
| S6 | Live **App Store/Play privacy questionnaires** matching the final binary + release-device network capture | ⛔ (needs S1) | Nic |
| S7 | iOS distribution profile regen (Associated Domains); App Store URL for force-update flow (needs the ASC listing) | ⛔ (needs S1) | Nic |
| S8 | App Store submission mechanics: deploy portal so legal URLs are live, seed demo review account, fill ASC fields, possible in-app "request account deletion" entry (Guideline 5.1.1) | 🔶 partly ready | Nic |

**Already done on the store front:** iOS Privacy Manifest, App Privacy labels
draft, app-review notes + demo seed script, force-update fail-safe (physically
tested), API-key restrictions, Play icon/screenshots.

---

## 3. Needs your sign-off (counsel + owner decisions)

Nothing here is a code task — these are approvals/appointments only.

| # | Decision | Status | Owner |
|---|---|---|---|
| A1 | **Appoint external Australian privacy/legal lead** — recurring blocker (PIA P-10, APP 8 §9) | ✍️ open | Nic |
| A2 | Counsel + owner **approve the PIA** (`PRIVACY_IMPACT_ASSESSMENT.md` §8 — all rows Pending) | ✍️ open | Nic + counsel |
| A3 | Counsel confirm the **APP 8 treatments** (Google/Firebase, SendGrid, school DPA, family/audio notice; §9 all Pending) | ✍️ open | counsel |
| A4 | Retain **account-specific contract/acceptance evidence** (Google, SendGrid, Apple/Google) outside Git | ✍️ open | Nic |

---

## 4. AI comprehension eval — separate enablement track (currently dark)

The whole pipeline is built and merged but **off in prod**
(`platformConfig/aiEvaluation {enabled:false}`, no school entitled, nothing
deployed). These are the gates before it can turn on for **any** school
(`AI_COMPREHENSION_EVAL_CHECKLIST.md` + the B-track drafts).

| # | Gate | Status | Owner |
|---|---|---|---|
| AI1 | Counsel + Nic **approve** the collection notice, AI PIA section, opt-out memo, APP 8 addendum (all headed DRAFT / not in force) | ✍️ open | Nic + counsel |
| AI2 | Set the **collection-notice effective date** (the server-enforced no-backfill floor) + notice delivered to families | ✍️ open | Nic + counsel |
| AI3 | **Build the consent-enforcement slice** — decision recorded (Model C opt-in, first-use parent checkbox); enqueue gate + worker claim re-check + parent-app checkbox + server student flag + tests. **Not built yet.** | 🔶 to build | code (own PR) |
| AI4 | **Residency evidence** — leg 2 (during-ML-processing for `gemini-2.5-flash` @128k) ✅ captured; **leg 3** (Vertex no-training / abuse-logging terms) and **STT product residency terms** still to pin. Until then, tier-2 wording only. | 🔶 partial | Nic |
| AI5 | **5–10 authorised representative child recordings** through STT+Gemini + teacher blind review; freeze v1 rubric/prompt (only synthetic done so far) | ✍️/🔶 open | Nic |
| AI6 | **Per-pilot-school DoE screening** — VIC gov schools out of first cohort (student-audio-into-GenAI restrictions); NSW gov needs departmental assessment. Recommend independent/Catholic cohort first. | ✍️ open | Nic |
| AI7 | Enable pilot school via the audited admin card (terms version) → flip the platform switch → manual deploy sequence | ⛔ after AI1–AI6 | Nic |
| — | Deletion cascade to evals/jobs | ✅ done (#464) | — |
| — | Model choice: `gemini-2.5-flash` retires Oct 2026 — accepted for pilot; revisit before wider rollout | note | Nic |

---

## 5. Device / QA gates still open (need a real device + SMS)

Source: PIA §7, `REMAINING_HARDENING_RUNBOOK.md` §3,
`TEACHER_COMPREHENSION_RECORDINGS_SCREEN_PLAN.md` §14.

- ⛔ **Signed-in account/student deletion device retest** — unchecked in two
  places (PIA §7, checklist P1-2). Prior evidence used an earlier build/harness.
- ⛔ **Comprehension-recordings physical playback/deletion matrix** (iOS +
  Android): playback, URL expiry, backgrounding, headset switch, account
  switching, delete-while-open, retention-expiry-while-open, tablet/text-scale.
- 🔶 Temporary demo book-allocation physical acceptance; full device E2E
  battery (signup A–D, offline log durability, offline scanning, MFA-login
  recovery); release-device network capture to finalize analytics + store
  questionnaires.

---

## 6. Code work buildable now (but can't deploy/enforce until an app ships)

These are agent-buildable; they gate on adoption of a released app, so they sit
behind §2. Source: `REMAINING_HARDENING_RUNBOOK.md` §5.

- 🔶 **Gen1→Gen2 functions migration (Phase 6)** — already substantially done in
  live code (~24 files on v2); finish the remaining legacy imports. No hard
  deadline.
- 🔶 **Hive at-rest encryption** (3.1) — COPPA/GDPR-K; needs a device migration test.
- 🔶 Comprehension-audio **gated storage rule** (#245) — deploy only after app
  adoption; needs on-device playback verify + `signBlob` IAM.
- 🔶 **MFA-login recovery** flow (4.10) for the mobile app.

---

## 7. ST4S / edtech assessment track (parallel, not a launch blocker)

Source: `docs/privacy/ST4S_READINESS_PREP.md`, `RESPONSIBLE_AI_POLICY.md`.

- ✅ Pre-assessment enquiry **sent to ST4S** (2026-07-20) — **awaiting their
  reply** on the AI excluded-list / STT exemption, which gates the rest.
- ✍️ **Adopt the Responsible AI policy** — drafted v0.1; needs the director's
  formal adoption (satisfies ST4S control AI_T1#).
- 🔶 Run the free **ST4S Readiness Check** (declare the AI feature; expect Tier 1).
- 🔶 **Commission the independent penetration test** — scoping pack + vendor
  shortlist + RFQ drafted; RFQ **not yet sent**. The in-house dry-run cleared
  the floor, but ST4S EV10 needs an *external* report.
- 🔶 Produce the remaining gap docs: InfoSec policy, BCP/DR, Secure SDLC +
  patch mgmt, HR controls, WCAG evidence.

---

## Legend & sources

**Status:** ✅ done · 🔶 in progress / partial · ⛔ blocker · ✍️ needs a human
decision. **Owner:** "Nic" = owner/business/device action; "counsel" =
external legal; "code" = agent-buildable.

Key source docs: `REMAINING_HARDENING_RUNBOOK.md` ·
`docs/security/LUMI_SECURITY_HARDENING_CHECKLIST_2026-07-15.md` ·
`docs/security/PENTEST_DRYRUN_FINDINGS_2026-07-20.md` ·
`docs/privacy/PRIVACY_IMPACT_ASSESSMENT.md` ·
`docs/privacy/APP_8_CROSS_BORDER_DISCLOSURE_LAWYER_BRIEF.md` ·
`docs/AI_COMPREHENSION_EVAL_CHECKLIST.md` + the `AI_EVAL_*` drafts ·
`docs/privacy/ST4S_READINESS_PREP.md` · `docs/app-store/submission-checklist.md` ·
`docs/TEACHER_COMPREHENSION_RECORDINGS_SCREEN_PLAN.md`.
