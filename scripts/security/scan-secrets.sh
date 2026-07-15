#!/usr/bin/env bash
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks is required (https://github.com/gitleaks/gitleaks)." >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
history_report="$(mktemp -t lumi-gitleaks-history.XXXXXX.json)"
trap 'rm -f "$history_report"' EXIT

echo "Scanning complete Git history (secret values redacted)..."
gitleaks git "$repo_root" \
  --redact=100 \
  --report-format json \
  --report-path "$history_report" \
  --no-banner \
  --no-color

if [[ "$#" -eq 0 ]]; then
  echo "History scan passed. Pass artifact paths to scan build outputs too."
  exit 0
fi

for target in "$@"; do
  if [[ ! -e "$target" ]]; then
    echo "Artifact path does not exist: $target" >&2
    exit 2
  fi
  echo "Scanning artifact path (secret values redacted): $target"
  gitleaks dir "$target" \
    --redact=100 \
    --max-archive-depth 2 \
    --no-banner \
    --no-color
done

echo "History and artifact scans passed."
