# Remote status messages

Operator runbook for the in-app banner served by the Cloudflare
status-worker. Used when you need to tell every user something out-of-band
— most often during a Firebase outage, when in-Firestore announcements
can't be loaded.

## What the user sees

A coloured strip at the very top of the app, above the impersonation and
service-status banners. Tap-dismissible by default (with the X button);
re-shows if you publish a higher version under the same id.

Severity drives the colour:

| Severity   | Background           | Use when                                          |
|------------|----------------------|---------------------------------------------------|
| `info`     | Sky blue, dark text  | FYI / scheduled maintenance window / new feature  |
| `warn`     | Soft yellow, dark    | Lumi is impaired; user-visible degradation        |
| `critical` | Error red, white     | Severe issue; non-dismissible by default          |

## One-time setup

1. **Save the bearer token** somewhere safe. It's a long string starting
   with letters/digits — generated when the worker was deployed and stored
   as a Cloudflare Worker secret. There is no way to retrieve it from the
   dashboard. If you lose it:
   ```
   cd packages/status-worker
   ./node_modules/.bin/wrangler secret put ADMIN_TOKEN
   ```
   Then update everywhere it's stored.

2. **Stash it in the macOS keychain** so the helper script picks it up
   automatically:
   ```
   ./scripts/status-message.sh token-set
   # paste token at the (hidden) prompt
   ```

That's it. The script will resolve the token from the keychain on every
subsequent call.

## Publishing a message

```bash
./scripts/status-message.sh warn "Lumi is having trouble — your reading still saves locally."
./scripts/status-message.sh info "Reminder times will reset Sunday 02:00 UTC during scheduled work."
./scripts/status-message.sh critical "Logging is temporarily unavailable. We're investigating."
```

Defaults that "just work":
- **id**: `YYYY-MM-DD-<severity>` (today's date + severity). One re-run on
  the same day re-uses the same id.
- **version**: auto-incremented from the currently-published version under
  the same id. New id → version 1. Re-running with the same id → version
  N+1. Bumping the version is what re-shows the banner to users who
  already dismissed the previous one.
- **dismissible**: true for info/warn, **false** for critical.

Override any of them:

```bash
./scripts/status-message.sh warn "Custom message" \
  --id "fb-outage-2026-05-29" \
  --version 7 \
  --no-dismiss
```

## Reading the current message

```bash
./scripts/status-message.sh show
```

Empty state (`version: 0, id: null`) means no banner is being shown.

## Clearing

```bash
./scripts/status-message.sh clear
```

Removes the message. In-app clients see the banner disappear on their
next poll (≤60 s) or whenever they next foreground the app.

Important: clients **do not** wipe their local cache when they receive
the empty state. This is on purpose — a brief Worker blip can't drop a
real announcement. The banner will hide on the next successful empty
fetch.

## How the in-app client uses each field

| Field           | Effect                                                                  |
|-----------------|-------------------------------------------------------------------------|
| `version`       | Monotonic. Bumping it re-shows after a user dismissed the prior copy.   |
| `id`            | Stable slug. Dismissals are keyed by `version_id`.                       |
| `message`       | Plain text, max 280 chars (longer is truncated by the Worker).          |
| `severity`      | Colour: `info`=blue, `warn`=yellow, `critical`=red.                     |
| `dismissible`   | When false the X button is hidden.                                      |
| `updatedAt`     | Set by the Worker on every POST. Shown in the connection-status screen. |
| `minAppVersion` | Blocks older releases behind the update screen. Malformed policy fails into support mode. |
| `platforms`     | Optional `ios` / `android` targeting for the minimum-version policy.    |

## Typical workflow during an outage

1. **Confirm the outage** (Firebase status page, your own dashboards).
2. **Publish a warn**: `./scripts/status-message.sh warn "Lumi is having trouble — your reading still saves locally."`
3. **If it escalates**, re-publish with severity `critical` and add `--no-dismiss` (auto-set already).
4. **When resolved**: `./scripts/status-message.sh clear`.
5. **Optional post-mortem info message**: `./scripts/status-message.sh info "We had a 23-minute issue from 14:00-14:23 UTC. Logged sessions are now syncing."` — let it stay up for an hour, then clear.

## Posting from another environment

If you're not on the deploy laptop, the same Worker accepts curl from
anywhere:

```bash
curl -X POST https://lumistatus.aged-morning-985b.workers.dev/status \
  -H "Authorization: Bearer $LUMI_STATUS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "version": 3,
    "id": "fb-outage-2026-05-29",
    "message": "Lumi is having trouble — your reading still saves locally.",
    "severity": "warn",
    "dismissible": true
  }'
```

## What the user CAN'T do remotely (yet)

The v1 client deliberately keeps the JSON small. Things to defer to v2:
- Per-platform targeting for ordinary banners (minimum-version targeting is supported)
- Per-role targeting (only show parents, only show teachers)
- CTA button + URL on the banner
- Markdown / rich text

If any of those become urgent, extend `packages/status-worker/src/index.ts`
and `lib/core/models/remote_message.dart` together — the client safely
ignores fields it doesn't know about, so adding new fields is
non-breaking.
