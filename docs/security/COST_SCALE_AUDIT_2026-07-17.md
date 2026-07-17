# Lumi cost and scale audit

**Date:** 17 July 2026
**Scope:** Firestore reads/writes, teacher dashboard queries, parent/teacher
history queries, listeners, document IDs, counters and service-health probes.
**Outcome:** Conditional pass for the current demo/pilot volume. The login-path
collection-group scan is removed and the tested rules remain authorised at
1,000 students, but long histories and the optional multi-week calendar still
need bounded pagination or materialised summaries before a large-school pilot.

## TL;DR

- Production's 30-day peak was 9,689 Firestore reads/hour and 1,964
  writes/hour. Alerts now fire at 20,000 reads/hour and 5,000 writes/hour.
- The unbounded UID-to-school resolver was replaced by a server-owned index.
  The production backfill converged at 38 memberships with zero conflicts.
- A Rules-backed emulator profile passed at 30, 100 and 1,000 students.
- The normal weekly dashboard query grows linearly: seven logs per student are
  210, 700 and 7,000 reads respectively. The recent-activity query stays at 15.
- The optional 12-week raw-log calendar would read 2,520, 8,400 and 84,000
  documents in those profiles. It is unsuitable for a 1,000-student class.
- Every manually owned snapshot subscription inspected has a cancellation path.
- The foreground service-health probe was relaxed from every 180 seconds to
  every 600 seconds while retaining connectivity, resume, explicit-retry and
  queue-failure checks. That reduces its steady-state periodic reads by 70%.

## Evidence

The test in `functions/test/dashboard_scale.integration.test.js` seeds one
completed reading log per student per day for seven days, authenticates as the
assigned teacher and runs the real Firestore Rules.

| Students | Weekly documents | Weekly emulator time | Recent documents | Recent emulator time | Projected 12-week calendar documents |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 210 | 159 ms | 15 | 27 ms | 2,520 |
| 100 | 700 | 90 ms | 15 | 39 ms | 8,400 |
| 1,000 | 7,000 | 877 ms | 15 | 325 ms | 84,000 |

Emulator timings are diagnostic, not production latency promises. Document
counts are the useful billing/scaling signal.

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
- The service-health controller's periodic server-source probe is now 600
  seconds. Event-driven probes still run when connectivity returns, the app
  resumes, the user retries, or the offline queue reports a failure.

### Open before a large-school pilot

1. Parent **All time** activity and Bookshelf still derive from an unbounded
   history stream.
2. Teacher per-student reading history still streams the full history before
   applying local filters.
3. The optional reading calendar streams every raw log in its selected
   4–24-week window. At 1,000 students, the default 12-week profile projects
   84,000 documents for one initial view, before live-listener updates.
4. Teacher home-widget refresh reads 41 days of raw class logs. It is bounded
   by date but remains linear in class activity.

## Listener ownership audit

Manual `.listen()`/subscription sites were checked in the active-child,
access, school-library assignment, parent-linking, teacher-dashboard, audio and
offline-sync paths. Each has a corresponding cancel, `onCancel`, scope-reset or
`dispose` path. Direct `StreamBuilder` subscriptions are owned and disposed by
Flutter. No orphaned listener was found in this static audit.

Repeat the audit whenever a new manual `.listen()` is introduced; the pull
request security gate calls this out explicitly.

## Required remediation

- Paginate parent and teacher all-time histories with a stable `(date,
  documentId)` cursor. Do not replace them with a silent flat cap that makes
  totals or Bookshelf data incorrect.
- Materialise teacher calendar/home summaries before a school whose class can
  generate thousands of logs per week is onboarded. Prefer a bounded,
  server-owned per-class/day summary design with sharding or transaction-safe
  reconciliation; avoid turning one daily document into a write hotspot.
- Add production pilot profiles for realistic numbers of logs per child,
  comments and concurrent listeners, then tune alert thresholds from measured
  behaviour.
- Review Firestore Data Access log volume after one week now that read/write
  audit logging is enabled; apply exclusions only to proven high-volume,
  low-security-value entries and never to admin/config mutation evidence.

## Pilot gate

- **Current demo/small pilot:** pass with monitoring.
- **Normal 30-student class:** pass; retain alerts and measure real use.
- **100-student class:** conditional; hide or replace long calendar ranges and
  complete history pagination first.
- **1,000-student synthetic profile:** no-go for the raw-log calendar and
  unbounded history views until summaries/pagination are shipped and retested.
