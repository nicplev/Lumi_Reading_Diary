# AI Comprehension Evaluation — Collection-Notice Update (Parent-Facing)

> **DRAFT — pending counsel + Nic approval; not in force.**
> Nothing in this document may be published, sent to a school, or relied on until
> Australian privacy counsel and the Lumi owner (Nic) have approved it and an
> effective date has been set. The AI evaluation feature remains OFF in
> production (`platformConfig/aiEvaluation {enabled:false}`).

**Prepared:** 20 July 2026
**Prepared for:** Nic (owner) and Australian privacy counsel
**Purpose of this document:** the parent/carer-facing collection-notice update
required before the AI comprehension-evaluation feature can be enabled for any
school (APP 5 notice for an APP 6 secondary use). Companion documents:
`AI_EVAL_PIA_SECTION_DRAFT.md` (PIA section), the dated addendum in
`APP_8_CROSS_BORDER_DISCLOSURE_LAWYER_BRIEF.md`, and
`AI_EVAL_OPT_OUT_DECISION_MEMO.md` (opt-out model decision, open).

---

## Part A — Drafting notes (not for publication)

1. **Why a new notice is required.** The comprehension-recording feature was
   collected for the purpose of *teacher listening and review*. Having an AI
   system transcribe and evaluate those recordings is a **new purpose (APP 6
   secondary use)**. Families must be told before any recording is collected
   for this purpose, and no recording made before the notice's effective date
   will ever be processed (the no-backfill guarantee below is enforced
   server-side, not just promised).
2. **Wording constraints (approved, non-negotiable):**
   - Use exactly: **"no student identifiers attached; content may incidentally
     contain personal information."** Never describe voice, transcript or
     evaluation content as "anonymised" or "de-identified".
   - Residency claims use the **tier-2 wording** from
     `docs/AI_EVALUATION_GEMINI_PLAN.md` §6 until the during-ML-processing
     residency evidence is captured into `docs/privacy/vendor-evidence/`:
     *"processed via Google Cloud's Sydney regional endpoint; Google's formal
     in-region processing commitment for generative AI in Australia is
     pending."* Never claim "your data never leaves Australia" as an
     unqualified absolute. If the tier-1 evidence lands before publication,
     counsel may upgrade the wording to the tier-1 sentence in §6 of the plan.
   - No safeguarding/monitoring claims. No numeric scores are shown anywhere;
     do not imply scoring or ranking.
3. **Placeholders that MUST be resolved before publication:**
   - `[EFFECTIVE DATE]` — set by Nic when the notice ships; this timestamp is
     also the server-enforced eligibility floor for processing.
   - `[OPT-OUT / CONSENT WORDING]` — pending the opt-out model decision
     (`AI_EVAL_OPT_OUT_DECISION_MEMO.md`). The placeholder paragraph below is
     written for the per-family opt-out model and must be replaced or confirmed
     once Nic decides.
   - `[SCHOOL NAME]` / `[SCHOOL CONTACT]` — per school at publication.
4. **Delivery.** The school delivers this notice to families (the existing
   audio-recording first-enable gate already records the school's commitment to
   notify families). Lumi's own privacy policy (school-portal legal page and
   marketing site) must be updated consistently — a deploy-inert draft of the
   portal privacy-page section accompanies this PR.
5. **Retention numbers cited below** are the operational values in
   `docs/AI_EVALUATION_RUNBOOK.md` §2/§5 (transcript 90 days; evaluation 730
   days; audio per the school's existing 30/90/365-day setting). Any change to
   those values requires privacy review and a notice update.

---

## Part B — Parent/carer notice text (DRAFT for publication)

### Update to how [SCHOOL NAME] uses Lumi comprehension recordings

**From [EFFECTIVE DATE], with the school's approval, Lumi will offer a new,
optional AI-assisted comprehension feature.** This notice explains what changes,
what does not change, and the choices available to you.

#### What already happens today

If your school has turned on comprehension recordings, your child can record a
short spoken answer to a reading question (for example, "What happened in the
story?"). The recording can be listened to by your child's teacher and school
administrators. Recordings are kept for the deletion period your school chose
(30, 90 or 365 days) and are stored in Australia.

#### What is new

From the effective date, new recordings may also be processed as follows:

1. **Transcription.** The recording is converted to text by Google Cloud's
   speech-to-text service in Sydney, Australia.
2. **AI evaluation.** The text of your child's answer, together with the
   teacher's question, is evaluated by an AI model (Google Gemini, running on
   Google Cloud's Vertex AI platform) against a simple comprehension rubric.
3. **Teacher-only summary.** The result is a short, qualitative summary for
   your child's teacher — for example, the comprehension areas your child
   showed, with short quotes from the transcript as evidence. There are no
   marks, scores or grades, and results are never shown to students.

The request sent to the AI service has **no student identifiers attached;
content may incidentally contain personal information** (for example, if your
child says a friend's name in their answer, that name will be in the recording
and transcript). Lumi additionally replaces the student's registered name with
"[the student]" in the text sent to the AI model.

#### The teacher stays in charge

The AI summary is **decision support for your child's teacher, not an
assessment of your child**. Teachers are told the summary may be inaccurate and
are directed to listen to the recording and use their professional judgement
before acting on it. AI results are never used for formal assessment, grading
or reporting, and are never shown to your child. Teachers can disregard any
result, and unclear or unusable recordings are flagged for teacher review
rather than given an invented result.

#### Where the information is processed

Recordings, transcripts and evaluations are stored in Google Cloud's Australian
(Sydney) region, and transcription and AI evaluation are **processed via Google
Cloud's Sydney regional endpoint. Google's formal in-region processing
commitment for generative AI in Australia is pending publication; Lumi's
privacy impact assessment records the details.** No new company receives your
child's information: the AI processing runs on the same Google Cloud services,
and under the same Google Cloud terms, that already host your school's Lumi
data. Google does not use this content to train its AI models.

#### How long information is kept

| Item | Kept for |
|---|---|
| Voice recording | Your school's existing setting (30, 90 or 365 days), unchanged |
| Transcript (text of the answer) | 90 days, then removed from the evaluation record |
| Teacher-only evaluation summary | Up to 730 days (2 years), then deleted |

If your child's student record is deleted, associated recordings are deleted as
part of the existing deletion process. Deletion of evaluations and related
processing records is part of the same commitment. [Drafting note: the
deletion-cascade extension covering evaluation documents is a pre-enablement
engineering gate — see PIA section; confirm complete before publication.]

#### Recordings made before this notice

**No recording made before [EFFECTIVE DATE] will ever be processed by the AI
feature.** This is enforced by Lumi's servers, not just promised: recordings
made before the effective date are not eligible for processing under any
circumstances, including at a school's or administrator's request.

#### Your choices

[OPT-OUT / CONSENT WORDING — placeholder pending the opt-out model decision
(`AI_EVAL_OPT_OUT_DECISION_MEMO.md`). Draft wording for the per-family opt-out
model, to be confirmed or replaced:]

> If you do not want your child's recordings processed by the AI feature, tell
> [SCHOOL CONTACT] and it will be turned off for your child. Your child can
> keep using Lumi exactly as before — including making recordings for their
> teacher to listen to — and opting out has no effect on your child's access
> to any part of the reading diary.

#### Questions or concerns

Contact [SCHOOL CONTACT], or Lumi at support@lumi-reading.com. Lumi's full
privacy policy is available in the app and at the school portal. If you are not
satisfied with a response, you may contact the Office of the Australian
Information Commissioner (oaic.gov.au).

---

## Part C — Approval record

| Role | Name | Decision | Date |
|---|---|---|---|
| Lumi owner | Nicholas Plevritis | Pending | — |
| Australian privacy counsel | Pending | Pending | — |
| Effective date set | — | Pending | — |
| Opt-out model resolved (B3 memo) | — | Pending | — |
