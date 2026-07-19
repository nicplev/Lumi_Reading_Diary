# PIA Section — AI Comprehension Evaluation (Gemini on Vertex AI, Australia)

> **DRAFT — pending counsel + Nic approval; not in force.**
> This section is drafted for inclusion in `PRIVACY_IMPACT_ASSESSMENT.md`
> (as a new numbered section, superseding row "AI transcript/evaluation" of the
> §2 purpose table and risk P-04). It updates the working AI PIA draft in
> `docs/AI_EVALUATION_PLAN.md` for the adopted all-Australian Gemini-on-Vertex
> design (`docs/AI_EVALUATION_GEMINI_PLAN.md`, decision date 2026-07-19).
> The feature remains OFF in production and no school may be enabled until the
> approvals in §11 below are recorded.

**Drafted:** 20 July 2026 · **Author:** implementation session for Nic's review
**Pipeline implementation state:** fully merged, dark (PRs #454–#462); nothing
deployed; kill switch `platformConfig/aiEvaluation {enabled:false}` live in
production; no school entitled.

---

## 1. Project description and purpose

The AI comprehension-evaluation feature helps an authorised teacher review a
student's spoken answer to a teacher-set reading-comprehension question. For
each eligible new recording:

1. the validated recording is transcribed by **Google Cloud Speech-to-Text V2**
   at the `australia-southeast1` (Sydney) regional endpoint;
2. the transcript and the captured question are evaluated by **Google Gemini
   (`gemini-2.5-flash`) on Vertex AI** at the `australia-southeast1` regional
   endpoint against a fixed comprehension rubric; and
3. a **teacher/school-admin-only** evaluation document is written: qualitative
   level, criterion evidence quoting the transcript, confidence, review flags,
   and a short summary. No numeric score is user-visible anywhere.

The purpose is **decision support** for the teacher. It is not, and must not
become, formal assessment, grading, ranking, parent-facing reporting without
teacher review, or any form of monitoring/safeguarding function. The teacher
can inspect, contest, override or ignore every result; unassessable input
produces review flags, never invented results.

## 2. Necessity and data minimisation

Necessary inputs are limited to: the audio answer; the captured question text
(≤200 chars); the minimum rubric; and provider/model/version identifiers for
audit. Explicitly excluded from provider requests: student name, UID, email,
school/class identifiers, parent details, reading history, and all unrelated
profile data. The student's registered name(s) are redacted to "[the student]"
in text sent to the model — retained even though processing is in Australia,
because minimisation is an APP obligation regardless of geography.

**Approved wording (mandatory, everywhere):** "no student identifiers attached;
content may incidentally contain personal information." The words "anonymised"
and "de-identified" are prohibited for this content.

## 3. Data flow and locations (adopted design)

```text
Australian Firebase Storage (validated canonical audio, generation-pinned)
  -> Australian Cloud Function worker (australia-southeast1)
  -> Google Speech-to-Text V2, australia-southeast1 regional endpoint
  -> transcript held in server-only job state (never client-readable)
  -> Gemini on Vertex AI, australia-southeast1 regional endpoint
  -> schools/{schoolId}/comprehensionEvals/{logId} (teacher/schoolAdmin-only)
```

Differences from the superseded working draft (`docs/AI_EVALUATION_PLAN.md`):

- **The Anthropic (US) evaluation stage is deleted.** No Anthropic DPA, ZDR
  pinning, API secret, or US processing exists in the adopted design. The
  evaluation stage authenticates with the Functions runtime service account
  and a least-privilege custom IAM role (`lumiAiEvalPredictor`,
  `aiplatform.endpoints.predict` only); **no API key or secret exists**.
- **No new vendor enters the register.** Vertex AI is a Google Cloud service
  under the same Google Cloud Data Processing Addendum that already governs
  Lumi's Firebase data. (The vendor register's "Anthropic — Blocked" row is
  superseded and should be updated when this section is adopted.)
- The `location` is pinned in code to `australia-southeast1`; server config
  rejects any other region at cold start, and the model must be on a
  code-reviewed allowlist (currently exactly `['gemini-2.5-flash']`). The
  global endpoint is treated as a residency violation, not a fallback.

### Residency evidence status (claims ladder)

Live probe evidence (2026-07-19, `AI_EVALUATION_GEMINI_PLAN.md` §12): the
Sydney regional Vertex endpoint serves `gemini-2.5-flash` (HTTP 200 with the
exact production request shape; all other Gemini models 404 — the probe
discriminates), structured output and injection resistance verified, IAM role
created and verified.

**Still open:** the dated capture of Google's **during-ML-processing** (not
just at-rest) residency commitment for `australia-southeast1`, and the pin of
Vertex generative-AI data-governance terms (no training on customer content;
abuse-monitoring/logging posture) into `docs/privacy/vendor-evidence/`.

**Until both are captured, all documents use the tier-2 claim** ("processed via
Google Cloud's Sydney regional endpoint; Google's formal in-region processing
commitment for generative AI in Australia is pending"), never an unqualified
"data never leaves Australia". See plan §6 for the full ladder.

## 4. APP analysis

- **APP 3 (collection):** no new collection from individuals. The feature
  processes recordings already collected under the school-authorised
  comprehension-recording feature, plus the teacher's question. Necessity is
  bounded by §2; the feature is off by default at platform and school level.
- **APP 5 (notice):** an updated collection notice is required and drafted
  (`AI_EVAL_COLLECTION_NOTICE_DRAFT.md`). The school delivers the notice to
  families; the first-enable portal gate already records the school's
  commitment to notify. The notice states purpose, processing, location
  (tier-2 wording), retention and choices.
- **APP 6 (use/disclosure — the central analysis):** AI evaluation is a **new
  secondary purpose** for recordings collected for teacher listening. Lumi's
  position (for counsel confirmation) is that the use may proceed only with:
  (a) the updated APP 5 notice in force before any eligible recording is made,
  (b) the server-enforced **no-backfill guarantee** (recordings pre-dating the
  notice's effective date are never processed, with no administrative
  override), and (c) the opt-out/consent model selected in
  `AI_EVAL_OPT_OUT_DECISION_MEMO.md` and implemented before enablement.
  Whether notice-plus-opt-out is sufficient or express consent (opt-in) is
  required for some school contexts is a counsel decision.
- **APP 8 (cross-border):** **negative finding proposed — no overseas
  disclosure occurs in the AI pipeline.** All three processing stages (STT,
  evaluation, narrative) run at Sydney regional endpoints under the existing
  Google Cloud terms. This finding is **contingent on the §3 residency
  evidence rows being captured**; until then the position is "regional
  endpoint verified; formal in-region ML-processing commitment pending". The
  finding is recorded as a dated addendum to
  `APP_8_CROSS_BORDER_DISCLOSURE_LAWYER_BRIEF.md`. Pre-existing platform
  exceptions (US Firebase Authentication, global required logs, SendGrid, FCM)
  are unchanged by this feature and remain covered by the main brief.
- **APP 10 (quality):** evaluations are qualitative, flagged when uncertain,
  and carry the mandatory disclaimer ("AI-generated assessment — may be
  inaccurate. Listen to the recording and use your professional judgement
  before acting."). A representative-recordings accuracy review with teacher
  blind-review is a pre-enablement gate; the adversarial prompt-regression
  suite (10/10 pass, live 2026-07-19) guards injection and invented-evidence
  failure modes on every prompt/model change.
- **APP 11 (security):** teacher reads are class-scoped and proven by rules
  tests (parents denied; cross-class denied; 145/145 rules suite); all AI
  documents are server-written; jobs/transcripts live in deny-all collections;
  transcripts never enter logs, analytics or error messages (source-wide
  log-safety regression). Processing identity is a keyless least-privilege
  service account.
- **APP 11.2 (retention/destruction):** transcript cleared from the eval doc
  after **90 days**; whole evaluation document deleted after **730 days**
  (stated in the notice; changes require privacy review); classification cache
  ~365 days, containing no verbatim student content; audio retention is the
  school's existing 30/90/365-day setting, unchanged. Retention is enforced by
  a daily cron (03:30 Sydney) with monotonic-cursor sweep. **Open gate:** the
  student/account deletion cascade must be extended to evaluation and job
  documents before any school is enabled (runbook §5.5) — this is an
  engineering pre-enablement blocker, tracked on the checklist.
- **Children's best interests / Children's Online Privacy Code (exposure
  draft):** the feature defaults off at two levels, collects nothing new,
  shows children no AI output, makes no automated decisions with legal or
  similarly significant effect, and preserves the core reading-diary service
  for families who opt out. Re-check applicability when the Code is registered
  (due by 10 December 2026).

## 5. Safeguards implemented (verifiable in the merged code)

- **Fail-closed gating at three points:** platform kill switch → school
  entitlement at enqueue (`functions/src/ai_evaluation/enqueue.ts`), both
  re-checked at worker claim time; missing/malformed config means OFF.
- **No-backfill enforcement:** jobs are created only by the audio-confirmation
  flow for newly validated recordings; there is no backfill path in the code,
  and job creation requires a current validated canonical receipt.
  [Counsel/Nic note: the notice-effective-date floor should additionally be
  recorded in ops config at enablement so eligibility is provably tied to the
  published date.]
- **Identifier exclusion + name redaction** in provider requests (§2).
- **Injection resistance:** transcript is delimited DATA, never instructions;
  live adversarial regression 10/10; schema-bounded structured output with
  server-side re-validation.
- **Concerning content handling:** provider safety blocks map to
  teacher-review flags (`concerning_content`), storing only the enum reason,
  never the blocked content.
- **Spend/abuse controls:** per-school daily caps, derived global cap
  (sharded), billing budget alerts, quota-429 deferral; teacher-visible
  "couldn't evaluate" terminal state instead of silent retry loops.
- **Auditability:** every eval stamps model, promptVersion, rubricVersion;
  entitlement and kill-switch changes are audit-logged; per-school usage
  metering supports invoice reconciliation without content access.

## 6. What this feature does NOT do (bright lines)

No numeric scores user-visible · no parent/student-visible AI output · no
formal assessment or automated decision-making about a child · no
safeguarding/monitoring claims · no training of models on student content ·
no processing of pre-notice recordings · no "anonymised" claims · no
fallback to non-Australian endpoints (outage posture is "safe to wait").

## 7. Risk register updates

Replaces P-04 of the main PIA risk register and adds AI-specific rows.
Likelihood/impact rated after current controls.

| ID | Risk | L | I | Treatment / required before enablement | Status |
|---|---|---|---|---|---|
| P-04 (revised) | Child content processed by AI without adequate notice/authority | Low (blocked by design) | High | Kill switch + entitlement fail-closed; approved notice with effective date; opt-out model implemented; no-backfill floor enforced; counsel sign-off | Blocked until approvals |
| P-04a | Residency claim overreach (claim exceeds captured evidence) | Medium | Medium | Claims ladder (plan §6); tier-2 wording mandatory until during-ML-processing evidence captured and dated in vendor-evidence | Open — evidence capture pending |
| P-04b | Incorrect/misleading evaluation acted on by a teacher | Medium | Medium | Teacher-in-the-loop framing + mandatory disclaimer; qualitative levels only; review flags; representative-recordings accuracy gate with teacher blind-review; feedback loop in pilot | Accuracy gate pending recordings |
| P-04c | Prompt injection or adversarial audio alters evaluation policy | Low | Medium | Delimited data prompt; schema-bounded output; server re-validation; live adversarial suite 10/10 required on every prompt/model change | Controlled; re-run on change |
| P-04d | Identifier leakage into provider requests | Low | High | Request construction excludes identifiers; name redaction; unit tests on request shape; log-safety regression | Controlled |
| P-04e | Excess retention of transcripts/evals | Low | Medium | 90d/730d retention crons merged; periods stated in notice; deletion-cascade extension to evals/jobs REQUIRED pre-enablement | Cascade extension open |
| P-04f | Model lifecycle: pinned model retired or successor global-only | Medium | Medium | Code allowlist; term-boundary succession watch (runbook §6); `gemini-2.5-flash` retires Oct 2026 — accepted for pilot only, revisit before wider rollout; HOLD posture defined | Accepted for pilot |
| P-04g | Provider safety filters false-positive on child speech | Medium | Low | Blocks map to review flags, not errors; `safetyBlocks` counter watched in pilot week 1 | Pilot metric |

## 8. Consultation

Internal: owner (Nic) — decisions recorded in the Gemini plan. External (all
pending): Australian privacy counsel; pilot-school principals (per-school
screening via `AI_EVAL_STATE_DOE_SCREENING_MEMO.md`); pilot families (via the
notice and the selected opt-out/consent route).

## 9. Pre-enablement gate summary (all must hold before ANY school is enabled)

1. Counsel + Nic approve: this PIA section, the collection notice (with
   effective date), the opt-out model, and the APP 8 addendum position.
2. Residency during-ML-processing evidence + data-governance terms captured,
   dated, into `docs/privacy/vendor-evidence/`; claims wording tier confirmed.
3. Deletion-cascade extension to evals/jobs implemented and tested.
4. 5–10 authorised representative recordings pass the teacher blind-review
   accuracy gate; rubric/prompt frozen (regression suite green).
5. State/sector DoE screening completed for each pilot school.
6. School entitlement enabled via the audited super-admin card (terms version
   recorded), then the platform switch — in that order, and reversibly.

## 10. Ongoing review triggers

Any change to: model (term boundaries only, via allowlist PR + probe
evidence), prompt/rubric versions, retention values, opt-out model, residency
evidence status, or Google's data-governance terms; plus registration of the
Children's Online Privacy Code; plus quarterly while the pilot runs.

## 11. Approval record

| Role | Name | Decision | Date |
|---|---|---|---|
| Product/privacy owner | Nicholas Plevritis | Pending | — |
| Technical/security reviewer | Pending | Pending | — |
| Australian privacy counsel | Pending | Pending | — |
