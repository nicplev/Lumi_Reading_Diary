#!/usr/bin/env bash
set -euo pipefail

PROJECT="lumi-ninc-au"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MONITORING_DIR="$ROOT/infra/monitoring"

for file in "$MONITORING_DIR"/policies/*.json; do
  display_name="$(jq -r '.displayName' "$file")"
  matches="$(
    gcloud monitoring policies list \
      --project="$PROJECT" \
      --filter="displayName=\"$display_name\"" \
      --format='value(name)'
  )"
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"

  if (( match_count > 1 )); then
    echo "Refusing to update duplicate policies named: $display_name" >&2
    exit 1
  elif (( match_count == 1 )); then
    gcloud monitoring policies update "$matches" \
      --project="$PROJECT" \
      --policy-from-file="$file" \
      --quiet >/dev/null
    echo "Updated: $display_name"
  else
    gcloud monitoring policies create \
      --project="$PROJECT" \
      --policy-from-file="$file" \
      --quiet >/dev/null
    echo "Created: $display_name"
  fi
done

dashboard_name="$(jq -r '.displayName' "$MONITORING_DIR/dashboard.json")"
dashboards="$(
  gcloud monitoring dashboards list \
    --project="$PROJECT" \
    --filter="displayName=\"$dashboard_name\"" \
    --format='value(name)'
)"
dashboard_count="$(printf '%s\n' "$dashboards" | sed '/^$/d' | wc -l | tr -d ' ')"

if (( dashboard_count > 1 )); then
  echo "Refusing to update duplicate dashboards named: $dashboard_name" >&2
  exit 1
elif (( dashboard_count == 1 )); then
  temporary_config="$(mktemp)"
  trap 'rm -f "$temporary_config"' EXIT
  etag="$(gcloud monitoring dashboards describe "$dashboards" --project="$PROJECT" --format='value(etag)')"
  jq --arg name "$dashboards" --arg etag "$etag" '. + {name: $name, etag: $etag}' \
    "$MONITORING_DIR/dashboard.json" >"$temporary_config"
  gcloud monitoring dashboards update "$dashboards" \
    --project="$PROJECT" \
    --config-from-file="$temporary_config" \
    --quiet >/dev/null
  echo "Updated dashboard: $dashboard_name"
else
  gcloud monitoring dashboards create \
    --project="$PROJECT" \
    --config-from-file="$MONITORING_DIR/dashboard.json" \
    --quiet >/dev/null
  echo "Created dashboard: $dashboard_name"
fi
