# Lumi AI comprehension evaluation — Phase 0 evidence and go/no-go

**Status:** Conditional GO for the Australian Google Speech-to-Text technical path; **NO-GO for school or production AI processing**

> **Provider revision 2026-07-19:** the proposed Anthropic (Claude Haiku) evaluation stage has been replaced by **Gemini Flash-Lite on Vertex AI at `australia-southeast1`** so the entire pipeline is processed inside Australia — see `docs/AI_EVALUATION_GEMINI_PLAN.md`. Anthropic-specific gates and data-flow lines below are retained as the historical Phase 0 record and are no longer applicable; the STT evidence in this document remains current and banked.

**Evidence date:** 2026-07-15

**Project / region:** `lumi-ninc-au` / `australia-southeast1`

**Production gate:** `platformConfig/aiEvaluation.enabled=false`

This is the working Phase 0 technical record and lightweight privacy impact assessment (PIA) draft for Lumi's proposed comprehension-evaluation pipeline. It is not legal advice. It must be reviewed with Australian privacy counsel and pilot schools before any entitlement is enabled.

## TL;DR

- The Australian regional Speech-to-Text V2 endpoint works with Lumi-style AAC/M4A audio and `en-AU`.
- Use the `long` model as the current candidate. It transcribed the full six-second synthetic sample directly from M4A; no transcode was needed. `latest_short` worked for a very short sample but returned no transcript for the six-second sample. Chirp 2 is unavailable in `australia-southeast1`.
- Successful requests are billed in one-second increments. The observed 1.35-second and 6.23-second clips were billed as 2 and 7 seconds respectively.
- The regional synchronous-recognition quota is currently 211 requests/minute. That comfortably covers the planned worker ceiling of five concurrent instances for the spike, but must be load-tested and revisited before scaling.
- This is not approval to process children. The test audio was synthetic computer speech. A representative child-style M4A, teacher accuracy review, collection notice, opt-out design, PIA approval and provider-contract checks are still required.
- Anthropic remains blocked: no API secret is configured, the DPA/APP 8 position is unresolved, retention/ZDR is not pinned and spend controls are not set.
- No recording created before the approved notice's effective time may ever enter the AI pipeline. There will be no backfill.

## Decision table

| Gate | Result | Evidence / condition |
|---|---|---|
| Speech API enabled | PASS | `speech.googleapis.com` is enabled in `lumi-ninc-au`. |
| Least-privilege Speech role | PASS | Runtime service account has `roles/speech.client`. This role does not authorise an LLM provider. |
| Australian regional endpoint | PASS for technical spike | Direct V2 requests to `australia-southeast1-speech.googleapis.com` returned HTTP 200. Google's Locations API reports `en-AU` `long`, `short` and `telephony` model features in that region. |
| Lumi M4A compatibility | PASS for synthetic AAC | `long` transcribed AAC/M4A through automatic decoding without conversion. Physical iOS/Android recordings still require testing. |
| Model selection | CONDITIONAL GO: `long` | Best result in this small synthetic test. Do not treat one sample as an accuracy benchmark. |
| Child-speech accuracy | OPEN / release blocker | No child audio was used. Obtain an approved representative development set only after notice/authority is documented, then have a teacher review transcripts. |
| Billing granularity | PASS | Official pricing says successful audio is rounded to one-second increments; observations matched. Empty successful responses are still billable. |
| Spike quota | PASS | Live project quota: 211 synchronous requests/minute/region; planned worker limit: 5. Reassess against measured job duration and evening peak before rollout. |
| Anthropic contract and controls | FAIL / blocked | No secret, DPA, APP 8 decision, pinned retention/ZDR, tier check or spend cap. |
| Privacy and school approval | FAIL / blocked | Working PIA below is not approved; notice, authority/consent or other lawful basis, opt-out and state/school policy checks remain. |
| Production enablement | OFF | Kill switch remains false and no AI worker/provider integration is deployed. |

## Australian Speech-to-Text spike

All content below was generated with macOS synthetic speech. It contains no real student voice or school record.

| Input | V2 model | Result | Billed duration |
|---|---|---|---:|
| 6.23 s AAC/M4A, `en-AU` | `latest_short` | HTTP 200, no transcript | 0 s reported in response metadata |
| 6.23 s PCM/WAV, `en-AU` | `latest_short` | HTTP 200, no transcript | 0 s reported in response metadata |
| 6.23 s PCM/WAV, explicit decode | `long` | Correct full sentence | 7 s |
| 6.23 s PCM/WAV, explicit decode | `chirp_2` | HTTP 400; model unavailable in region | not processed |
| 6.23 s AAC/M4A, automatic decode | `long` | Correct full sentence; confidence 0.9675 | 7 s |
| 1.35 s AAC/M4A, automatic decode | `latest_short` | Partial short phrase; confidence 0.9506 | 2 s |

The six-second `latest_short` empty response is a warning, not proof that the model is generally defective. Google describes short models as suited to short, single-shot utterances, and model availability can change. The pipeline should start with `long`, preserve a provider/model version in evaluation provenance, and make any later model change an evaluated release.

Official references:

- [Speech-to-Text V2 regional availability](https://cloud.google.com/speech-to-text/v2/docs/locations)
- [Speech-to-Text transcription models](https://cloud.google.com/speech-to-text/docs/transcription-model)
- [Speech-to-Text pricing and one-second rounding](https://cloud.google.com/speech-to-text/pricing)
- [Speech-to-Text quotas and limits](https://cloud.google.com/speech-to-text/docs/quotas)

### Proposed Speech request boundary

- Endpoint: `australia-southeast1-speech.googleapis.com`
- API: Speech-to-Text V2 synchronous recognize for sub-minute comprehension clips
- Language: `en-AU`
- Initial model candidate: `long`
- Input: canonical AAC/M4A object only after the existing upload-confirmation checks pass
- Identity: the Australian Functions runtime service account; never a client API key
- Output: transcript plus provider/model/provenance metadata; never copy a student name, UID, school ID or class ID into provider request metadata
- Failure posture: safe to wait; no score/evaluation on empty, errored, low-quality or uncertain transcripts

## Working privacy impact assessment

### Purpose and necessity

The proposed purpose is to help an authorised teacher review a student's spoken response to a teacher-set comprehension question. It must remain decision support: the teacher can inspect, contest and override the result. It must not make high-impact or automated decisions about a child, expose numeric scores, or produce parent-facing evaluations without teacher review.

Necessary inputs are limited to:

- the audio response;
- the captured comprehension question;
- the minimum rubric needed to interpret that answer; and
- provider/model/version identifiers needed to audit the result.

Student name, UID, email, school name, class name, parent details, reading history, disability/health information and unrelated profile fields are not necessary provider inputs. Approved wording is: **“no student identifiers attached; content may incidentally contain personal information.”** Do not describe voice or transcript content as anonymised.

### Proposed data flow and locations

```text
Australian Firebase Storage
  -> Australian Cloud Function
  -> Google Speech-to-Text V2 Australian regional endpoint
  -> transcript in server-only job state
  -> Anthropic evaluation (BLOCKED: overseas/provider terms unresolved)
  -> separate teacher-only comprehension evaluation
```

The Australian Speech region reduces the STT processing-location risk, but it does not by itself prove every support, telemetry, resilience or subcontractor access path stays in Australia. The Google terms/DPA and school contract must be checked. The proposed Anthropic step is a cross-border disclosure risk until its processing locations, DPA, subprocessors, retention and ZDR eligibility are accepted.

### Privacy-law and school-policy gates

- **APP 6 / new purpose:** document whether AI analysis is a secondary use, the lawful basis relied upon, what families reasonably expect, and whether consent/opt-out is required. Update the collection notice before collecting recordings for this purpose.
- **APP 8 / overseas handling:** complete the Anthropic DPA and accountability assessment before any transcript is sent outside Australia. Record subprocessors and accessible countries.
- **APP 11:** protect audio/transcripts and destroy or de-identify them when no longer needed. Verify deletion at providers as well as in Lumi.
- **Children's best interests:** complete and approve the full PIA before enabling a school. Default the feature off and collect only what is strictly necessary.
- **School AI policy:** screen each pilot against its state/sector and school policy. The Australian Framework expects privacy disclosure, limited collection/retention, testing, monitoring and contestability.

Official references:

- [OAIC Australian Privacy Principles](https://www.oaic.gov.au/privacy/australian-privacy-principles/read-the-australian-privacy-principles)
- [OAIC APP 11 guidance](https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-11-app-11-security-of-personal-information)
- [OAIC guide to privacy impact assessments](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/privacy-impact-assessments/guide-to-undertaking-privacy-impact-assessments)
- [OAIC draft Children's Online Privacy Code announcement](https://www.oaic.gov.au/news/media-centre/oaic-releases-exposure-draft-of-the-childrens-online-privacy-code)
- [Australian Framework for Generative AI in Schools](https://www.education.gov.au/schooling/resources/australian-framework-generative-artificial-intelligence-ai-schools)

### Required safeguards

- AI remains off globally and per school by default; missing or unreadable configuration means off.
- Only recordings created at or after the approved notice-effective timestamp are eligible. **No backfill, including administrator-triggered backfill.**
- Parents must have a practical opt-out route without loss of Lumi's core reading-diary service. The precise authority model must be signed off for each school context.
- Audio, transcript, prompt and output never enter Analytics, Crashlytics, logs, error messages or support tools.
- Server derives Storage and Firestore paths. Clients cannot choose provider metadata or privileged fields.
- Teacher reads stay class-scoped; parents cannot read AI evaluations; all AI documents remain server-written.
- Store qualitative levels and confidence only. No user-visible numeric score.
- Low confidence, empty speech, adult prompting, injection, off-topic and unintelligible input produce review/no-result states, not invented evidence.
- Provider inputs and outputs are excluded from training wherever contract/settings allow; retention/ZDR settings and evidence must be pinned in the runbook.
- Existing account/student deletion must be extended and tested against every AI job, transcript, evaluation and provider-side retained copy before launch.
- Default evaluation retention proposal is 730 days, subject to necessity/legal/school review. Raw audio and transient transcript/job data should have materially shorter documented periods.
- Audit access and processing without storing raw child content in audit logs.

### Risk register

| Risk | Current control | Required before enablement |
|---|---|---|
| Child content sent without adequate notice/authority | Feature globally off; no worker | Approved notice and authority/opt-out decision; effective timestamp enforced server-side |
| Cross-border transcript disclosure | No Anthropic key or calls | Executed DPA, APP 8 assessment, subprocessors/locations, retention/ZDR evidence |
| Prompt injection in spoken response | Synthetic regression fixture created | Schema-bounded evaluator tests must prove transcript instructions cannot alter policy/rubric |
| Incorrect transcript/evaluation | Teacher-only surface planned | Representative accuracy study, teacher review, confidence/no-result thresholds, contest/override flow |
| Identifier leakage | Separate server-only job/eval model | Request-construction tests proving identifiers and unrelated context are absent |
| Excess retention | No AI data currently produced | Approved retention schedule plus automated deletion and provider deletion verification |
| Cost/quota abuse | Global switch off; regional quota known | App Check, caps, idempotent jobs, rate limits, retry ceiling, budget alert and provider spend cap |
| Provider outage | No dependency in product yet | Safe-to-wait queue, no fallback to an unapproved region/provider, documented kill switch |

## Synthetic adversarial regression set

The permanent Phase 0 seed set is at `functions/test/fixtures/ai_evaluation_adversarial_transcripts.json`. It covers direct and mixed prompt injection, prompt exfiltration, off-topic content, adult coaching/substitution, gibberish, empty speech, unsupported self-assessment and incidental personal information. `functions/test/ai_evaluation_fixtures.test.js` validates that the fixture stays synthetic, schema-complete and covers the minimum threat categories.

The fixture is not yet a test of a real evaluator because no LLM prompt/provider code exists. Phase 3 must run every case against the schema-bounded evaluator and assert the `mustNot` outcomes.

## Remaining go/no-go actions

1. Approve the full PIA, collection notice, authority/opt-out model, no-backfill rule and retention schedule with privacy counsel and pilot schools.
2. Record 5–10 properly authorised representative development clips, including child-style AAC/M4A from physical iOS and Android devices. Do not use historical recordings.
3. Have a teacher compare STT transcripts to the audio and record word-error/meaning-impact findings. Reconsider the model only from this evidence.
4. Freeze the v1 rubric and evaluation JSON schema, including explicit no-result/review states.
5. Complete Anthropic DPA/APP 8, processing location, subprocessors, retention/ZDR, tier and spend-cap checks. Only then create a workspace-scoped secret.
6. Extend the adversarial fixture into a live prompt regression suite without including real child content.
7. Update the deletion/retention test matrix for AI jobs, transcripts, evaluations and provider-side deletion.
8. Keep `platformConfig/aiEvaluation.enabled=false` until every release-blocking item above has evidence and the production rollback/runbook is approved.

## Final Phase 0 verdict

**Technical STT path: conditional GO. Product/provider launch: NO-GO.** The Australian regional endpoint and direct AAC/M4A transcription are viable enough to continue controlled development. That does not authorise processing real children or deploying the provider-connected pipeline. Privacy, representative accuracy, provider contract and operational controls remain hard gates.
