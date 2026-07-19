# Comprehension audio control reconciliation

Status: implemented and verified locally on 19 July 2026

## Policy decisions

- The super-admin recording switch is an emergency platform-wide ceiling. When
  off, collection and playback stop everywhere. Re-enabling restores each
  school's saved preference; it does not opt schools in.
- A school admin opts their school in or out, records authority/family-notice
  evidence, and chooses 30, 90 or 365 days. Seven days is no longer selectable.
- A legacy stored 7-day choice remains valid only for deleting already-held
  audio on day 7. It cannot authorise new collection. The school must explicitly
  choose 30+ before collection resumes; Lumi never silently extends 7 to 30.
- Turning recording off stops playback but does not purge. Manual deletion is
  always available, and automatic retention continues independently.
- Automatic retention is always active. The super-admin value is a fallback
  for schools without a valid stored choice, not a switch that can suspend a
  school's deletion commitment.

## Implementation

1. Mirror the zero-import Functions audio-authority module into server-ops and
   pin parity in CI. Add explicit playback and retention-source helpers.
2. Make super-admin Run now match the cron: school-scoped cutoffs, canonical
   paths, pending-object deletion, path quarantine, bounded pagination, shared
   stats and audit shape.
3. Standardise run stats around deleted/failed/duration, school and retention
   buckets, fallback count, legacy-7 count, configured fallback and trigger.
4. Remove the retention enable/disable control. Enforce a configurable fallback
   range of 30-730 days while safely defaulting invalid/legacy platform values
   to 90 days.
5. Gate playback at both server paths: the Flutter signed-URL callable and the
   school-admin streaming route. Client surfaces hide mic/player affordances;
   server checks remain authoritative.
6. Harden server-ops and school-admin deletion paths to derive canonical final
   and pending paths from trusted school/log IDs and clear the complete receipt.
7. Test authority parity, 30-day validation, legacy 7-day cleanup, playback
   precedence, canonical deletion/quarantine, stats compatibility and UI gates.

Verification completed with Functions unit/lint/build checks, Flutter analysis
and widget tests, both portal production builds and typechecks, authority/stats
tests, Storage Rules emulators, the Functions audio emulator suite, and the
server-ops manual-retention emulator suite.

## Effective precedence

| Platform | School | Collection | Playback | Retention |
| --- | --- | --- | --- | --- |
| On | On + current authority | Allowed | Allowed | School choice |
| On | Off | Blocked | Blocked | Saved choice continues |
| Off | Any | Blocked | Blocked | Saved choice continues |

Deletion remains available in every row. Demo preview audio stays local-only.
