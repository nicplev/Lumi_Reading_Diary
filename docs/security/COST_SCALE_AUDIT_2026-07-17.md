# Lumi cost and scale audit

**Date:** 17 July 2026
**Scope:** Firestore reads/writes, teacher dashboard queries, parent/teacher
history queries, listeners, document IDs, counters and service-health probes.
**Outcome:** Pass for the tested 30/100/1,000-student profiles. The login-path
collection-group scan is removed, all-time mobile histories use bounded cursor
pagination, and the calendar/teacher-home aggregate paths use server-owned,
transaction-safe daily summary shards instead of raw multi-week log scans.

## TL;DR

- Production's 30-day peak was 9,689 Firestore reads/hour and 1,964
  writes/hour. Alerts now fire at 20,000 reads/hour and 5,000 writes/hour.
- The unbounded UID-to-school resolver was replaced by a server-owned index.
  The production backfill converged at 38 memberships with zero conflicts.
- A Rules-backed emulator profile passed at 30, 100 and 1,000 students.
- The retained detailed weekly query grows linearly only when an optional card
  needs raw sentiment/group detail: 210, 700 and 7,000 logs. Recent activity
  remains capped at 15.
- Calendar, weekly chart, hero intelligence and teacher home-widget refresh now
  read at most eight shards per active day. The scale profile read 56 weekly
  shards at every school size; a 12-week view is capped at 672 reads rather than
  2,520, 8,400 or 84,000 raw logs.
- Parent All-time/Bookshelf and teacher student-history requests load 30 logs
  per page with a stable date/document-ID cursor. Partial totals and search
  results are clearly labelled until older pages are explicitly loaded.
- Every manually owned snapshot subscription inspected has a cancellation path.
- The foreground service-health probe was relaxed from every 180 seconds to
  every 600 seconds while retaining connectivity, resume, explicit-retry and
  queue-failure checks. That reduces its steady-state periodic reads by 70%.

## Evidence

The test in `functions/test/dashboard_scale.integration.test.js` seeds one
completed reading log per student per day for seven days, authenticates as the
assigned teacher and runs the real Firestore Rules.

| Students | Raw weekly logs | Weekly summary shards | Recent documents | Raw 12-week projection | Summary 12-week maximum |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 210 | 56 | 15 | 2,520 | 672 |
| 100 | 700 | 56 | 15 | 8,400 | 672 |
| 1,000 | 7,000 | 56 | 15 | 84,000 | 672 |

Emulator timings are diagnostic, not production latency promises. Document
counts are the useful billing/scaling signal.

Production deployment evidence: Firestore Rules and the `classDailyReading`
composite index are live; the index reports `READY`. Both the idempotent
Eventarc synchronizer and Melbourne weekly reconciler report `ACTIVE` on the
pinned `lumi-functions-runtime` identity. Eventarc retries transient failures,
and the scheduler's OIDC identity is limited to that same runtime account. An
aggregate-only production reconciliation verified **697 eligible logs** and
**12,857 minutes** exactly across **459 summary shards**, with zero inconsistent
shards. No error-level service logs appeared after the final deployment.

Production baseline measured over the preceding 30 days:

| Signal | Observed maximum/current | Alert threshold |
| --- | ---: | ---: |
| Firestore reads | 9,689/hour; 33,180/day | >20,000/hour |
| Firestore writes | 1,964/hour | >5,000/hour |
| Cloud Run egress | about 4.5 MB/hour | >50 MiB/hour |
| Firebase user-content Storage egress | about 1.5 MB/hour | >50 MiB/hour |
| Firebase user-content Storage footprint | about 2.8 MB | >250 MiB |

## Query findings

### Closed

- `resolveUserSchoolByUid` no longer performs an unbounded collection-group
  scan. It reads `userMembershipIndex/{uid}`, verifies the authoritative
  membership, and retains only a migration-only query limited to ten top-level
  legacy index records.
- The UID index is maintained by two Eventarc triggers and is unreadable and
  unwritable by clients. A production create/resolve/delete canary passed.
- Recent dashboard activity is capped at 15 documents.
- Weekly dashboard data is bounded by a date range and shared by the widgets
  that consume it, avoiding duplicate widget-level fetches in the main view.
- Reading-log IDs are random 128-bit identifiers, not sequential IDs.
- Student and class totals use incremental aggregation with reconciliation,
  rather than re-reading every historic log on ordinary writes.
- Parent and teacher all-time student histories are capped at 30 records per
  request. The Firestore document-snapshot cursor includes the ordered date and
  implicit document-ID tie-breaker. A 65-log identical-timestamp emulator case
  returned 30 + 30 + 5 unique records with no gap or duplicate.
- `classDailyReading` uses eight deterministic shards per class/day. A student's
  logs always use the same shard, keeping unique-reader counts exact while
  avoiding a single hot class counter. Only the Admin SDK writes summaries;
  Rules require an assigned class for teacher queries and deny parents,
  unrelated teachers and all client writes.
- The per-log `readingLogSummaryState` projection makes writes idempotent and
  event-order safe. The transaction reads the current authoritative log, so
  duplicate or reordered create/validation/update/delete events converge. A
  weekly reconciler rebuilds summaries from projection state; an emulator test
  repaired deliberately corrupted totals and removed a stale shard.
- The service-health controller's periodic server-source probe is now 600
  seconds. Event-driven probes still run when connectivity returns, the app
  resumes, the user retries, or the offline queue reports a failure.

### Remaining pilot measurements

1. Measure real production listener concurrency after schools begin using the
   new mobile build and tune billing alerts from observed traffic.
2. Optional detailed sentiment/group/top-reader cards retain one bounded
   current-week raw-log fetch because their source attributes are intentionally
   absent from the minimised daily summary. Revisit only if pilot volume makes
   that seven-day detail query material.

## Listener ownership audit

Manual `.listen()`/subscription sites were checked in the active-child,
access, school-library assignment, parent-linking, teacher-dashboard, audio and
offline-sync paths. Each has a corresponding cancel, `onCancel`, scope-reset or
`dispose` path. Direct `StreamBuilder` subscriptions are owned and disposed by
Flutter. No orphaned listener was found in this static audit.

Repeat the audit whenever a new manual `.listen()` is introduced; the pull
request security gate calls this out explicitly.

## Required follow-up

- Add production pilot profiles for realistic numbers of logs per child,
  comments and concurrent listeners, then tune alert thresholds from measured
  behaviour.
- Review Firestore Data Access log volume after one week now that read/write
  audit logging is enabled; apply exclusions only to proven high-volume,
  low-security-value entries and never to admin/config mutation evidence.

## Pilot gate

- **Current demo/small pilot:** pass with monitoring.
- **Normal 30-student class:** pass; retain alerts and measure real use.
- **100-student class:** pass for tested query shapes; measure concurrency.
- **1,000-student synthetic profile:** pass for pagination and summary query
  shapes. This is a query-scale result, not a claim that one 1,000-student class
  is an intended product configuration.
