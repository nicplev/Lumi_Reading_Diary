# Decision Memo — Opt-Out / Consent Model for AI Comprehension Evaluation

> **DRAFT — pending counsel + Nic approval; not in force.**
> This memo frames a decision that belongs to Nic (with counsel). It builds
> nothing and changes no behaviour; the feature remains dark. Companion
> documents: `AI_EVAL_COLLECTION_NOTICE_DRAFT.md` (carries the placeholder this
> decision resolves), `AI_EVAL_PIA_SECTION_DRAFT.md` §4 (APP 6 analysis),
> `AI_EVAL_STATE_DOE_SCREENING_MEMO.md` (sector expectations).

**Prepared:** 20 July 2026
**Decision owner:** Nic (with Australian privacy counsel)
**Decision needed before:** any school entitlement is enabled; the collection
notice cannot be finalised until the "Your choices" paragraph is resolved.

---

## 1. The decision

AI evaluation is a new secondary purpose (APP 6) for comprehension recordings.
The updated collection notice (B1 draft) tells families it is happening. The
open question is **what choice families get, and where the product enforces
it**. Three viable models follow; each is compatible with the shipped
architecture, and the same single enforcement point serves models A and C.

### The enforcement point (common to A and C)

`functions/src/ai_evaluation/enqueue.ts` → `enqueueAiEvalJobCore()` runs the
fail-closed gate chain **platform switch → school entitlement → log/receipt
validation** before a job is created. A student-level flag slots in
immediately after the `studentId` is derived and validated (today the
`if (!studentId || !classId) return "skipped:invalid_log";` check, currently
lines 127–130): read `schools/{schoolId}/students/{studentId}`, check the
flag, and return a new `EnqueueOutcome` (e.g. `"skipped:family_opt_out"`)
without creating a job. Because no job document is ever created, nothing
downstream (worker, sweep, caps, metering) needs to know the model exists.

Defence in depth: the worker re-checks the platform and school gates at claim
time (`functions/src/ai_evaluation/worker.ts`, the "Re-check gates at claim"
block) so a family choice made *after* a job was queued still takes effect;
the student-flag read joins that same block (one extra document read per job).

Storage: a server-owned field on the student document (e.g.
`aiEvaluation: {optOut: true, recordedAt, recordedBy}`), written only via the
school portal / support tooling, denied to client writes by the existing
server-owned-field rule pattern. No index or rules-read changes: the reads
happen in privileged server code.

## 2. The three models

### Model A — per-family opt-OUT (default in, notice + practical opt-out)

Every student at an enabled school is eligible once the notice is in force;
a family can opt their child out at any time via the school (or Lumi support),
and the flag stops future processing at both enqueue and claim.

- **Privacy strength: medium.** Individual choice is real and technically
  enforced, but requires the family to act. The core service is unaffected by
  opting out (recordings still reach the teacher's ears — only AI processing
  stops), which is exactly the "practical opt-out route without loss of the
  core service" the PIA requires.
- **APP alignment.** Defensible under APP 6 as a use within updated notice +
  reasonable expectations, *provided* counsel accepts notice-plus-opt-out as
  sufficient for child voice data in the relevant school contexts. The
  no-backfill guarantee materially helps: nothing recorded before the notice
  is ever processed, so no family is retroactively included.
- **Teacher/parent UX cost: low.** No consent-collection burden; class
  coverage starts near-complete; the teacher surface needs no per-student
  explanation of missing evals beyond an "opted out" state (worth adding so
  absence reads as choice, not error).
- **Implementation cost in this codebase: small — one slice.** The enqueue
  gate + worker claim re-check + `EnqueueOutcome` member + unit tests
  (gate-order tests already exist as the template in
  `functions/test/ai_evaluation_enqueue.test.js`), plus a school-portal
  surface for recording the opt-out and a rules test proving clients cannot
  write the field.

### Model B — whole-school authority via the notice (no per-family flag)

The school's decision to enable the feature, plus the delivered notice, is
the whole consent story; objecting families are handled by the school outside
the product.

- **Privacy strength: weakest.** No technical enforcement of an individual
  objection. The only product-level answer to "not my child" is disabling
  that child's *recording* feature entirely — which takes away the
  teacher-listening value the family already had, punishing the objection.
- **APP alignment: poor fit for this purpose.** For a new secondary use of
  children's voice data, "the school decided for everyone" sits uneasily with
  APP 6 reasonable expectations and with the Australian Framework's emphasis
  on family transparency and contestability; expect counsel and government-
  sector screening to push back.
- **UX and implementation cost: zero** — this is what is already built (the
  school entitlement gate). That is its only advantage.

### Model C — explicit per-family opt-IN (consent required)

Only students whose family has affirmatively agreed are processed. Same flag
mechanism as Model A with the default inverted: the enqueue/claim checks
require `consent === true`, and a missing flag means **not** processed
(fail-closed at family level, matching the pipeline's gate philosophy).

- **Privacy strength: strongest.** Express, recorded, revocable consent per
  family; the cleanest possible APP 6 position and the easiest story for any
  DoE or sector screening that expects active consent for AI processing of
  student voice. The DoE screening memo found this expectation is **already
  mandatory in one target jurisdiction**: Victoria's government-school GenAI
  policy requires opt-in parental consent for any GenAI tool needing
  personal information beyond a school email + password — so for any future
  VIC government school, Model C is not a choice but a requirement.
- **UX cost: high.** The school must collect and record consent per family
  (realistically a portal-recorded consent register maintained by the school,
  mirroring the existing audio first-enable authority-evidence pattern).
  Partial participation is certain: teachers see patchy class coverage,
  term reports hit "insufficient data" more often, and the pilot's
  quality/cost signal thins out.
- **Implementation cost: medium.** The gate itself is identical to Model A
  (same slice); the consent-register surface (per-student recording of
  consent with who/when, plus CSV import or roster ticking) is the real work
  — roughly one additional portal slice.

## 3. Comparison at a glance

| | A: opt-out | B: school-wide | C: opt-in |
|---|---|---|---|
| Individual choice enforced in product | Yes | No | Yes |
| APP 6 defensibility for child voice | Medium–high (counsel call) | Low | Highest |
| Sector-screening friction (gov schools) | Some | High | Lowest |
| Parent/school effort | Low | None | High |
| Class coverage in pilot | Near-full | Full | Partial |
| Engineering | Small slice | None | Small slice + consent register |

## 4. Recommendation (advisory — the choice is Nic's)

**Model A (per-family opt-out) for the pilot**, on three conditions:

1. counsel confirms notice-plus-practical-opt-out is a sufficient APP 6 basis
   for the pilot schools' contexts (sector and state matter — see the DoE
   screening memo);
2. the teacher surface shows an explicit "family opted out" state so absence
   of evals is legible; and
3. the enforcement flag is built so the default is a one-line flip — if any
   pilot school's sector, state scheme, or counsel requires express consent,
   Model C activates with the same flag and gate, plus the consent-register
   surface.

Model B is not recommended as the end state: it is only acceptable as the
implicit interim state while the feature is dark, and it leaves no good
answer for an objecting family.

Sector overrides from the DoE screening memo
(`AI_EVAL_STATE_DOE_SCREENING_MEMO.md`): Victorian government schools
mandate opt-in consent (and are in any case deferred from the first pilot
cohort pending departmental clearance); NSW government schools require
explicit per-app parental consent plus departmental GenAI assessment before
any pilot. For the recommended first cohort — independent and Catholic-system
schools — Model A stands, subject to counsel. Model C per jurisdiction,
Model A elsewhere, is a workable hybrid because the flag mechanism is
shared and only the default flips.

## 5. What happens after the decision

1. Nic records the decision (+ counsel's basis) in this memo's approval table.
2. The `[OPT-OUT / CONSENT WORDING]` placeholder in
   `AI_EVAL_COLLECTION_NOTICE_DRAFT.md` and the portal privacy-section draft
   is resolved to match.
3. The enforcement slice is scheduled (own branch/PR per house workflow):
   enqueue gate + worker claim re-check + portal recording surface + tests.
   It must merge before any school entitlement is enabled.

## 6. Decision recorded — 20 July 2026

**Nic chose Model C (explicit per-family opt-IN)**, with a specific capture
UX: a consent checkbox is shown to the parent in the app the **first time
they tap "use this recording"**. If the parent does not accept, the recording
is handled exactly as today — the teacher can listen to it — but **no AI
transcription or evaluation ever occurs** for that child. Absent consent =
not processed (fail-closed at the family level, matching the pipeline's gate
philosophy). This supersedes §4's advisory recommendation of Model A, and it
automatically satisfies the Victorian government-school opt-in mandate.

Implementation implications (recorded for the build slice — **not built by
this track**):

- Consent is captured in the **parent app** at first recording use and must
  be stored **server-side** on the student record (server-written; client
  writes denied), because enforcement happens in privileged server code:
  the `enqueueAiEvalJobCore()` gate and the worker claim-time re-check (§1).
- The enqueue outcome for a non-consenting family should be its own enum
  member (e.g. `"skipped:no_family_consent"`) so ops metrics distinguish
  choice from error.
- The teacher surface should show a "family has not opted in" state so
  missing evaluations read as choice, not failure.

Open sub-questions for counsel / the design slice:

1. Consent scope: per student (any linked parent can grant?) or per parent
   account — and what happens when two linked parents answer differently.
2. Withdrawal path: how a parent changes their mind in-app, and whether
   withdrawal also removes already-produced evaluations or only stops new
   processing (current retention design: stops new processing; deletion on
   request via the school).
3. Checkbox wording — must be approved by counsel with the notice; the
   notice draft (`AI_EVAL_COLLECTION_NOTICE_DRAFT.md`) carries the draft
   consent language.
4. Whether the first-use prompt is also re-shown after material changes
   (model change, retention change) — recommended: yes, treated like a
   notice re-issue.

## 7. Approval record

| Decision | Chosen model | Basis | Approver | Date |
|---|---|---|---|---|
| Opt-out / consent model | **Model C — per-family opt-in via first-use parent consent checkbox** | Owner decision; counsel ratification pending | Nic | 20 July 2026 |
