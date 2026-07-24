# Backup Restore Drill — Record — ST4S D3

**Version 0.1 — DRAFT template** · 2026-07-24
*Do one restore drill, fill this in, sign, and save it to the evidence pack (folder `EV8`/`D3`). This filled record is the D3 evidence. Repeat at least annually.*

> **Why:** D3 asks you to prove backup **restoration has been tested** — not just that backups exist. You perform a test restore, confirm the data came back correctly, and record it here.

---

## 1. Drill details
- **Date performed:** __________
- **Performed by:** Nicholas Plevritis (Security Lead)
- **Systems in scope:** ☐ Firestore  ☐ Cloud Storage  ☐ Both
- **Type:** ☐ Point-in-time recovery (PITR)  ☐ Restore from export/backup

## 2. Method
- **Source restored from:** [e.g. Firestore PITR to timestamp 2026-07-__ 09:00 AEST, or export gs://…]
- **Target (NOT production):** [test project / separate database / test collection — name it]
- **Steps taken:** [brief numbered list — e.g. 1. triggered PITR to test DB; 2. …]

## 3. Results
| Measure | Result |
|---|---|
| **RTO** — time from start to data available | ______ (target: [e.g. < 4 h]) |
| **RPO** — how recent the recovered data was | ______ (target: [e.g. ≤ 24 h / near-zero with PITR]) |
| **Completeness** — record counts vs source (spot-check) | ☐ matched / notes: ______ |
| **Integrity** — security rules re-applied + verified (rules hash) | ☐ ok |
| **Isolation** — cross-tenant negative check on restored data | ☐ ok |

## 4. Outcome
- **Result:** ☐ Pass  ☐ Pass with issues  ☐ Fail
- **Issues found / follow-ups:** ______
- **Next drill due:** [annually, or after a major infrastructure change]

## 5. Sign-off
Performed & verified by: Nicholas Plevritis   Signature: ____________   Date: __________

---
*Reference: the Disaster Recovery Plan (EV8) describes the full RTO/RPO targets and restore runbook this drill exercises.*
