#!/usr/bin/env bash
set -euo pipefail

# Firebase Hosting's preview Next.js integration injects __FIREBASE_DEFAULTS__
# whenever it sees the Firebase JS SDK. That enables firebase-frameworks'
# authenticated-server-context bridge, which is redundant for Lumi: the admin
# portal verifies its own HttpOnly session cookie with the Admin SDK. The
# bridge also attempts a server-side Identity Toolkit request with Lumi's
# browser-referrer-restricted API key, causing authenticated SSR requests to
# fail with HTTP 500.
#
# A Hosting release pins its Cloud Run revision by tag. After creating the
# bridge-disabled revision, move the live release's existing tag to that new
# revision so both ordinary service traffic and the Hosting rewrite are fixed.

project_id="${LUMI_PROJECT_ID:-lumi-ninc-au}"
region="${LUMI_ADMIN_REGION:-australia-southeast1}"
service="${LUMI_ADMIN_SERVICE:-ssrlumidevadminau}"
site="${LUMI_ADMIN_HOSTING_SITE:-lumi-dev-admin-au}"

for command in curl gcloud jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: $command is required" >&2
    exit 2
  fi
done

access_token="$(gcloud auth print-access-token)"
release_json="$(mktemp -t lumi-admin-release.XXXXXX)"
trap 'rm -f "$release_json"' EXIT

curl --fail --silent --show-error \
  -H "Authorization: Bearer ${access_token}" \
  -H "x-goog-user-project: ${project_id}" \
  "https://firebasehosting.googleapis.com/v1beta1/projects/${project_id}/sites/${site}/channels/live/releases?pageSize=1" \
  >"$release_json"

hosting_tag="$(
  jq -r '.releases[0].version.config.rewrites[]?.run.tag // empty' \
    "$release_json" | head -n 1
)"

if [[ -z "$hosting_tag" || ! "$hosting_tag" =~ ^fh-[a-f0-9]+$ ]]; then
  echo "error: could not determine the live Firebase Hosting Cloud Run tag" >&2
  exit 1
fi

gcloud run services update "$service" \
  --project="$project_id" \
  --region="$region" \
  --update-env-vars='__FIREBASE_DEFAULTS__=' \
  --quiet

latest_revision="$(
  gcloud run services describe "$service" \
    --project="$project_id" \
    --region="$region" \
    --format='value(status.latestReadyRevisionName)'
)"

if [[ -z "$latest_revision" ]]; then
  echo "error: repaired Cloud Run revision did not become ready" >&2
  exit 1
fi

gcloud run services update-traffic "$service" \
  --project="$project_id" \
  --region="$region" \
  --update-tags="${hosting_tag}=${latest_revision}" \
  --quiet

tagged_revision="$(
  gcloud run services describe "$service" \
    --project="$project_id" \
    --region="$region" \
    --format=json |
    jq -r --arg tag "$hosting_tag" \
      '.status.traffic[] | select(.tag == $tag) | .revisionName'
)"

if [[ "$tagged_revision" != "$latest_revision" ]]; then
  echo "error: Hosting tag did not move to the repaired revision" >&2
  exit 1
fi

echo "Admin Firebase Frameworks auth bridge disabled on the live Hosting revision."
