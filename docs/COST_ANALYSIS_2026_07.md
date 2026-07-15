# Lumi Running-Cost Analysis — per-student economics (July 2026)

**Date:** 2026-07-15 · **FX:** A$1.4404 / US$1 (ECB 2026-07-14) · All vendor prices verified against official pricing pages on 2026-07-15 (sources in appendix). **All figures ex-GST** — Google, Apple and SendGrid add 10% GST on AU-billed accounts (an input-tax-credit wash if the entity is GST-registered, but the billing budget alert fires on the GST-inclusive bill).

## TL;DR

| | 80 students | 250 | 800 | 5,000 |
|---|---|---|---|---|
| **Core cost / student / year** (Firebase + SMS + fixed share) | **A$8.94** | **A$3.02** | **A$1.10** | **A$0.37** |
| + AI comprehension, upper end (sync STT + Haiku eval) | A$14.27 | A$8.35 | A$6.43 | A$5.70 |
| + AI comprehension, batch pipeline | A$10.52 | A$4.60 | A$2.69 | A$1.96 |
| Gross margin @ retail price (A$15/13/11 by band) | 40% | 77% | 90% | 95%¹ |

¹ at wholesale ~A$7. Margins are infrastructure-only — they exclude payment-channel costs (Apple IAP 15–30% on B2C, the absorbed KAKA % on the school channel) and GST treatment.

- The **variable infrastructure cost of a fully-active student — 200 logged nights/year, every night with a 60-second comprehension recording — is ~A$0.23/year**. Over half of that is **SMS** (parent phone-auth sign-ins + teacher MFA, A$0.18); all of Firebase — every read, write, function, byte of audio — is ~A$0.06.
- **Per-student cost is dominated by platform-fixed costs** (SendGrid A$345/yr is half the fixed base) until ~500 students, and by **AI transcription** once that feature launches.
- **AI transcription dwarfs everything else per-student.** The currently-planned sync Google STT pipeline costs A$4.61/student/yr — ~20× the entire base variable cost. Batch/cheap providers run A$0.19–0.86.
- ⚠️ **The A$100/mo billing budget only survives AI launch at ≤~200 students on sync STT.** AI at sync rates adds ~A$36/mo at 80 students, ~A$111/mo at 250, ~A$355/mo at 800 — on top of a current Google bill of only ~A$16–30/mo. Raise the budget (or ship batch STT, −81%) before enabling `platformConfig/aiEvaluation` beyond a pilot school.

---

## 1. Scope and assumptions (deliberately upper-end)

Unit modelled: **one student + one linked parent** ("family unit"). Multi-child families share app-session reads, so real costs are slightly lower.

| Input | Value | Basis |
|---|---|---|
| Logged nights / year | **200** | user-specified upper end (~every school night) |
| Comprehension recording | **1 per night, 60 s** (the max) | duration cap `_maxDurationSec = 60` |
| Recording size | **480 KB** (64,000 bps × 60 s ÷ 8 = 480,000 bytes) | `comprehension_recording_step.dart` RecordConfig; 2 MB hard ceiling is the pathological worst case |
| Audio kept | **full year, never cleaned** | retention cron exists but is config-gated off by default |
| Parent app usage | 200 sessions/yr × ~50 reads | 4–5 realtime listeners/child + health probe (1 read/180 s) |
| Parent sign-in SMS | **4 / year** | `phonePrimary` parents get an SMS every fresh sign-in (new device, reinstall, logout); sessions otherwise persist |
| Teacher interaction | 1 comment/wk + 1 audio playback/wk × 40 wks | upper end |
| Teachers | 1 per 25 students, 1 MFA-SMS login/week | upper end |
| Incremental stats aggregation | **ON** (live in prod since 2026-07-02) | legacy fallback covered in §6 |
| Free tiers | **ignored** in per-student figures (gross) | free-tier reality covered in §5 |

## 2. Table A — variable cost per student-year

Region `australia-southeast1` (Sydney) throughout. Usage totals: **24,257 Firestore reads · 1,230 writes · 1,800 function invocations · 96 MB audio · ~6 SMS**.

| Line | Quantity /student-yr | Unit price (USD) | USD/yr | AUD/yr |
|---|---|---|---|---|
| Firestore reads | 24,257 | $0.038 / 100k | 0.0092 | 0.0133 |
| Firestore writes | 1,230 | $0.115 / 100k | 0.0014 | 0.0020 |
| Firestore storage (docs+indexes ~0.75 MB) | ~0.4 MB avg | $0.115 / GiB-mo | 0.0005 | 0.0007 |
| Functions invocations | 1,800 | $0.40 / M | 0.0007 | 0.0010 |
| Functions vCPU (0.167 vCPU × 0.5 s avg) | 150 vCPU-s | $0.0000336 /s (Tier 2) | 0.0051 | 0.0073 |
| Functions memory (256 MiB × 0.5 s avg) | 225 GiB-s | $0.0000035 /s | 0.0008 | 0.0011 |
| Storage: audio at rest (keep-all, yr-1 avg 48 MB) | 0.045 GiB-avg | $0.023 / GiB-mo | 0.0123 | 0.0178 |
| Storage ops (200 uploads + 480 reads) | Class A/B | $0.005 / $0.0004 per 1k | 0.0012 | 0.0017 |
| Egress: audio playback (40 × 480 KB = 19.2 MB) | 0.018 GiB | $0.19 / GiB (AU) | 0.0034 | 0.0049 |
| Egress: Firestore responses (~1.5 KB/read) | ~35 MiB | $0.19 / GiB | 0.0066 | 0.0095 |
| **Firebase subtotal** | | | **0.0412** | **0.0593** |
| Parent phone-auth SMS (4 sign-ins/yr) | 4 SMS | $0.02 / SMS (AU) | 0.0800 | 0.1152 |
| Teacher MFA SMS, amortised (52 SMS/teacher ÷ 25) | 2.1 SMS | $0.02 / SMS (AU) | 0.0416 | 0.0599 |
| **Total variable per student-year** | | | **US$0.163** | **A$0.23** |

Read composition (largest first): reconciler 10,608 (weekly full recompute of all counted logs, student + class passes) · parent app sessions 10,000 · log-night triggers 1,400 · reminders 624 · streak/top-reader crons 625 · teacher views 600 · comprehension confirm 400. FCM push (reminders, awards, comments) is free.

**Notable:** SMS is over half the variable cost — the weekly stats reconciler and the parent app's realtime listeners cost more reads than the actual logging path — and none of it is worth optimising: the cost-audit fixes (#331–334) already flattened the hot path.

## 3. Table B — AI transcription per student-year (separated, as requested)

200 recordings × 60 s = **200 audio-minutes/student/year**. No transcription is deployed today (playback-only); Speech-to-Text V2 is enabled on the project as the planned pipeline (`docs/AI_EVALUATION_PLAN.md`).

| Provider / mode | USD/min | USD/student-yr | **AUD/student-yr** |
|---|---|---|---|
| **Google STT V2 sync — the planned pipeline** | 0.016 | 3.20 | **4.61** |
| Google STT V2 dynamic batch | 0.003 | 0.60 | **0.86** |
| OpenAI whisper-1 | 0.006 | 1.20 | 1.73 |
| OpenAI gpt-4o-mini-transcribe | 0.003 | 0.60 | 0.86 |
| Gemini 2.5 Flash (thinking off) | ~0.0024 | 0.48 | 0.69 |
| Gemini 2.5 Flash-Lite | ~0.00066 | 0.13 | **0.19** |

Optional second stage, kept separate:

| LLM evaluation of transcripts | per call | USD/student-yr | AUD/student-yr |
|---|---|---|---|
| Claude Haiku 4.5 (~1.5k in / 200 out tokens) | $0.0025 | 0.50 | **0.72** |
| — same via Anthropic Batch API (−50%) | $0.00125 | 0.25 | 0.36 |

**Cross-check:** upper-end bundle (sync STT + Haiku) = **A$5.33/student-yr**, vs the internal estimate in `AI_COMPREHENSION_EVAL_CHECKLIST.md` of 2.6¢/recording × 200 = A$5.20 — within 2.5%. Both models agree.

**Vs the A$12/student/yr add-on price:** sync pipeline → 56% GM; batch STT + Haiku (A$1.58) → 87% GM; Gemini Flash-Lite transcription alone (A$0.19) → ~98% GM before evaluation cost (the backlog's single-stage Vertex bake-off would put the whole pipeline near that). The post-v1 backlog item "STT batch recognition" is worth ~A$3.75/student/yr of margin.

## 4. Table C — fixed platform costs (annual, AUD)

| Line | A$/yr | Note |
|---|---|---|
| SendGrid Essentials | **344.83** | US$19.95/mo. Free plan **retired May 2025** (60-day trial only). Massively oversized for onboarding-only volume — cheapest lever in this table |
| Apple Developer Program | 149.00 | AU price |
| Cloud Run SSR portals (school + admin) | ≤86 | scale-to-zero, no min-instances; estimate, upper |
| Cron compute floor (15 jobs, 3 × every-5-min) | ≤35 | ~920 invocations/day, mostly free-tier |
| Domains (.com + .app, Cloudflare at-cost) | 35.52 | |
| Cloud Scheduler (15 jobs, 3 free) | 20.74 | 12 × US$0.10/mo |
| Firebase Hosting overage (est) | ≤17 | 4 targets; free tier covers pilot traffic |
| Artifact Registry (function + portal images) | ~4–20 | 69 Gen2 function images ~3 GiB; portal deploy images accumulate without a cleanup policy — worth adding one |
| Firestore 7-day PITR (enabled in prod) | ~2–5 | US$0.2025/GiB-mo; grows with data (~0.6 GiB @ 800 students). Scheduled backups, when added, would be a similar-sized new line |
| Cloudflare status worker | 0 | free tier (100k req/day per Cloudflare docs; 30 s edge cache) |
| FCM, Firebase Auth MAU (<50k) | 0 | free |
| App Check | 0 today | mobile attestation free; the hardening plan's web rollout uses reCAPTCHA Enterprise — free to 10k assessments/mo, then US$1/1k (small but non-zero at 800+ students) |
| **Total fixed** | **≈ A$696/yr (A$58/mo)** | Google Play US$25 was one-time, excluded |

## 5. Table D — per-student totals by platform scale, and free-tier reality

| Platform students | Fixed/student | + Variable | **Core /student-yr** | + AI (sync) | + AI (batch) |
|---|---|---|---|---|---|
| 80 (pilot school) | 8.70 | 0.23 | **A$8.94** | 14.27 | 10.52 |
| 250 | 2.78 | 0.23 | **A$3.02** | 8.35 | 4.60 |
| 800 | 0.87 | 0.23 | **A$1.10** | 6.43 | 2.69 |
| 5,000 | 0.14 | 0.23 | **A$0.37** | 5.70 | 1.96 |

**Free tiers make the real bill even smaller** (gross figures above ignore them):
- Firestore: 50k reads/day free ⇒ absorbs ~750 students' average daily reads — but the Sunday reconciler spike (~204 reads/student on its run day) exhausts the daily quota from ~245 students, so partial billing starts there.
- Writes: 20k/day free ⇒ ~5,900 students. Functions: 2M invocations/mo ⇒ ~13,000 students; compute free tier covers the cron floor.
- Auth SMS: first 10/day free ⇒ at ~6 SMS/student/yr, covers ~600 students before SMS bills at all.
- **Cloud Storage: no free tier in Sydney** (Firebase's no-cost quota is US-regions-only since the 2024/25 change) — audio bills from the first byte. At pilot scale, audio storage is essentially *the only variable line actually billed*.

Net effect: below ~250 platform students the true marginal Google bill is ~A$0.02–0.04/student/yr; the gross A$0.23 is the honest at-scale figure.

**Margins vs price** (core, no AI, infrastructure-only): retail band A$15/13/11 → 40% GM at a stand-alone 80-student platform, 77% at 250, 90% at 800+; wholesale A$7 at 5,000 students → 95%. B2C family (A$39/yr) → ~99% infrastructure margin, **but** consumer iOS subscriptions must clear Apple IAP's 15–30% commission (direct Stripe sales are shelved per `docs/direct-sales-future-design.md`), and the school channel absorbs the agreed KAKA percentage — neither appears in these infrastructure margins. The AI add-on at A$12 carries 56% GM on sync STT, 87% on batch (§3).

## 6. Sensitivities and risks

1. **AI launch vs the A$100/mo budget alert.** The alert watches the Google bill, which today is only ~A$16–30/mo at 80–800 students (SendGrid and Apple are billed outside GCP). Sync-STT AI spend lands on that same Google bill at ~A$0.44/student/mo: +A$36/mo at 80 students (fits), +A$111/mo at 250 (alert fires), +A$355/mo at 800. Raise the budget or ship batch STT (−81%) before enabling beyond a pilot school.
2. **Incremental-aggregation regression.** If `platformConfig/incrementalAggregation` were ever flipped off, every log write re-reads all of the student's logs plus the class's logs (legacy O(N) path): late-year cost per log night goes from ~7 reads to ~200–5,000. Worst case ≈ A$0.55/student/yr in reads plus some function time — a 10× multiplier on the Firestore line, still small absolute dollars, but it would also hammer the daily free tier.
3. **Audio retention off (current default).** Keep-everything grows storage ~96 MB/student/yr *cumulatively* — by year 3 the at-rest line is ~5× year 1's, and the nightly `reconcileStorageUsage` full-bucket scan grows with object count. Enabling `comprehensionRetention` (e.g. 90–180 days) caps it; at 90 days the at-rest line drops ~60% and stops compounding.
4. **Worst-case audio (2 MB cap × 200 nights = 400 MB/student/yr)** ⇒ storage+egress ≈ A$0.10–0.17/student/yr — still negligible; the cap does its job.
5. **Year-2+ growth.** The weekly reconciler recomputes from *all-time* logs, so its annual read total grows by ~20.8k reads/student each year (+A$0.011/yr, compounding linearly). Fine for years; a candidate for year-scoped recompute someday.
6. **SendGrid** is half the fixed base for a transactional-only workload (~hundreds of emails/mo). Moving to a cheaper transactional provider or SMTP relay saves ~A$250–300/yr — material at pilot scale (it's A$3–4/student at an 80-student platform), irrelevant at 5,000.
7. **SMS is now the top variable line and the one per-unit cost an attacker can drive** (A$0.029/SMS). `smsRateLimits` defaults disabled and fails open; parent `phonePrimary` sign-ins multiply exposure. The security checklist already tracks this (P2-1/P2-4) — this analysis strengthens the case for enabling the limiter.

## 7. Methodology appendix

**Per-log-night trace** (incremental ON): client `set()` on `schools/{id}/readingLogs/{logId}` (`lib/services/reading_log_service.dart` `writeLog`) → `validateReadingLog` (1 read, 0 writes when valid) + `aggregateStudentStats` (~3 reads, 1 write via `applyStudentStatsDelta`) + `updateClassStats` (~2–3 reads, 1 write) (`functions/src/index.ts`, `functions/src/stats_aggregation.ts`) → student-doc update fires `detectAchievements` + `notifyAwardChanges`, which exit with zero billable reads/writes on a normal night (thresholds are hardcoded; award identity unchanged). Audio: client upload to `schools/{id}/comprehension_audio/{logId}.m4a` + `confirmComprehensionAudioUpload` (2 reads, 1 write; `functions/src/comprehension_retention.ts`) + `trackStorageObjectFinalized` (1 write, `functions/src/storage_usage.ts`). The audio-confirm write re-fires both stats triggers but hits `isStatsNoopUpdate` and exits before any read.

**Recording maths:** `RecordConfig(aacLc, bitRate 64000, sampleRate 22050, mono)`, 60 s cap (`lib/screens/parent/widgets/comprehension_recording_step.dart`) ⇒ 64,000 bps × 60 s ÷ 8 = 480,000 bytes. 200 nights ⇒ 96 MB (0.089 GiB).

**Cron amortisation:** weekly `reconcileStatsScheduled` re-reads each student's counted logs (avg ~100 in year 1) in both the student and class passes ⇒ 52 × 102 × 2 ≈ 10.6k reads/student-yr. `refreshStreaksDaily` 1 read/day; `topReaderAward` ~5 reads/wk; hourly `sendReadingReminders` touches each parent ~once per reminder-day (~3 reads, Mon–Thu default).

**Function compute:** 1,800 invocations × 0.5 s avg × (0.167 vCPU / 0.25 GiB), Cloud Run Tier 2 rates. Every function on the log-night path is pinned `concurrency: 1` (Gen1-parity migration; two parent-doc triggers elsewhere use 10).

**SMS model:** parents authenticate via phone (`parent_registration_modal.dart` `phonePrimary`/`emailMfa` flows; `functions/src/mfa_enrollment.ts` handles role "parent") ⇒ 1 SMS per fresh sign-in, modelled at 4/yr; teachers 1 MFA login SMS/wk ÷ 25 students.

**Pricing sources (all fetched + independently re-verified 2026-07-15):** cloud.google.com/firestore/pricing (Sydney rows) · cloud.google.com/run/pricing (Sydney = Tier 2) · cloud.google.com/scheduler/pricing · cloud.google.com/storage/pricing (Sydney; no-cost quota US-only per firebase.google.com/pricing) · cloud.google.com/speech-to-text/pricing (V2 SKUs) · developers.openai.com/api/docs/pricing · ai.google.dev/gemini-api/docs/pricing (audio = 32 tok/s) · platform.claude.com/docs/en/about-claude/pricing (Haiku 4.5 $1/$5 per MTok, batch −50%) · cloud.google.com/identity-platform/pricing (Auth SMS country table: AU $0.02) · sendgrid.com/pricing (free plan retired 2025-05-27) · ECB reference rate via Frankfurter (AUD 1.4404/USD, 2026-07-14).

**Internal cross-checks:** AI bundle A$5.33 vs `docs/AI_COMPREHENSION_EVAL_CHECKLIST.md` 2.6¢/recording (A$5.20) ✓ · modelled Google bill A$16–30/mo at ≤800 students sits comfortably under the live A$100/mo budget alert ✓ · read-path economics consistent with `OPTIMIZATION_SUMMARY.md` login-path analysis.

---

*Produced 2026-07-15 from a code-trace of the live paths plus web-verified vendor pricing; independently re-verified by adversarial arithmetic/code/pricing/completeness review passes.*
