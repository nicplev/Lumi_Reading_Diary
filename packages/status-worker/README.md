# @lumi/status-worker

A tiny Cloudflare Worker that serves Lumi's out-of-band status message.

This exists so the app can surface a banner ("Lumi is having trouble — your
reading still saves locally.") even when Firebase itself is the outage. It
must never depend on Firebase.

## Endpoints

- `GET /status` — public, edge-cached 30s. Returns the current `StatusPayload`
  or an empty payload (`version: 0, id: null`) when KV is empty.
- `POST /status` — requires `Authorization: Bearer $ADMIN_TOKEN`. Body is
  validated and written to KV. Returns the normalized payload.
- `DELETE /status` — requires auth. Clears KV (back to empty).

## Payload shape

```json
{
  "version": 3,
  "id": "2026-05-27-firebase-outage",
  "message": "Lumi is having trouble — your reading still saves locally.",
  "severity": "warn",
  "updatedAt": "2026-05-27T10:00:00Z",
  "dismissible": true,
  "minAppVersion": null,
  "platforms": ["ios", "android", "web"]
}
```

- `version` is monotonic. Bump it whenever you change content. The in-app
  client dedupes dismissals by `version:id`.
- `id` is a stable human-readable slug for the message. Same `id` + bumped
  `version` re-shows the banner to users who previously dismissed it.
- `severity` controls colour: `info` → blue, `warn` → yellow, `critical` →
  red.
- `dismissible: false` hides the X button. Use sparingly.
- `minAppVersion`, `platforms` are reserved for v2 (targeting / force update);
  the v1 client ignores them.

## First-time setup

```bash
pnpm install
pnpm --filter @lumi/status-worker wrangler login
pnpm --filter @lumi/status-worker wrangler kv:namespace create STATUS_KV
pnpm --filter @lumi/status-worker wrangler kv:namespace create STATUS_KV --preview
# Paste the IDs into wrangler.toml
pnpm --filter @lumi/status-worker wrangler secret put ADMIN_TOKEN
pnpm --filter @lumi/status-worker deploy
```

## Publishing a message

```bash
curl -X POST https://lumi-status-worker.<your-zone>.workers.dev/status \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "version": 4,
    "id": "2026-05-27-fb",
    "message": "Lumi is having trouble — your reading still saves locally.",
    "severity": "warn",
    "dismissible": true
  }'
```

## Clearing a message

```bash
curl -X DELETE https://lumi-status-worker.<your-zone>.workers.dev/status \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

The client treats empty state (`id: null`) as "nothing to show" but
**does not** clear its local cache, so a brief Worker blip never wipes a
real message.
