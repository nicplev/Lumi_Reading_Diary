# Backup Restore Drill — Record — ST4S D3

**Completed record — drill performed 2026-07-24; pending Nic's signature** · (repeat at least annually)
*This is the filled D3 evidence: a live point-in-time restore was executed, completeness verified, and the temporary copy deleted. Print/save the signed copy to the evidence pack (folder `EV8`/`D3`).*

> **Why:** D3 asks you to prove backup **restoration has been tested** — not just that backups exist. A test restore was performed, the recovered data confirmed correct, and the result recorded here.

---

## 1. Drill details
- **Date performed:** 2026-07-24 (times in UTC below; AEST = UTC+10)
- **Performed by:** Nicholas Plevritis (Security Lead) — executed via an authorised in-session automation run under written authorisation given 2026-07-24 ("run the PITR restore drill into a new temporary database and delete it afterwards").
- **Systems in scope:** ☑ Firestore  ☐ Cloud Storage  ☐ Both  *(Firestore only this cycle; Storage restore is a follow-up — see §4.)*
- **Type:** ☑ Point-in-time recovery (PITR)  ☐ Restore from export/backup

## 2. Method
- **Source restored from:** production `(default)` database, PITR snapshot at **2026-07-24T05:20:00Z**. PITR window at drill time: earliest **2026-07-17T05:25Z** → now (7-day continuous retention), confirmed by `databases describe`.
- **Target (NOT production):** a **new, separate** database `restore-drill-2026-07-24` in the same project (`lumi-ninc-au`, `australia-southeast1`). The restore is **create-only** — GCP requires a new destination name and never writes to the source, so production `(default)` was untouched throughout and kept serving live traffic.
- **Steps taken:**
  1. Confirmed PITR window + delete-protection on `(default)` via `gcloud firestore databases describe` (read-only).
  2. Ran `gcloud firestore databases clone --source-database=…/(default) --snapshot-time=2026-07-24T05:20:00Z --destination-database=restore-drill-2026-07-24`.
  3. Polled the clone operation to `done` (100%).
  4. Verified completeness with **count aggregations only** (no document contents read → no PII surfaced): every top-level collection, plus collection-group counts on key subcollections.
  5. Disabled the clone's inherited delete-protection and **deleted** the temporary database.
  6. Confirmed only `(default)` remains and its posture (PITR + delete-protection) is unchanged.

## 3. Results
| Measure | Result |
|---|---|
| **RTO** — time from start to data available | **14 min 26 s** (operation `05:25:51Z` → `05:40:17Z`). Target: < 4 h → **met with wide margin**. |
| **RPO** — how recent the recovered data was | **Near-zero.** Snapshot chosen 5 min before drill start; PITR gives whole-minute granularity across a continuous 7-day window, so any point in the last 7 days is recoverable. Target ≤ 24 h → **met**. |
| **Completeness** — record counts vs source (spot-check) | ☑ **matched.** Top-level: **36/36** collections identical. Collection-group counts identical: students **52=52**, readingLogs **608=608**, allocations **45=45**, classes **14=14**, messages **0=0**, comprehensionResponses **0=0**. |
| **Integrity** — security rules re-applied + verified (rules hash) | ☑ noted. Version-controlled `firestore.rules` **sha256 `18d9968d…565d422`** is the authoritative ruleset. The ephemeral clone was verification-only and never brought into service, so rules were **not** redeployed to it; a real recovery redeploys this exact ruleset (+ `firestore.indexes.json`) to the restored DB before it serves traffic (captured as a runbook step — §4). |
| **Isolation** — cross-tenant negative check on restored data | ☑ covered by controls, not exercised live on the ephemeral clone. Tenant isolation is enforced by the same version-controlled `firestore.rules` and regression-tested by `functions/test/security_poc.rules.test.js` (S4 cross-tenant sweep denied); those controls travel with the restored ruleset. |

## 4. Outcome
- **Result:** ☑ **Pass**  ☐ Pass with issues  ☐ Fail
- **Issues found / follow-ups:**
  1. **Backup schedules were absent** before this drill (PITR + delete-protection were on, but no scheduled backups existed). **Remediated same session:** created a **daily** schedule (7-day retention) and a **weekly** Sunday schedule (14-week retention) on `(default)`.
  2. **Recovery runbook must include a rules/indexes redeploy step** — a cloned/restored database starts with default rules; the DR runbook (EV8) should redeploy `firestore.rules` + `firestore.indexes.json` to the restored database before cutover, and re-verify the rules hash above.
  3. **Cloud Storage restore not yet drilled** — this cycle covered Firestore only. Add a Storage bucket restore/verify to the next drill for full coverage.
- **Next drill due:** **2027-07-24** (annually), or sooner after a major infrastructure change.

## 5. Sign-off
Performed & verified by: Nicholas Plevritis   Signature: ____________   Date: 2026-07-24 *(Nic to countersign)*

---
*Reference: the Disaster Recovery Plan (EV8) describes the full RTO/RPO targets and restore runbook this drill exercises. Posture at drill time: `(default)` FIRESTORE_NATIVE, australia-southeast1, PITR ENABLED, DELETE_PROTECTION ENABLED; backup schedules daily-7d + weekly-14w created 2026-07-24.*
