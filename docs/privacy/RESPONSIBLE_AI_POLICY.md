# Responsible AI Policy — Lumi Education Pty Ltd

> **DRAFT v0.1 — pending formal adoption by the director.** Once adopted,
> replace this banner with the adoption record in §14 and export a dated PDF
> for the ST4S evidence pack (this document answers ST4S AI-module control
> AI_T1 and Responsible AI evidence item E5).

**Entity:** Lumi Education Pty Ltd (trading as Lumi Reading), ABN 45 700 349 015
**Product:** Lumi — a reading-diary service for primary schools (parent and
teacher apps, school portal)
**Policy owner:** Nicholas Plevritis, Director
**Prepared:** 20 July 2026 · **Review cycle:** at least every 12 months (§13)

---

## 1. Purpose and scope

This policy governs every use of artificial intelligence in Lumi's products
and operations: current features, future features, and AI tools used in
developing and operating the service. It exists to keep Lumi's use of AI
consistent with the Australian Framework for Generative AI in Schools, the
Australian Privacy Principles, the Voluntary AI Safety Standard, and the
expectations of the schools and families Lumi serves.

At the date of this policy, Lumi has exactly one AI feature: the **AI
comprehension evaluation** (student reading recording → speech-to-text
transcription → rubric-based evaluation by a large language model →
teacher-only qualitative summary). It is fully built but **not enabled for
any school**; enabling it is gated on the approvals in §8. No other Lumi
feature uses AI. Any new AI feature requires a documented assessment against
this policy before development begins (§12).

## 2. Principles

Lumi commits to these principles, in this order of precedence when they
conflict:

1. **Children's best interests first.** AI must never create risk, pressure
   or judgement directed at a child. Lumi's AI output is never shown to
   students.
2. **Human accountability.** A qualified human — the child's teacher — owns
   every educational judgement. AI output is decision support that the
   teacher can inspect, contest, override or ignore. Lumi (the company)
   remains accountable for the AI systems it deploys; accountability is
   never delegated to a model or a vendor.
3. **Privacy and minimisation.** AI processing uses the minimum data
   necessary, under the consent model families were told about, with
   identifiers excluded and names redacted, regardless of where processing
   occurs.
4. **Transparency.** Schools and families are told, in plain language, what
   the AI does, what it processes, where, for how long, and what their
   choices are — before it applies to them.
5. **Safety and reliability.** AI behaviour is tested adversarially before
   release and monitored in operation; unclear or unusable input produces a
   flagged review state, never an invented result.
6. **Fairness.** AI output is qualitative, evidence-quoted and reviewable;
   no numeric scores are shown to any user; known failure modes (speech
   recognition of young children, disfluency, adult prompting) are handled
   as review states rather than penalised.

## 3. Bright lines — what Lumi's AI will never do

These are absolute constraints. Deviation from any of them is an incident
under §10 and requires this policy to be re-approved before proceeding.

- **No formal assessment, grading, ranking or reporting decisions.** AI
  output must never be the basis of a formal educational record, and is
  never used in isolation for any decision with a real effect on a child.
- **No AI output shown to students or parents.** Teacher and school-admin
  eyes only (any future change requires a new privacy assessment, notice
  update and policy re-adoption).
- **No numeric scores visible to any user, in any surface or export.**
- **No inference of ability, disability, learning difficulties, emotion or
  wellbeing.** The evaluation schema contains no such fields, and prompts
  instruct assessment of comprehension of the specific text only.
- **No biometric identification or voice-prints.** Speech processing is
  transcription only; no speaker recognition, and no biometric templates
  are created or stored.
- **No training of models on student content.** Provider terms must exclude
  training on Lumi's data; this is verified and evidenced, not assumed.
- **No advertising, profiling or sale of data — with or without AI.**
- **No monitoring or safeguarding claims.** Lumi's AI is not a surveillance
  or child-safety detection system and is never marketed as one.
- **No processing without the family's opt-in consent**, and no processing
  of any recording made before the collection notice's effective date
  (no backfill, with no administrative override).
- **No processing outside Australia.** AI endpoints are pinned in code to
  `australia-southeast1`; a non-Australian endpoint is treated as a defect,
  not a fallback. Residency claims follow the evidence-tiered wording in
  the PIA; the word "anonymised" is never used for voice or transcript
  content.

## 4. Data handling for AI

- **Inputs are minimised** to the audio answer, the teacher's question, the
  rubric and audit metadata. Student name, identifiers, class/school
  context, and unrelated records are excluded from provider requests; the
  student's registered name is redacted to "[the student]" before any text
  reaches a model. Approved description: "no student identifiers attached;
  content may incidentally contain personal information."
- **Prompts and outputs are never logged** to application logs, analytics,
  crash reporting or support tooling. A source-wide automated test enforces
  log minimisation.
- **Retention is limited and enforced by scheduled jobs:** transcripts are
  removed from evaluation records after 90 days; evaluation records are
  deleted after 730 days; recordings follow the school's existing 30/90/365
  day setting; student and account deletion cascades to all AI artifacts.
- **Development and support:** production personal information is never
  provided to AI development or productivity tools. Test and regression
  content is synthetic and marked as such.

## 5. Human oversight and contestability

- Every AI evaluation is presented to the teacher with the disclaimer:
  *"AI-generated assessment — may be inaccurate. Listen to the recording
  and use your professional judgement before acting."*
- The source recording remains available to the teacher alongside the AI
  output for its retention period, so the evidence can always be checked.
- Uncertain, empty, off-topic, coached or adversarial input produces
  explicit review flags rather than results.
- Teachers can disregard any output; nothing in the product acts
  automatically on an evaluation.
- Parents and schools can question or complain about AI processing via the
  school or support@lumi-reading.com; complaints touching AI are handled
  under the existing privacy-complaint process and logged for the §13
  review.

## 6. Consent and transparency

- The AI feature applies only after: the school has enabled it, the updated
  collection notice is in force (with a stated effective date), and the
  child's family has **opted in** via the in-app consent step. Declining or
  ignoring consent leaves the ordinary service fully intact.
- Consent is revocable; withdrawal stops new AI processing.
- Lumi's privacy policy and school-facing documentation disclose the use of
  AI, the providers, processing location, retention periods and choices.

## 7. Third parties and models

- AI processing runs on Google Cloud services (Speech-to-Text; Gemini on
  Vertex AI) under the same Google Cloud terms that govern Lumi's hosting;
  no student data is disclosed to any additional company for AI purposes.
- The applicable foundation-model and data-governance terms are captured,
  dated, into Lumi's vendor-evidence records, and the vendor register lists
  every AI data flow.
- Only models on a code-reviewed allowlist, with recorded Australian
  regional serving evidence, can be invoked; configuration pointing at any
  other model fails closed.

## 8. Release gates for AI features

An AI feature (or a material change to one) ships only when all of the
following hold:

1. Privacy impact assessment section approved by the policy owner and
   Australian privacy counsel; collection notice in force.
2. Consent model implemented and verified fail-closed.
3. Adversarial regression suite passes 10/10 against the production prompt;
   representative-content accuracy review passed by a teacher blind review.
4. Kill switch (platform and per-school, fail-closed) verified.
5. Residency and data-governance evidence current for the pinned model.
6. Relevant school-sector requirements screened (state DoE / ST4S status).

## 9. Testing and monitoring

- **Before any prompt, rubric or model change ships:** the adversarial
  prompt-regression suite (injection, coaching, off-topic, gibberish,
  self-grading, personal-information cases) must pass 10/10; changes are
  permitted at school-term boundaries only and bump recorded versions.
- **In operation:** safety-filter block rates, deferral/failure classes,
  and token-usage drift are metered and reviewed; rising anomaly rates
  trigger the §10 process. Every evaluation stamps model, prompt and rubric
  versions so results remain auditable and trends segment correctly.
- **Model lifecycle:** at every term boundary the pinned model's
  deprecation status and its successor's Australian-region status are
  checked; migrating with less than six weeks of model runway is treated as
  an incident.

## 10. AI incident management

AI incidents include: harmful, biased or fabricated output reaching a
teacher; a prompt-injection success; output shown to an unintended
audience; processing of a non-consented or pre-notice recording; processing
outside Australia; a provider terms change permitting training on customer
data; or any bright-line breach (§3).

Response: (1) stop processing — platform kill switch or per-school disable,
both instant and requiring no deploy; (2) assess scope and affected
schools/families using job/evaluation audit records; (3) notify affected
schools honestly and promptly, and treat any personal-information exposure
under the existing Data Breach Response Plan (see
`docs/privacy/DATA_BREACH_RESPONSE_AND_TABLETOP.md`); (4) record the
incident, root cause and remediation; (5) re-run the §9 gates before
re-enabling. Incidents and near-misses feed the §13 review and, where
relevant, new adversarial regression cases.

## 11. Roles and responsibility

Lumi is a small company; roles are held as follows and revisited at each
review:

| Role | Holder | Responsibility |
|---|---|---|
| Accountable owner (AI) | Nicholas Plevritis, Director | This policy; release-gate sign-off; incident command |
| Privacy Officer | Nicholas Plevritis, Director | Privacy assessments, notices, consent model, complaints |
| Technical steward | Director (with engaged contractors/tooling as needed) | Enforced controls (§3–§4), testing (§9), monitoring |
| Backup/authority | Kylie Plevritis | Authorised to act for Lumi if the Director is unavailable (mirrors the incident-response arrangement) |

External Australian privacy counsel is engaged for the release gates in §8.

## 12. New AI features and internal AI use

- Any proposed AI feature starts with a written assessment against §2–§3
  and a PIA update **before development**, and follows every §8 gate before
  release. Adding, removing or materially changing AI functionality is
  declared to ST4S (it is a reassessment trigger).
- AI-assisted development tools may be used on Lumi's code and
  documentation, never on production personal information (§4).

## 13. Review

This policy is reviewed at least every 12 months, and immediately upon: an
AI incident; a new or materially changed AI feature; a provider or model
change; a change in the consent model, retention periods or hosting; new or
revised sector requirements (ST4S/RAI framework releases, state DoE policy
changes, registration of the OAIC Children's Online Privacy Code); or
counsel's advice. Each review is recorded in §14.

## 14. Adoption and review record

| Date | Version | Action | By |
|---|---|---|---|
| 20 July 2026 | 0.1 | Initial draft prepared for the director's review | Drafting session (B-track) |
| — | 1.0 | Formal adoption | Pending — Nicholas Plevritis |
