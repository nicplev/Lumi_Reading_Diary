#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-lumi-ninc-au}"
REGION="${LUMI_ADMIN_REGION:-australia-southeast1}"
FUNCTION_NAME="${LUMI_ADMIN_FUNCTION:-ssrlumidevadminau}"
PROJECT_NUMBER="${LUMI_PROJECT_NUMBER:-3795320704}"
BUILD_SA="lumi-admin-build@${PROJECT_ID}.iam.gserviceaccount.com"
RUNTIME_SA="lumi-super-admin-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
DEPLOY_SA="github-actions-admin@${PROJECT_ID}.iam.gserviceaccount.com"
CLOUD_BUILD_AGENT="service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
SOURCE_BUCKET="gcf-v2-sources-${PROJECT_NUMBER}-${REGION}"

for command in gcloud jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "FAIL: $command is required" >&2
    exit 2
  fi
done

function_json="$(
  gcloud functions describe "$FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format=json
)"

expected_build="projects/${PROJECT_ID}/serviceAccounts/${BUILD_SA}"
actual_build="$(jq -r '.buildConfig.serviceAccount // empty' <<<"$function_json")"
actual_runtime="$(jq -r '.serviceConfig.serviceAccountEmail // empty' <<<"$function_json")"

if [[ "$actual_build" != "$expected_build" ]]; then
  echo "FAIL: $FUNCTION_NAME build identity is $actual_build, expected $expected_build" >&2
  exit 1
fi
if [[ "$actual_runtime" != "$RUNTIME_SA" ]]; then
  echo "FAIL: $FUNCTION_NAME runtime identity is $actual_runtime, expected $RUNTIME_SA" >&2
  exit 1
fi

project_policy="$(gcloud projects get-iam-policy "$PROJECT_ID" --format=json)"
project_roles="$(
  jq -c --arg member "serviceAccount:$BUILD_SA" \
    '[.bindings[] | select(.members[]? == $member) | .role] | sort' \
    <<<"$project_policy"
)"
if [[ "$project_roles" != '["roles/logging.logWriter"]' ]]; then
  echo "FAIL: $BUILD_SA project roles are $project_roles; expected only Logs Writer" >&2
  exit 1
fi

build_policy="$(
  gcloud iam service-accounts get-iam-policy "$BUILD_SA" \
    --project="$PROJECT_ID" \
    --format=json
)"
expected_build_policy="$(
  jq -cn \
    --arg deploy "serviceAccount:$DEPLOY_SA" \
    --arg agent "serviceAccount:$CLOUD_BUILD_AGENT" \
    '[
      {role: "roles/iam.serviceAccountTokenCreator", members: [$agent]},
      {role: "roles/iam.serviceAccountUser", members: [$deploy]}
    ]'
)"
actual_build_policy="$(
  jq -c '[.bindings[]? | {role, members: (.members | sort)}] | sort_by(.role)' \
    <<<"$build_policy"
)"
if [[ "$actual_build_policy" != "$expected_build_policy" ]]; then
  echo "FAIL: $BUILD_SA attachment/token policy has unexpected drift" >&2
  exit 1
fi

repo_policy="$(
  gcloud artifacts repositories get-iam-policy gcf-artifacts \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --format=json
)"
repo_roles="$(
  jq -c --arg member "serviceAccount:$BUILD_SA" \
    '[.bindings[] | select(.members[]? == $member) | .role] | sort' \
    <<<"$repo_policy"
)"
if [[ "$repo_roles" != '["roles/artifactregistry.writer"]' ]]; then
  echo "FAIL: $BUILD_SA repository roles are $repo_roles; expected only Artifact Registry Writer" >&2
  exit 1
fi

bucket_policy="$(
  gcloud storage buckets get-iam-policy "gs://${SOURCE_BUCKET}" --format=json
)"
bucket_roles="$(
  jq -c --arg member "serviceAccount:$BUILD_SA" \
    '[.bindings[] | select(.members[]? == $member) | .role] | sort' \
    <<<"$bucket_policy"
)"
if [[ "$bucket_roles" != '["roles/storage.objectViewer"]' ]]; then
  echo "FAIL: $BUILD_SA source-bucket roles are $bucket_roles; expected only Storage Object Viewer" >&2
  exit 1
fi

secret_policy="$(
  gcloud secrets get-iam-policy ADMIN_SESSION_SECRET_AU \
    --project="$PROJECT_ID" \
    --format=json
)"
if jq -e --arg member "serviceAccount:$BUILD_SA" '
    any(.bindings[]?; any(.members[]?; . == $member))
  ' <<<"$secret_policy" >/dev/null; then
  echo "FAIL: build identity must not have access to the admin runtime secret" >&2
  exit 1
fi

user_key_count="$(
  gcloud iam service-accounts keys list \
    --iam-account="$BUILD_SA" \
    --project="$PROJECT_ID" \
    --managed-by=user \
    --format=json | jq 'length'
)"
if [[ "$user_key_count" -ne 0 ]]; then
  echo "FAIL: $BUILD_SA has $user_key_count user-managed key(s)" >&2
  exit 1
fi

echo "PASS: admin build and runtime identities are dedicated, keyless and least privilege."
