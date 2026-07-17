#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-lumi-ninc-au}"
REGION="${LUMI_FUNCTIONS_REGION:-australia-southeast1}"
RUNTIME_SA="lumi-functions-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
OLD_SA="serviceAccount:${PROJECT_ID}@appspot.gserviceaccount.com"

command -v gcloud >/dev/null
command -v jq >/dev/null

jobs_json="$(mktemp -t lumi-scheduler-jobs.XXXXXX.json)"
functions_json="$(mktemp -t lumi-scheduled-functions.XXXXXX.json)"
trap 'rm -f "$jobs_json" "$functions_json"' EXIT

gcloud scheduler jobs list \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --format=json >"$jobs_json"

unexpected_jobs="$(
  jq --arg runtime "$RUNTIME_SA" \
    '[.[] | select(.httpTarget.oidcToken.serviceAccountEmail != $runtime)] | length' \
    "$jobs_json"
)"
if [[ "$unexpected_jobs" -ne 0 ]]; then
  echo "FAIL: $unexpected_jobs Scheduler job(s) do not use $RUNTIME_SA" >&2
  jq -r --arg runtime "$RUNTIME_SA" \
    '.[] | select(.httpTarget.oidcToken.serviceAccountEmail != $runtime) | .name' \
    "$jobs_json" >&2
  exit 1
fi

gcloud functions list \
  --v2 \
  --regions="$REGION" \
  --project="$PROJECT_ID" \
  --format=json >"$functions_json"

failures=0
while IFS=$'\t' read -r function_name service_name; do
  policy="$(
    gcloud run services get-iam-policy "$service_name" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format=json
  )"
  if ! jq -e --arg member "serviceAccount:$RUNTIME_SA" '
      any(.bindings[]?;
        .role == "roles/run.invoker" and
        any(.members[]?; . == $member)
      )
    ' <<<"$policy" >/dev/null; then
    echo "FAIL: $function_name ($service_name) lacks runtime Run Invoker" >&2
    failures=$((failures + 1))
  fi
  if jq -e --arg old "$OLD_SA" '
      any(.bindings[]?;
        .role == "roles/run.invoker" and
        any(.members[]?; . == $old)
      )
    ' <<<"$policy" >/dev/null; then
    echo "FAIL: $function_name ($service_name) still grants the old default identity" >&2
    failures=$((failures + 1))
  fi
done < <(
  jq -r '.[] |
    select(.labels["deployment-scheduled"] == "true") |
    [(.name | split("/")[-1]), (.serviceConfig.service | split("/")[-1])] |
    @tsv' "$functions_json"
)

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

job_count="$(jq 'length' "$jobs_json")"
echo "PASS: $job_count Scheduler jobs use the dedicated runtime identity; scheduled services have only the expected invoker."
