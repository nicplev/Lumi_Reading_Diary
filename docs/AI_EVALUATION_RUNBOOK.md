# AI Comprehension Evaluation — Operations Runbook

**Scope:** the dark-shipped pipeline from PRs #456 (enqueue), #457 (worker/sweep) and the retention cron. Design: `docs/AI_EVALUATION_GEMINI_PLAN.md` · execution checklist: `docs/AI_COMPREHENSION_EVAL_CHECKLIST.md`.

**Prod state assumptions:** project `lumi-ninc-au`, all AI processing pinned to `australia-southeast1`. No API keys exist — auth is the Functions runtime SA **`lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com`** with `roles/speech.client` + custom role `lumiAiEvalPredictor` (`aiplatform.endpoints.predict`), plus bucket-level `roles/storage.objectUser` on the audio bucket and a per-service `roles/run.invoker` binding on each trigger service.

> **Service-identity gotcha (cost a debugging cycle on 2026-07-20):** an earlier record named `lumi-ninc-au@appspot.gserviceaccount.com` as the runtime SA. It is not. Always derive it from the deployed service:
> `gcloud run services describe <service> --project lumi-ninc-au --region australia-southeast1 --format="value(spec.template.spec.serviceAccountName)"`

---

## 1. Kill switch (the fastest OFF)

`platformConfig/aiEvaluation` — the ONLY client-readable AI doc. **Fail-closed**: missing doc, read error, or anything but literal `{enabled: true}` means OFF.

- **Emergency stop (no deploy):** set `{enabled: false}` in the Firestore console. Effects: enqueue stops creating jobs immediately; the worker re-checks the gate at every claim, so queued/deferred jobs terminate as `done/disabled` **without any provider spend**. UI surfaces hide (client gate reads the same doc, fail-closed).
- Server config caches are ≤60s; worst case a minute of stragglers.
- Turning back ON re-processes nothing automatically (jobs already terminated as `disabled` stay done). New recordings enqueue normally.

Per-school stop: clear `schools/{id}.settings.aiEvaluation.enabled` (super-admin portal, Phase 6 card). Same fail-closed semantics, same claim-time re-check.

## 2. Budget knobs (`aiEvalOpsConfig/runtime`, deny-all, 60s server cache)

| Field | Default | Notes |
|---|---|---|
| `model` | `gemini-2.5-flash` | MUST be in the code allowlist (`config.ts`); a non-allowlisted value defers every job with `config_invalid` + error log — it never routes elsewhere. Changing model = evaluated release at a term boundary (see §6). |
| `defaultDailyCapPerSchool` | 200 | Used when a school has no `adminMeta/aiEvaluation.capPerDay`. |
| `globalDailyCap` | 1000 | Derived value: `max(default, 1.2 × Σ enabled schools' capPerDay)` — recomputed on entitlement changes (Phase 6). |
| `minDurationSec` | 4 | Below this: `flagged:too_short`, zero spend. |
| `maxTranscriptChars` | 8000 | Truncation before the LLM call. |
| `evalTimeoutSec` | 60 | Per provider call. |
| `maxAttempts` | 3 | Then poison + teacher-visible `failed` eval. |
| `transcriptRetentionDays` | 90 | §5. |
| `evalRetentionDays` | 730 | §5 — stated in the privacy notice; changes need privacy review. |
| `promptVersion` | 1 | Bump ONLY with a rubric/prompt release at a term boundary; classification cache is promptVersion-scoped. |
| `costAlarmDailyUsd` | 25 | Sweep logs `aiEval.sweep.costAlarm` at error level above this. |

**Spend guards, in order:** fail-closed kill switch → per-school `capPerDay` (hard stop) → sharded global daily cap (hard stop) → GCP billing budget `Lumi AI eval (Vertex+Speech) daily-scale guard` (A$150/mo on the Vertex AI + Cloud Speech SKUs, alerts at 50/90/100% — **alert-only**, it does not stop spend; the app-level caps are the enforcement).

## 3. Job states + triage

`aiEvalJobs/{schoolId}_{logId}` (deny-all): `queued → processing → done | failed | deferred | poisoned`.

- **`deferred`** (`deferredReason`): `school_cap` / `global_cap` — normal at cap; sweep retries on the first run after the Sydney date rolls. `stt_quota` / `provider_quota` — capacity 429s; also retried after date roll; **chronic quota deferrals = start the Provisioned Throughput conversation, do NOT raise caps blindly**. `config_invalid` — fix `model` in ops config, jobs retry via sweep.
- **`failed`** — transient (5xx, unparseable/invalid model output). Sweep retries while `attempts < maxAttempts`.
- **`poisoned`** — gave up; a `status:failed, flags:[system_error]` eval doc was written so the teacher sees "couldn't evaluate", never eternal pending. Triage: check `lastError` on the job → if systemic (bug/outage), fix cause, then re-run by setting the job back to `{status:"queued", attempts:0}` (console) — the sweep's stale-queued clause picks it up within ~1h+sweep interval; the eval doc is idempotently overwritten.
- **Stuck `processing`** — sweep reclaims after 2×timeout+5min automatically.
- **Sweep health:** `opsMetrics/cronHeartbeats.sweepAiEvalJobs` (admin dashboard, stale after 8h). `aiEval.sweep.chronicBacklog` (error log, 3 consecutive full pages) = the documented **Cloud Tasks escalation trigger**.

## 4. Provider outage posture: SAFE TO WAIT

Audio persists ≥ the retention floor; jobs defer/fail-retry; nothing is lost by waiting. **Never** fall back to another region/provider ad hoc — that breaks the residency guarantee. If Vertex AU is down for days, the correct move is a human decision with privacy review, not an ops toggle.

## 5. Retention clocks (cron `aiEvalRetention`, daily 03:30 Sydney)

1. Transcripts cleared from eval docs after `transcriptRetentionDays` (90d) → `transcriptRemovedAt` stamped; UI shows "transcript removed after N days". Monotonic cursor in `aiEvalOpsConfig/retentionState` (reset the cursor to re-scan history after restoring from backup).
2. Whole eval docs deleted after `evalRetentionDays` (730d) — APP 11.2; the period is stated in the collection notice.
3. Classification cache entries deleted after ~365d.
4. Audio retention is separate (`cleanupComprehensionAudio`, 04:00 Sydney, portal-configured days). **Teacher/manual audio deletion leaves the eval intact by design** (audio deletion ≠ assessment retraction) — guarded by a unit test.
5. Student/account deletion: the existing deletion cascade must be extended to evals/jobs **before any school is enabled** (checklist Phase 0/8 gate — not yet done).

Timing order overnight (Sydney): 00:00 sweep (deferred re-run on fresh budget) → 03:30 AI retention → 04:00 audio retention.

## 6. Model succession watch (do at every term boundary)

1. Check the pinned model's deprecation/shutdown dates on its Vertex model page. **`gemini-2.5-flash` retires October 2026.**
2. Probe candidate successors on the Sydney endpoint (`functions/scripts/ai-eval-prompt-regression.mjs` with `MODEL=<candidate>` — 10/10 required) + a positive control.
3. Record a probe-evidence row in `AI_EVALUATION_GEMINI_PLAN.md` §12, add the model to the code allowlist (PR), then flip `aiEvalOpsConfig/runtime.model`.
4. Model changes segment report trends (Phase 7) — treat like a rubric bump: term boundary only, bump `promptVersion` if the prompt also changed.
5. Migrating with <6 weeks of model runway is an incident, not a task.

## 7. Cost + usage queries

- Daily pipeline counters: sum `aiEvalOpsConfig/metrics_{YYYY-MM-DD}_shard{0..9}` — fields: `evaluated, flagged, failed, deferred, poisoned, safetyBlocks, sttSeconds, inputTokens, outputTokens, thoughtsTokens, cachedTokens, llmCalls, classificationCalls, estCostUsdMillis`.
- Per-school monthly (invoicing): `schools/{id}/meta/aiEvalUsage` → `{"YYYY-MM": {...}}` — reconcile against the invoice generator.
- `thoughtsTokens` should be ~0 (`thinkingBudget:0` is pinned). Non-trivial values = model/config drift → investigate before costs move.
- `safetyBlocks` rising = Gemini safety filters false-positiving on child speech — pilot tuning signal, review flagged evals with the teacher.
- Billing truth: GCP console → Billing → filter service "Vertex AI" + "Cloud Speech API". The in-app `estCostUsdMillis` is an estimate from the code price table (`config.ts`) — update the table when Google reprices.

## 8. Prompt/adversarial regression (run before ANY prompt/model/rubric change ships)

```bash
cd functions && npm run build
TOKEN="$(gcloud auth print-access-token)" PROJECT=lumi-ninc-au \
  node scripts/ai-eval-prompt-regression.mjs        # add MODEL=… for candidates
```
10/10 required. Synthetic fixture only — never feed real child content through this script. Extend `test/fixtures/ai_evaluation_adversarial_transcripts.json` when a new failure mode is found in pilot (keep `syntheticOnly: true`).

## 9. IAM / API surface (recorded 2026-07-19, rollback commands in plan §12)

- `aiplatform.googleapis.com` + `speech.googleapis.com` enabled.
- Runtime SA: `roles/speech.client` + `projects/lumi-ninc-au/roles/lumiAiEvalPredictor` (`aiplatform.endpoints.predict` only).
- **No secrets. No API keys.** Nothing to rotate; SA key hygiene is the platform's standard posture.
- STT regional sync quota: 211 req/min vs maxInstances 5 — revisit before fleet scale.

## 10. Deploy / rollback map

| Piece | Deploy | Rollback |
|---|---|---|
| Enqueue (rides in `confirmComprehensionAudioUpload`) | `firebase deploy --only functions:confirmComprehensionAudioUpload` | Revert PR #456 + redeploy same target |
| Worker + sweep + retention | `firebase deploy --only functions:processAiEvalJob,functions:sweepAiEvalJobs,functions:aiEvalRetention,functions:cleanupComprehensionAudio` | `firebase functions:delete processAiEvalJob sweepAiEvalJobs aiEvalRetention` + revert |
| Kill switch / entitlements / ops config | Firestore console or super-admin portal — **no deploy** | Same, instantly |
| Rules/indexes | Already live since Phase 1 (PR #390) | n/a |

Everything deploys dark: with `platformConfig/aiEvaluation {enabled:false}` (current prod state) the new functions are inert — the worker only ever runs if a job doc is created, and nothing creates job docs while the switch is off.
