# AI comprehension evaluation — production deploy evidence, 2026-07-20

Deploy of the dark AI-evaluation pipeline (PRs #454–#465) to `lumi-ninc-au`. Runbook: `docs/AI_EVALUATION_RUNBOOK.md` · status table: `docs/AI_COMPREHENSION_EVAL_CHECKLIST.md`.

## Pre-flight (all green before touching prod)

| Check | Result |
|---|---|
| `platformConfig/aiEvaluation` | `{enabled: false}` — kill switch OFF |
| `aiEvalJobs` collection | 0 documents |
| Schools with `settings.aiEvaluation.enabled == true` | 0 |
| functions lint / build / units | 0 errors · pass · 218/218 |
| Deletion emulator integration | 2/2 |

Zero entitled schools is the property that made the later canary safe: with the platform switch on, nothing but the canary school could enqueue.

## Functions deployed (australia-southeast1, Node 22 Gen2)

`firebase deploy --only functions:…` — 4 created, 6 updated, all `ACTIVE`:

- **created:** `processAiEvalJob`, `sweepAiEvalJobs`, `aiEvalRetention`, `generateStudentReportNarrative`
- **updated:** `confirmComprehensionAudioUpload` (enqueue + question snapshot), `cleanupComprehensionAudio` (fixed cron), `requestAccountDeletion`, `requestStudentDeletion`, `getMyDeletionStatus`, `processPendingUserDeletions` (deletion cascade extension)

Schedules verified in Cloud Scheduler:

| Job | Schedule | TZ | State |
|---|---|---|---|
| `sweepAiEvalJobs` | `0 */6 * * *` | Australia/Sydney | ENABLED |
| `aiEvalRetention` | `30 3 * * *` | Australia/Sydney | ENABLED |
| `cleanupComprehensionAudio` | `0 4 * * *` | Australia/Sydney | ENABLED (was floating "every 24 hours") |

Post-deploy dark state re-verified: kill switch still `false`, `aiEvalJobs` still 0 documents.

## School portal deployed

`FIREBASE_CLI_EXPERIMENTS=webframeworks firebase deploy --only hosting:school` → release complete, SSR revision updated. `https://lumi-school-admin-au.web.app/login` → HTTP 200. Portal source tree verified byte-identical (`git rev-parse <commit>:school-admin-web`) between the deploying checkout and `origin/main`, so the artifact matches the reviewed code.

Admin portal was already live: CI auto-deployed it on the #460 merge.

## E2E canary (synthetic content only)

Script: `functions/scripts/ai-eval-canary.mjs` (committed). Audio is macOS `say` speech — never a child. Creates a throwaway `zz_canary_ai_eval` school and removes **every** artifact in a `finally` block.

**FINAL RESULT: both phases PASS** (after the two IAM fixes below).

**Phase A — negative, zero provider spend: PASS.** With the kill switch OFF and the canary school entitled, the deployed worker claimed the job, re-checked the gate and terminated `status: done, doneReason: disabled`, **no eval doc, no provider call**. This is the fail-closed guarantee verified against real production infrastructure, not a unit test.

**Phase B — positive, full pipeline: PASS.** Kill switch ON briefly → job → STT (Sydney) → Gemini (Sydney) → eval doc written:

- job `done`, eval `status: complete`, `overallLevel: secure`
- transcript: *"The dog found a bone in the garden and then he buried at near the big tree because he did not want the cat to take it."* (one benign ASR slip, "buried at" for "buried it" — exactly the disfluency-tolerance the prompt is built for)
- summary: *"The student accurately recalled the initial event of the dog finding a bone and burying it, providing details about where and why. The events were presented in a logical order."*

**Cleanup on every run:** residue check `{job:false, school:false, evalDoc:false, audio:false}` → zero residue, kill switch confirmed back to `false`.

Re-run any time: `cd functions && node scripts/ai-eval-canary.mjs <synthetic.m4a>`.

## INCIDENT FOUND: missing `run.invoker` on two Cloud Run services

The canary surfaced a **pre-existing production incident unrelated to this feature**.

Gen2 Firestore-triggered functions are invoked by Eventarc as `lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com`, which needs `roles/run.invoker` **per service**. Healthy services (`aggregatestudentstats`, `updateclassstats`, `validatereadinglog`, `sweepaievaljobs`, `aievalretention`, `cleanupcomprehensionaudio`) all carry that binding. Two do not:

| Service | Missing since | Observed failures (7d) | Owner |
|---|---|---|---|
| `maintainclassdailyreading` | **2026-07-16 23:27 UTC** | 390 | pre-existing — NOT from this work |
| `processaievaljob` | creation (2026-07-19) | 10 (canary only) | this deploy |

Symptom in logs: `The request was not authenticated… The IAM principal lacks {run.routes.invoke} permission.` Eventarc retries and gives up; the function body never executes.

**Timeline points at a hardening pass:** project IAM `SetIamPolicy` removals were recorded at 2026-07-16 23:24 UTC (3 minutes before the first failure). The binding for `maintainclassdailyreading` appears to have been dropped there. `processaievaljob`'s binding was simply never created by the deploy.

**Impact assessment:**
- `maintainClassDailyReading` maintains sharded class daily-reading aggregates on reading-log writes. Live updates have been failing since Jul 16 — **but `reconcileClassDailyReadingScheduled` is running successfully** (heartbeat `ok @ 2026-07-18T18:30Z`), which recomputes those aggregates. So the effect is *delayed/stale* class daily-reading figures between reconciles, not permanent data loss.
- `processAiEvalJob` — no impact today (feature dark, zero jobs). If left unfixed when the pilot starts, evaluations would not run on upload; the 6-hourly sweep's stale-queued clause would eventually pick them up (it calls the worker inline and has a working invoker binding), so results would appear hours late rather than never.

**RESOLVED 2026-07-20** — both bindings applied and verified; `maintainclassdailyreading` immediately resumed executing (403 WARNINGs replaced by INFO executions). All **25** Eventarc-triggered services were then audited: no remaining gaps.

**Commands applied:**

```bash
gcloud run services add-iam-policy-binding processaievaljob \
  --project lumi-ninc-au --region australia-southeast1 \
  --member="serviceAccount:lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com" \
  --role="roles/run.invoker"

gcloud run services add-iam-policy-binding maintainclassdailyreading \
  --project lumi-ninc-au --region australia-southeast1 \
  --member="serviceAccount:lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

This restores each service to exactly the binding its healthy siblings already have. Rollback is the same command with `remove-iam-policy-binding`.

**Follow-up worth doing:** add the invoker-binding audit to the deploy checklist — a silently-missing binding produces no error anywhere except the target service's own logs.

## SECOND INCIDENT: AI roles were granted to the wrong service account

With the invoker fixed, Phase B still failed `lastError: http_403` on the first provider call. Root cause was **an error in the Phase 0 IAM work**: the roles were granted to `lumi-ninc-au@appspot.gserviceaccount.com` because that SA name was taken from the plan document, but the functions actually run as **`lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com`**.

Worse, the Phase 0 record asserted the runtime SA already held `roles/speech.client`. It did not — **no principal in the project held that role at all**. The Phase 0 STT probes had run on the operator's own user credentials, which masked the gap completely. A green probe against an endpoint proves the *endpoint* works; it proves nothing about the *service identity* that will call it in production.

**Applied:**
```bash
gcloud projects add-iam-policy-binding lumi-ninc-au \
  --member="serviceAccount:lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com" \
  --role="projects/lumi-ninc-au/roles/lumiAiEvalPredictor"
gcloud projects add-iam-policy-binding lumi-ninc-au \
  --member="serviceAccount:lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com" \
  --role="roles/speech.client"
# least privilege — the appspot SA never needed it
gcloud projects remove-iam-policy-binding lumi-ninc-au \
  --member="serviceAccount:lumi-ninc-au@appspot.gserviceaccount.com" \
  --role="projects/lumi-ninc-au/roles/lumiAiEvalPredictor"
```

Note the roles take **1–3 minutes to propagate**: a canary run ~30 s after granting still returned 403, and the same run ~4 minutes later passed. Docs corrected in the same PR (plan §12.5, runbook header, checklist Phase 0 rows).

**Final runtime SA role set:** `lumiAiEvalPredictor`, `roles/speech.client`, `roles/datastore.user`, `roles/eventarc.eventReceiver`, `roles/firebaseappcheck.tokenVerifier`, `lumiFcmSender`, `lumiFunctionsAuthRuntime`, plus bucket-level `roles/storage.objectUser` and per-service `roles/run.invoker`.
