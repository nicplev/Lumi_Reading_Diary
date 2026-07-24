# ST4S Readiness Prep — Lumi (incl. the AI comprehension-evaluation feature)

> **Working document — Nic's action plan for entering the ST4S process.**
> Researched 2026-07-20 from the official ST4S Supplier Guide 2025.1
> (16 Dec 2025, 120 pp), the RAI Supplier Guide v1.4 (9 Oct 2025), the badge
> program guidelines (Mar 2025) and the st4s.edu.au site. Decision to begin:
> Nic, 20 July 2026.

## 1. What ST4S is and what passing unlocks

**Safer Technologies 4 Schools (ST4S)** is the national security/privacy
assessment for school edtech, run by Education Services Australia on behalf
of every state/territory education department, the Catholic and independent
sectors, and NZ. Passing puts Lumi's report in the national **ST4S
Catalogue** (visible to school/department decision-makers in every
jurisdiction), earns the **ST4S badge** ("assessed by ST4S", plus a specific
"AI assessed by ST4S" wording), replaces most per-state security
questionnaires, and is the eligibility ticket for the follow-on
**Responsible AI (RAI) evaluation**. Victoria makes it effectively
mandatory: government schools must check the Arc catalogue and **cannot use
products rated non-compliant, non-participating or high risk**.

**Cost: free.** No application fee for the Readiness Check, the full
assessment, or (as far as published) the badge. Lumi bears only its own
preparation/remediation costs.

## 2. The pipeline and timeline

1. **Readiness Check** — free web self-assessment, do anytime, results
   private, repeatable: <https://assessment.st4s.edu.au/s3/ST4S-Readiness-Check-v2023-1-V1>
   (linked from st4s.edu.au/readiness-check). ~85 core questions + ~31 AI
   questions when AI features are declared. Note: the portal still runs the
   v2023.1 question set (the 2025.1 framework update hasn't reached it yet).
2. **Nomination** — after a "Ready" outcome you may submit for
   prioritisation; the ST4S Working Group nominates **monthly with a quota**
   (school/department demand helps; un-nominated submissions roll over).
   Wait can be "days, weeks or months".
3. **Full assessment** — online questionnaire + evidence uploads; allow
   **at least 3 months**; clarification rounds with a ~3-month remediation
   window; outcome for a service like Lumi: Low / Medium / High risk or
   Non-compliant ("Medium" is the most common pass, usually because of
   parental-consent requirements). Miss any **"#" pass/fail control** ⇒
   Non-compliant.
4. **Valid 2 years**, then reassessment — triggered EARLY by hosting
   changes, new data types, or **"adding or removing features/functionality
   related to artificial intelligence."**

**Sequencing implication for Lumi:** declare the AI comprehension feature in
the initial assessment (the AI module is mandatory whenever a service has AI
features, and it's assessed even if dark/dev-gated at submission time).
Assessing without it and shipping it later forces an early reassessment;
declaring it up front also unlocks the "AI assessed by ST4S" badge wording.

**Expected tier: Tier 1** — the fullest question set (~52 mandatory-minimum
core controls + 31 mandatory AI-module controls). Tier 1 functionality
explicitly includes "video or student diary or communication tools (parent,
teacher, child)" and "audio capture" — Lumi is both.

## 3. ⚠️ The one issue to resolve BEFORE submitting anything

ST4S maintains an **Excluded/High-Risk list**, and three entries sit close
to the AI comprehension feature:

1. AI services "designed to process personal information" — "information
   must be **de-identified before being exposed to an AI model**";
2. biometric/attribute processing, including "determining or predicting…
   **student disability, learning difficulties**";
3. voice processing — **but** with an explicit exemption path: services
   using voice "solely for… accessibility (e.g. AI enhanced voice
   recognition, **live transcription of voice to text**…) **may have an
   exemption subject to review**", with safeguards (transparent privacy
   policy, user deletion controls).

Lumi's counters are real but must be argued, not assumed: name redaction +
"no student identifiers attached" before the model; STT is transcription
(no voice-prints, no biometric templates, nothing retained by the model);
the rubric evaluates **comprehension of a specific text**, not diagnosis of
the child (no disability/learning-difficulty inference — and the eval schema
contains no such fields); teacher-only qualitative output; opt-in consent
(decided 20 July 2026); fail-closed kill switch; Australian processing.

**Action (first, before the Readiness Check submission is escalated):**
describe the feature to the ST4S Team via the contact form
(<https://st4s.edu.au/contact-us/>) and ask how the exclusion list and the
STT exemption apply. The Supplier Guide explicitly invites pre-assessment
discussion. Getting this answer early prevents building collateral for an
assessment that stalls on an exclusion ruling.

## 4. Evidence checklist — what Lumi has vs. gaps

Formal evidence items are uploaded during full assessment (EV1–EV21 core,
AI_EV1–AI_EV5 for AI). ISO27001/SOC2 are **optional accelerators, not
required**; GCP's own certifications cover the hosting-provider control
(H6). Documents must be final, authorised, in English, bearing the company
name + ABN. ST4S may verify authenticity with authors/pen-testers and may
request a demo account.

### Already in hand (map these, don't rewrite them)

| ST4S ask | Existing Lumi artifact |
|---|---|
| Privacy policy content controls (PR series) | Portal/app privacy policy (`marketing-site/src/app/legal/privacy/page.tsx`) + AI section draft pending counsel |
| Data-flow / subprocessor register (EV19, P12) | `docs/privacy/VENDOR_DATA_FLOW_REGISTER.md` — near submission-ready |
| Hosting locations incl. all environments (H1, H2) | `docs/security/AU_RESOURCE_LOCATION_AUDIT_2026-07-17.md` + vendor-evidence residency capture (2026-07-20). Must be extended to state backup/DR/test/dev locations explicitly |
| PIA | `docs/privacy/PRIVACY_IMPACT_ASSESSMENT.md` + AI section draft |
| Incident response / breach plan (EV9, T6, I1) | `docs/privacy/DATA_BREACH_RESPONSE_AND_TABLETOP.md`, dual alert inboxes verified |
| Retention & deletion (D1–D3) | Retention crons (audio 30/90/365, transcript 90d, eval 730d), deletion cascade incl. AI artifacts (#464), receipts |
| Encryption, tenant isolation, access control (S/A series) | GCP default encryption + Firestore/Storage rules with negative-test matrix; MFA support; App Check |
| Log minimisation (L series) | Source-wide log-safety regression; AU log sinks |
| AI hosting country (AI_H1) | Sydney-pinned endpoints, code-enforced; probe + residency evidence in `docs/AI_EVALUATION_GEMINI_PLAN.md` §12 / vendor-evidence |
| Prompt filtering (AI_SF6#) | Gemini default safety settings kept; blocks → teacher-review flags |
| AI logging/retention (AI_L1) | Prompts/outputs never logged; transcript/eval retention documented in runbook |
| Foundation-model terms link (AI_G5) | Vertex AI terms — pin into vendor-evidence (leg 3 capture, already planned) |

### Gaps to produce (prioritised)

1. **Responsible AI policy / AI ethics framework — AI_T1#, a pass/fail
   control.** Does not exist yet. Short document: purpose limits (decision
   support, never formal assessment), human oversight, excluded uses, review
   cadence, incident handling. Highest priority.
2. **Penetration-test report (EV10) + vulnerability assessment (EV11)** —
   no pen-test evidence exists in the repo. Commission one (redacted report
   is acceptable; ST4S may verify the tester's certification).
3. **Information Security Policy (EV6)** — formalise what's already
   practised (least-privilege IAM, keyless identities, secret hygiene).
4. **BCP (EV7) + DR plan (EV8)** — formalise (PITR, restore drill already
   done — write it down).
5. **Secure SDLC statement (EV13) + patch management (EV12)** — document the
   existing PR/review/CI/dependency practice.
6. **HR controls (HR1–3)** — background checks + security-training records;
   for a 1-person company, document the small-business arrangement (ST4S
   explicitly accepts alternative arrangements for CIO/Privacy-Officer roles
   too — currently "Privacy lead unappointed" in the PIA; name Nic to both
   roles or document the alternative).
7. **WCAG evidence (EV20)** — accessibility statement/testing notes.
8. **Consent forms/T&Cs for AI (AI evidence + RAI E9)** — the opt-in
   checkbox wording, once counsel approves it.

## 5. RAI (Responsible AI) layer — after ST4S

Status July 2026: **in pilot**, aiming for 2026 rollout. Eligibility
requires a current, successful ST4S assessment **including the AI module**.
Register interest at **assessment@st4s.edu.au**; monthly quota; ~3 months;
2-year validity. Structure: 73 control questions + 12 evidence checks across
General (8) / Human Social & Wellbeing (13) / Transparency (16) / Fairness
(11) / Accountability (25); 13 mandatory RAI controls beyond ST4S; built on
the national framework + VAISS + NIST AI RMF; expressly designed for
**Australian small-to-medium edtech vendors**. The E1–E12 evidence list
overlaps heavily with §4's gaps (risk assessment, RAI policy, test logs incl.
hallucination testing, AI incident plan, consent forms, user documentation) —
producing §4's documents with the RAI evidence names in mind does both jobs.

## 6. Conduct rules (avoid own-goals)

- Do **not** publicise being "in the ST4S process" off the back of a
  Readiness Check; badge wording is licensed and specific ("assessed by",
  never "certified/approved/endorsed by").
- The questionnaire must be completed by someone holding **written CEO/CIO
  authorisation** (Nic — write a one-line self-authorisation for the file).
- Misrepresenting readiness can discontinue an assessment with a 3-month
  re-entry ban; discontinued/non-compliant status must be disclosed to
  schools if asked.

## 7. Nic's action list (in order)

1. **Contact ST4S** via <https://st4s.edu.au/contact-us/> describing the AI
   comprehension feature; ask (a) how the AI exclusion list / STT exemption
   applies, and (b) current RAI pilot status. (Resolves the two biggest
   unknowns before any submission.)
2. **Run the Readiness Check** at the portal (free, private, repeatable) —
   declare the AI feature; expect Tier 1.
3. Meanwhile, produce the §4 gap documents, starting with the Responsible AI
   policy (pass/fail control) and booking a penetration test (longest lead
   time).
4. On a "Ready" outcome: submit for prioritisation; jurisdiction demand
   helps, so a supportive pilot school/diocese mentioning Lumi to their
   department accelerates nomination.
5. After ST4S completes: register RAI interest at assessment@st4s.edu.au.

Jurisdiction contacts (from the Supplier Guide, for later): VIC
security.assessments@education.vic.gov.au · independent sector
st4s@isa.edu.au · full list in the guide (p.18).

## 8. Open items / unverified

- RAI GA status mid-2026 (page still says pilot) — ask in step 1.
- Precise STT/voice exemption criteria — unpublished; ask in step 1.
- NSW's formal ST4S requirement for its Online Learning Tools Marketplace is
  reported in a 2024 academic source but not named in NSW policy documents —
  confirm with NSW DoE when that conversation starts.
- Badge licence terms (fee not affirmatively stated as none).
- Full-assessment question totals (~250 core + ~55 AI) are derived counts,
  not official figures.

Primary sources (all accessed 2026-07-20): ST4S Supplier Guide 2025.1
(16 Dec 2025); RAI Supplier Guide 2025.1 v1.4 (9 Oct 2025); ST4S Product
Badge Program Usage Guidelines v2 (Mar 2025); st4s.edu.au pages (readiness
check, excluded/high-risk list, catalogue, badge program, responsible-ai,
costs); VIC PAL "ICT software in schools — risk assessment" (28 Jan 2025).

---

## Annex — pre-assessment enquiry (step 1 of the action list)

**STATUS: SENT by Nic on 20 July 2026** via <https://st4s.edu.au/contact-us/>.
Awaiting the ST4S Team's reply — their answer to question 1 (excluded-list /
STT-exemption applicability) gates the rest of this plan. Text as sent below
(phone number redacted in this copy). Entity details per the ASIC
business-name registration (LUMI READING, registered 15 July 2026, holder
Lumi Education Pty Ltd).

> **Subject: Pre-assessment guidance request — AI feature in a K-6
> reading-diary app (Lumi)**
>
> Dear ST4S Team,
>
> I hope you're well. My name is Nicholas Plevritis and I'm the director of
> **Lumi Education Pty Ltd** (trading as Lumi Reading), a small Australian
> edtech company. Lumi is a reading-diary app
> for primary schools: parents and carers log their child's home reading,
> teachers see class reading progress, and the two can message about a
> child's reading. All student data is hosted on Google Cloud/Firebase in
> the Sydney (`australia-southeast1`) region.
>
> We're preparing to complete the ST4S Readiness Check and would very much
> appreciate your guidance on one point beforehand, as the Supplier Guide
> kindly invites pre-assessment discussion.
>
> **The feature in question.** Lumi has an optional, off-by-default
> comprehension feature (enabled per school, with recorded school
> authority): a child records a short spoken answer to a teacher-set
> question about their book, and the teacher can listen to it. We have
> built — but not enabled anywhere — an AI extension of this feature:
>
> 1. the recording is transcribed by Google Cloud Speech-to-Text at the
>    Sydney regional endpoint;
> 2. the transcript and the teacher's question are evaluated by Gemini on
>    Vertex AI, also at the Sydney regional endpoint, against a simple
>    comprehension rubric; and
> 3. the output is a short, qualitative, **teacher-only** summary (evidence
>    quotes from the transcript, a level such as "developing", and review
>    flags). There are no marks or scores, students and parents never see
>    AI output, and the summary is decision support only — teachers are
>    explicitly directed to listen to the recording and use their
>    professional judgement.
>
> Key safeguards: explicit per-family **opt-in** consent (no consent = no
> AI processing ever, while ordinary teacher listening continues); the
> student's registered name is redacted before the model and no student
> identifiers are attached to requests, though spoken content may
> incidentally contain personal information; no voice-prints or biometric
> templates are created — the speech stage is transcription only; the model
> does not train on the content; the rubric assesses comprehension of the
> specific text, never ability, disability or learning difficulties (the
> output schema contains no such fields); retention is limited (transcript
> 90 days, evaluation 730 days); and the feature sits behind a fail-closed
> kill switch.
>
> **Our questions:**
>
> 1. Given the Excluded and High-Risk list — in particular the
>    de-identification expectation for AI inputs, and the voice/biometrics
>    entry with its exemption for speech-to-text transcription "subject to
>    review" — is a feature of this design assessable under ST4S, and how
>    would the exemption review apply to it?
> 2. If that determination is case-by-case, what information or
>    documentation would you need from us to make it?
> 3. We intend to declare this AI feature in our initial Readiness Check
>    and any subsequent full assessment, even though it is not yet enabled
>    for any school — is that the correct approach?
> 4. Separately, could you let us know the current status of the
>    Responsible AI evaluation pilot and whether registrations of interest
>    are open?
>
> We'd be very happy to provide architecture documentation, our privacy
> impact assessment, data-flow register, or a demonstration account if
> helpful. Thank you very much for your time and for the work behind ST4S —
> the published guides have been genuinely helpful to us as a small vendor.
>
> Kind regards,
> Nicholas Plevritis
> Director, Lumi Education Pty Ltd (trading as Lumi Reading)
> ABN 45 700 349 015
> support@lumi-reading.com
> [PHONE NUMBER]
