# State DoE Screening Memo — AI Comprehension Evaluation Pilot

> **DRAFT — pending counsel + Nic approval; not in force.**
> Research memo for pilot-school screening. Policy positions below were
> researched on 20 July 2026; several were verifiable only via search-index
> snapshots of official pages (marked). Re-verify the flagged items with the
> department/sector body before relying on them for a specific school.

**Prepared:** 20 July 2026
**Scope:** NSW and VIC department positions on generative-AI tools in schools,
the national framework, cross-sector assessment schemes, and a per-school
screening checklist for the AI comprehension-evaluation pilot.
**The feature being screened:** student voice recording → Google STT (Sydney)
→ Gemini on Vertex AI (`australia-southeast1`) → teacher-only qualitative
summary. Teacher-in-the-loop decision support; never formal assessment; no
numeric scores; fail-closed kill switch; no pre-notice recordings processed.

---

## 1. Headline findings (what changes the plan)

1. **A Victorian government-school pilot is effectively gated on departmental
   engagement, not just school consent.** Victoria's GenAI policy directs
   staff and students not to upload **audio** of students into generative-AI
   tools, and its privacy policy warns that GenAI deriving biometric
   information from audio "should be avoided" and puts **audio collection
   through a 4-step central approval process** (department Privacy team,
   software catalogue check, contract review, community consultation). Lumi's
   core AI flow is a child's voice into a GenAI pipeline — squarely inside
   this restricted zone. **Do not pilot in a VIC government school without
   explicit departmental clearance.** (§4)
2. **NSW government schools need departmental approval for the AI feature.**
   NSW assesses GenAI tools centrally (Safe AI Ethics Assessment + security +
   pedagogy), has **blocked new GenAI commercial arrangements pending
   review** (page modified 13 Apr 2026), and requires departmental approval
   before students may access a GenAI tool. Lumi's AI feature is not
   student-facing GenAI (students never see AI output), but a GenAI service
   processing student voice will attract the same machinery. Engagement with
   the department (marketplace listing + Chief AI Office pathway) must start
   **before** any NSW government pilot. (§3)
3. **ST4S is the cross-sector key.** Victoria treats a vendor that has not
   engaged with Safer Technologies 4 Schools as effectively prohibited
   ("non-participating" rating must not be used), and the new **Responsible
   AI (RAI) Standard** (ESA; 73 controls; rolling out for 2026) is the
   AI-specific layer on top. An ST4S assessment (then RAI evaluation) is the
   single highest-leverage vendor action and is valued by all sectors. Start
   the ST4S Readiness Check regardless of which schools pilot first. (§5)
4. **The lowest-friction pilot cohort is independent and Catholic schools**,
   which set their own AI/app policies (under the Privacy Act/APPs) rather
   than state DoE schemes — though diocesan systems (e.g. MACS) also run
   approved-platform regimes. Lumi's existing APP-grounded privacy corpus is
   the right artefact set for them. (§6)
5. **Victoria mandates opt-in parental consent** for any GenAI tool needing
   personal information beyond a school email + password — relevant input to
   the opt-out decision memo: for VIC government schools, per-family
   **opt-in** is not optional. (§4)
6. **Timing horizon:** the OAIC Children's Online Privacy Code (exposure
   draft 31 Mar 2026; consultation closed 5 Jun 2026) is targeted for
   registration by **10 Dec 2026** and will likely cover educational services
   accessed by children — it lands inside any pilot-to-production window.

## 2. National framework (all sectors)

The **Australian Framework for Generative AI in Schools** (approved by
Education Ministers 5 Oct 2023; non-binding; all jurisdictions and sectors)
sets 6 principles / 25 guiding statements. The 2024 review (endorsed by
ministers June 2025) kept it unchanged, added deepfakes as an emerging risk,
and moved it to annual review. Principles most relevant here, and Lumi's
mapping:

| Framework principle | Lumi design answer |
|---|---|
| Accountability / human oversight — teachers remain responsible for decisions supported by AI | Teacher-in-the-loop only; qualitative summaries; mandatory "use your professional judgement" disclaimer; no formal assessment; teacher can contest/ignore every result |
| Transparency — school communities know how and when AI is used | Collection-notice update (B1 draft) delivered before enablement; effective-date floor; portal/legal-page update |
| Privacy, security and safety | All-AU processing (tier-2 claim pending evidence); no identifiers in provider requests; name redaction; fail-closed kill switch + per-school entitlement; 90d/730d retention; no model training on content |
| Fairness | No numeric scores; unassessable input → review flags, never invented results; accuracy gate with teacher blind-review before enablement |

Sources: OECD.AI policy record (updated 25 Dec 2025) and AITSL resource page,
accessed 2026-07-20. **Caveat:** education.gov.au itself was unreachable
during research; framework content was cross-verified from those official
mirrors and search-index snapshots of the education.gov.au pages.

## 3. NSW Department of Education (government schools)

**Posture.** A dedicated Chief AI Office runs three pillars (GenAI Safety /
Capability / Enablement). GenAI tools get a **Safe AI Ethics Assessment**
plus cybersecurity and pedagogical review before executive approval. The
department has restricted free tools failing safety standards, **blocked new
GenAI commercial arrangements pending review**, and disabled vendor GenAI
add-ins during evaluation. Student access to a GenAI tool requires
departmental approval following assessment. ("Artificial intelligence in
education", education.nsw.gov.au, page modified 13 Apr 2026; accessed
2026-07-20.)

**Staff guidance.** Staff must not put student work or personal/sensitive
information into unapproved AI tools; NSWEduChat is the department-built
option ("all data in NSWEduChat stays in Australia"); other tools require
departmental assessment. ("Guidelines regarding the use of generative AI",
updated 1 Apr 2026; "NSWEduChat" page; accessed 2026-07-20.)

**Third-party app regime.** Under the *Technology in schools procedures*
(PD-2024-0481-01, V01.2.0, last updated 18 Jun 2026): core apps need no
parental consent; **every other online application requires explicit
parental consent per app**; schools must not deploy software that failed a
security assessment; principals consult Digital Field Services before
purchase. Schools discover pre-assessed apps via the staff-only **Online
Learning Tools Marketplace** and **AssessedIT** (self-service catalogue of
pre-assessed apps that also generates parent consent letters — verified via
official T4L newsletter snapshot, 2024). Vendor entry points (from
search-index snapshots of the official supplier page, which currently 404s —
**reconfirm before use**): `marketplace@det.nsw.edu.au` (catalogue listing)
and `ThirdPartyIntegration@det.nsw.edu.au` (SIF-based data integration).

**Privacy.** The legal-issues bulletin on third-party web/cloud services
requires due-diligence (vendor checklist), and compliance with the PPIP Act
1998 (NSW), HRIP Act 2002 (NSW) and Privacy Act 1988 (Cth). No black-letter
"data must stay onshore" rule was found for third-party apps, but the
department's own posture (NSWEduChat's Australia-only stance; security
assessment regime) signals a strong onshore expectation — Lumi's Sydney-only
architecture is the right answer, claimed at tier-2 wording until evidence
lands. (Bulletin content Feb 2023, page metadata 5 Mar 2026; student
device/online-services procedures V03.2.0 updated 29 Apr 2026 — students must
not use AI tools to create/post images/content of students, staff or
families; accessed 2026-07-20.)

**What NSW means for the pilot.**
- Ordinary Lumi (reading diary, no AI) in a NSW government school already
  requires the app to be assessed/consented per the procedures.
- The AI evaluation feature adds the GenAI machinery: departmental
  assessment/approval, against a background where new GenAI commercial
  arrangements are paused. Expect lead time; start with the marketplace/
  AssessedIT listing conversation and ask how the Safe AI Ethics Assessment
  applies to a teacher-facing evaluation feature processing student voice.
- Design points to lead with: teacher-only output, no student-facing GenAI,
  all-AU processing, no training on student content, fail-closed controls,
  no numeric scores, per-app parental consent flow already supported by the
  notice + opt-out/consent model.

## 4. Victorian Department of Education (government schools)

**GenAI policy** (PAL "Generative Artificial Intelligence", last updated
18 Jun 2024; guidance tab reviewed 25 Nov 2025; accessed 2026-07-20):
- **Opt-in parental consent is mandatory** before using any GenAI tool that
  requires personal information beyond a student's school email + password.
- Staff and students must **not upload media depictions of students — photos,
  audio, video — into GenAI tools**.
- AI must not make judgements about student learning achievement, write
  student reports, or replace teacher judgement in communication.
- Schools must risk-assess before implementation and prefer tools that do not
  share data with third parties, do not train on user data, and do not retain
  data. Some AI tools are blocked on the department network (no public list).

**Software regime** (PAL "Software and Administration Systems", updated
28 Jan 2025): schools must check the **Arc Software Catalogue** for an
**ST4S** risk assessment; products rated non-compliant, high-risk or
**non-participating (vendor never engaged with ST4S) must not be used**; if
no report exists the school must run a PIA and ask the department's IT
Security Team to request an assessment.

**Privacy regime** (PAL "Privacy and Information Sharing", updated
11 Jul 2025): PIA before software storing personal/sensitive information;
opt-in consent for higher-risk collection; **audio recordings and biometric
information trigger a 4-step approval**: (1) contact the department Privacy
team, (2) check Arc/ST4S, (3) contract compliance review, (4) comprehensive
school-community consultation. The policy explicitly warns that generative
AI can derive biometric information from audio and that this "should be
avoided". Governing statute: Privacy and Data Protection Act 2014 (Vic).

**What VIC means for the pilot.**
- The combination of "no student audio into GenAI tools" + the audio/
  biometric 4-step + mandatory opt-in consent means a VIC government pilot
  **cannot proceed on school-level consent alone**. It requires the central
  Privacy team's engagement and, realistically, an ST4S report first.
- Lumi's counters when that conversation happens: the pipeline does not
  build voice-prints or biometric templates (STT transcription only, then
  text evaluation); nothing is retained by the model or used for training;
  processing is Australia-regional; output is teacher-only decision support,
  which aligns with the policy's "teacher judgement remains central" line.
  But the policy text as written still catches the flow — treat VIC
  government schools as **out of scope for the first pilot cohort** unless
  Nic specifically wants to run the departmental process.

## 5. Cross-sector assessment machinery (ST4S + RAI)

- **ST4S (Safer Technologies 4 Schools)** — ESA-run, developed with all eight
  jurisdictions plus the Catholic and independent sectors (and NZ). Product
  assessments/badges are consumed by schools across sectors; Victoria makes
  non-participation effectively prohibitive, and other jurisdictions use the
  same catalogue. Action: run the ST4S Readiness Check and start an
  assessment for Lumi (with the AI feature declared). (st4s.edu.au, accessed
  2026-07-20.)
- **RAI Standard (Responsible AI)** — commissioned by Education Ministers
  (2024), built by ESA on top of ST4S: 73 control questions + 12 evidence
  checks across General (8), Human Social & Wellbeing (13), Transparency
  (16), Fairness (11), Accountability (25); 13 mandatory RAI controls beyond
  ST4S plus use-case-specific controls; based on VAISS and NIST AI RMF.
  Suppliers completing ST4S can be invited into the RAI evaluation pilot;
  rollout aimed at 2026. Lumi's design maps well (teacher-in-the-loop
  accountability, transparency notice, no high-stakes automation), and an
  RAI report would neutralise most per-state friction. (st4s.edu.au RAI
  pages, accessed 2026-07-20; precise July-2026 operational status
  unconfirmed — check when engaging.)

## 6. Government vs independent/Catholic sectors

| Sector | What binds them | Practical gate for the pilot |
|---|---|---|
| NSW government | NSW DoE procedures, AssessedIT/marketplace, GenAI approvals, PPIP/HRIP Acts | Departmental assessment + listing + per-app parental consent (§3) |
| VIC government | PAL policies (GenAI, Software, Privacy), Arc/ST4S, PDP Act 2014 (Vic) | Central Privacy-team 4-step + ST4S + opt-in consent; currently effectively restricted for student-audio GenAI (§4) |
| Catholic systemic (e.g. MACS, BCE, CSNSW dioceses) | Diocesan policies + Privacy Act/APPs | Diocese-level approved-platform decision (MACS: students may only use approved platforms/AI programs; open chatbots blocked — 2023 release. BCE launched its own student GenAI tool May 2026, showing diocesan autonomy). Engage the diocese, not just the principal |
| Independent | School's own policy + Privacy Act/APPs; AISNSW/ISV guidance (member-only frameworks) | Principal/board decision; Lumi's APP corpus (PIA, notice, APP 8 brief) is the artefact set they'll ask for |

The national framework applies to all sectors (non-binding); ST4S badges are
recognised across sectors; the Privacy Act/Children's Online Privacy Code
applies to Lumi directly as vendor regardless of sector.

## 7. Per-pilot-school screening checklist (walk through with each principal)

Record answers per school; file with the pilot evidence.

**A. Classification**
- [ ] State/territory and sector (government / Catholic systemic / independent)?
- [ ] If Catholic systemic: which diocese/system office approves platforms, and has it been engaged?
- [ ] Which privacy statute applies (APPs / PPIP NSW / PDP Vic) — recorded for counsel?

**B. Scheme gates (government schools)**
- [ ] NSW: is Lumi listed/assessed (AssessedIT / Online Learning Tools Marketplace)? Has the department's AI assessment pathway been engaged for the AI feature? Written outcome on file?
- [ ] NSW: per-app explicit parental consent process agreed with the school (AssessedIT consent letter or Lumi notice + consent record)?
- [ ] VIC: ST4S report status in Arc? Department Privacy team contacted (audio 4-step)? Written clearance for student-audio GenAI processing? **If no: do not pilot the AI feature at this school.**
- [ ] Any school/system network blocklist that would affect Lumi domains?

**C. School policy + community**
- [ ] Does the school/system have its own AI or app-approval policy, and has the principal signed off against it?
- [ ] Collection-notice update delivered to families, with effective date recorded (B1 notice; no pre-notice recording is ever processed)?
- [ ] Opt-out/consent model per the decision memo implemented for this school's context (VIC gov ⇒ opt-in mandatory)?
- [ ] School's audio-recording authority + retention setting (30/90/365d) current in the portal?

**D. Framing the school must accept (and can verify in-product)**
- [ ] Teacher-in-the-loop only; no formal assessment; no numeric scores; students/parents never see AI output.
- [ ] All-AU processing claim at the current evidence tier (tier-2 wording until the during-ML-processing capture lands).
- [ ] Kill-switch + per-school disable semantics explained (instant, no deploy).
- [ ] Retention: transcript 90d, evaluation 730d, audio per school setting.
- [ ] Escalation contact + how the school requests disablement or deletion.

## 8. Source register

Official pages fetched directly (accessed 2026-07-20 unless noted):
- NSW "Artificial intelligence in education" — modified 13 Apr 2026
- NSW "Guidelines regarding the use of generative AI" — updated 1 Apr 2026
- NSW "NSWEduChat" + rollout news (23 Sep 2025)
- NSW "Technology in schools procedures" PD-2024-0481-01 — updated 18 Jun 2026
- NSW legal-issues bulletin "Privacy and the use of third-party web and cloud-based services" — content Feb 2023 / page 5 Mar 2026
- NSW "Digital devices and online services for students procedures" PD-2020-0471-01 V03.2.0 — updated 29 Apr 2026
- VIC PAL "Generative Artificial Intelligence" — updated 18 Jun 2024 (guidance reviewed 25 Nov 2025)
- VIC PAL "Software and Administration Systems" — updated 28 Jan 2025
- VIC PAL "Privacy and Information Sharing" — updated 11 Jul 2025
- st4s.edu.au (ST4S, "The RAI Standard", "About Responsible AI")
- AITSL framework resource page; OECD.AI policy record (updated 25 Dec 2025)

Verified only via search-index snapshots of official pages (re-verify before
relying): NSW AssessedIT detail (T4L Issue 105, 2024); NSW vendor contact
emails (supplier page 404s); education.gov.au framework + 2024 Review pages
(site unreachable); RAI 2026 rollout status; OAIC Children's Code dates.
Secondary/sector sources: NCEC inquiry statement; MACS media release (2023);
BCE GenAI tool launch (May 2026); AISNSW/ISV newsroom items.

## 9. Recommended sequencing (advisory — Nic decides)

1. Start ST4S Readiness Check now (serves every sector; prerequisite-shaped
   for VIC; feeds the RAI evaluation).
2. Pilot first in independent and/or Catholic schools whose system office
   signs off — using the B1 privacy corpus + this checklist.
3. In parallel, open the NSW conversation (listing + AI assessment pathway)
   with the teacher-only/all-AU design brief; treat approval as a milestone,
   not a formality, given the current pause on new GenAI arrangements.
4. Defer VIC government schools unless Nic chooses to run the central
   Privacy-team process; revisit when the RAI program is operational.
