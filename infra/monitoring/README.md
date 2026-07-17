# Lumi production monitoring

This directory is the checked-in source of truth for the extra cost and
security anomaly alerts added on 17 July 2026. The policies notify both
verified security channels:

- `nic@lumi-reading.com`
- `nicxplev@gmail.com`

The thresholds are deliberately conservative early warnings based on the
preceding 30 days of production data. Review them after a real school pilot or
any planned load test.

| Signal | 30-day hourly maximum | Alert threshold |
| --- | ---: | ---: |
| Firestore reads | 9,689 | >20,000/hour |
| Firestore writes | 1,964 | >5,000/hour |
| Cloud Run egress | 4.5 MB | >50 MiB/hour |
| Firebase user-content Storage egress | 1.5 MB | >50 MiB/hour |
| Firebase user-content Storage footprint | 2.8 MB current | >250 MiB |

Storage policies explicitly filter to
`lumi-ninc-au.firebasestorage.app`; Cloud Functions build and source buckets
must not affect these alerts.

Three log-match policies also alert on high-signal events that can be missed by
volume thresholds:

- comprehension-audio security failures;
- account/student deletion job failures; and
- developer impersonation anomalies.

Together with the five pre-existing function, Rules, App Check and
authentication policies, production has **13 enabled alert policies**. Both
`DATA_READ` and `DATA_WRITE` audit logging are enabled for
`datastore.googleapis.com` in the project IAM audit configuration. Review the
resulting log volume after a week before considering narrowly scoped
exclusions. A post-enable production probe verified that Firestore
`ListCollectionIds`, `RunQuery` and `Commit` entries are arriving in the
`cloudaudit.googleapis.com/data_access` log; Firestore emits them with service
name `firestore.googleapis.com` even though its audit configuration uses
`datastore.googleapis.com`.

## Apply or update

Run `./infra/monitoring/apply.sh` from the repository root while authenticated
to project `lumi-ninc-au`. The script matches policies and the dashboard by
display name, so it updates instead of duplicating them.

After applying, confirm every policy is enabled and still includes both
notification channels. A separate temporary delivery-test policy may be used
to prove email delivery; do not keep that deliberately firing policy enabled.
