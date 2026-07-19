# Evidence capture — Vertex AI generative-AI ML-processing residency, Australia

**Captured:** 2026-07-20 (AEST; page timestamp 2026-07-19T21:35:29Z UTC)
**Source:** https://docs.cloud.google.com/gemini-enterprise-agent-platform/resources/data-residency
(canonical URL redirects from `/vertex-ai/generative-ai/docs/learn/data-residency`)
**Method:** live page read in Chrome; per-cell DOM extraction of the "Google models" support matrix (`span.compare-yes[aria-label="Supported"]` = commitment present). Extraction method validated against known-positive cells (US/EU multi-region) before recording.
**Captured by:** Claude Code session (A-track), for `docs/AI_EVALUATION_GEMINI_PLAN.md` §6 row 2.

---

## Why this document exists

The all-Australian processing claim for Lumi's AI comprehension evaluation has four load-bearing legs (plan §6). Leg 2 is Google's **during-ML-processing** residency commitment for `australia-southeast1` — distinct from at-rest residency, and distinct from merely *calling* a regional endpoint. This is that evidence.

## Google's stated model (quoted from the page)

- **Data-at-rest:** "remains physically stored in the specific Google Cloud location you chose… regardless of which endpoint you use."
- **ML processing** ("the method by which data is processed such that it produces model weights (tuning & training) or applies the model to the data for model inference"): location "is determined by your choice of endpoint."
- **Locational endpoints** (e.g. `australia-southeast1`): "ensure that ML processing remains entirely within the broader multi-regional or country jurisdiction associated with that region."
- **Global endpoints:** "route and process data anywhere globally… they don't provide regional isolation or data residency guarantees." — this is why the code treats `global` as a residency violation, not a fallback.

## The Australia column — finding

Column header: **`Australia (australia-southeast1)`**

| Model row | AU ML-processing commitment |
|---|---|
| **Gemini 2.5 Flash, 128k (`gemini-2.5-flash`)** | ✅ **SUPPORTED** |
| Gemini 2.5 Flash, 1M (`gemini-2.5-flash`) | ❌ not supported (US multi-region, EU multi-region, Canada, Singapore only) |
| Gemini 2.5 Flash-Lite (`gemini-2.5-flash-lite`) | ❌ not supported |
| Gemini 3.5 Flash (`gemini-3.5-flash`) | ❌ not supported |
| Gemini 3.1 Flash-Lite (`gemini-3.1-flash-lite`) | ❌ not supported |
| Gemini 2.5 Pro (64k and 1M) | ❌ not supported |
| Gemini 2.5 Flash Image / Live-native-audio | ❌ not supported |
| Embeddings for Text (`text-embedding-004`) | ✅ supported (not used by Lumi) |

Across the entire Google-models matrix, **exactly two rows carry the Australian commitment**, and only one of them is a generative model: `gemini-2.5-flash` at the **128k context tier**.

## What this means for Lumi

1. **The tier-1 residency claim is available** (plan §6 claims ladder): Australia has the during-ML-processing commitment for the exact model the pipeline pins. Leg 2 is **PASS**, conditional on the context tier below.
2. **The commitment is context-tier-bound.** The same model id appears twice; only the 128k row is covered. A request that pushed into the 1M tier would fall outside the Australian commitment. Lumi's evaluation requests are ~1.8k input / ~1.2k output tokens (≈3–4k total, plan §7) — roughly **1.5% of the 128k ceiling** — but nothing in the data model previously *prevented* a future config change (e.g. raising `maxTranscriptChars`, or batching many transcripts into one call) from crossing it silently.
   → Guard added in the same PR as this capture: `maxTranscriptChars` is clamped at config load and the assembled prompt is asserted against a residency character budget before any provider call. See `functions/src/ai_evaluation/config.ts` + `evaluation.ts`.
3. **The model choice is doubly confirmed.** `gemini-2.5-flash` is the only Gemini that is BOTH served from the Sydney endpoint (probe evidence, plan §12.2) AND covered by the Australian ML-processing commitment. Flash-Lite and every 3.x model fail both tests.
4. **Model-succession risk is now sharper.** Any successor model must be re-checked against BOTH this table and the endpoint probe before it can be added to the code allowlist. Recorded in the runbook's model-succession watch (§6).

## Not covered by this capture (still open)

- **Speech-to-Text residency.** Lumi's transcription uses the Cloud Speech-to-Text V2 API (`australia-southeast1-speech.googleapis.com`), a *different product* from Vertex AI. The Chirp rows in this table are Vertex-hosted Chirp, which Lumi does not use. STT regional serving was validated in the Phase 0 spike (`docs/AI_EVALUATION_PLAN.md`); its formal residency terms should be captured separately before the tier-1 claim is made about the *whole* pipeline rather than the LLM stage.
- Support/telemetry/subprocessor access paths (the standing caveat that keeps "your data never leaves Australia" off-limits as an unqualified absolute — plan §6).
- Vertex generative-AI data-governance terms (no-training-on-customer-data, abuse-monitoring logging posture) — plan §6 leg 3, still to be pinned.

## Verbatim column set (for re-verification)

Google-models table columns as captured: Model · US multi-region · EU multi-region · Brazil (southamerica-east1) · Canada (northamerica-northeast1) · France (europe-west9) · Germany (europe-west3) · Netherlands (europe-west4) · United Kingdom (europe-west2) · **Australia (australia-southeast1)** · India (asia-south1) · Japan (asia-northeast1) · Singapore (asia-southeast1) · South Korea (asia-northeast3).

`Gemini 2.5 Flash, 128k` supported regions as captured: US multi-region, EU multi-region, Brazil, Canada, France, Germany, United Kingdom, **Australia**, India, Japan, Singapore, South Korea.
