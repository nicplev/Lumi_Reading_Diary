#!/usr/bin/env bash
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks is required (https://github.com/gitleaks/gitleaks)." >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
tmp_root="$(mktemp -d -t lumi-gitleaks.XXXXXX)"
history_report="$tmp_root/history.json"
trap 'rm -rf "$tmp_root"' EXIT

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

archive_index=0
for target in "$@"; do
  if [[ ! -e "$target" ]]; then
    echo "Artifact path does not exist: $target" >&2
    exit 2
  fi

  scan_target="$target"
  max_archive_depth=2
  case "$target" in
    *.apk|*.aab|*.ipa|*.APK|*.AAB|*.IPA)
      if ! command -v unzip >/dev/null 2>&1; then
        echo "unzip is required to scan packaged mobile artifacts." >&2
        exit 2
      fi
      archive_index=$((archive_index + 1))
      scan_target="$tmp_root/mobile-$archive_index"
      mkdir -p "$scan_target"
      # APK/AAB/IPA are ZIP containers. Gitleaks can otherwise report a
      # successful zero-byte scan, so extract them before accepting evidence.
      unzip -oq "$target" -d "$scan_target"
      file_count="$(find "$scan_target" -type f | wc -l | tr -d ' ')"
      if [[ "$file_count" -eq 0 ]]; then
        echo "Packaged artifact contained no files: $target" >&2
        exit 1
      fi
      echo "Scanning $file_count extracted files (secret values redacted): $target"
      max_archive_depth=0
      ;;
    *)
      echo "Scanning artifact path (secret values redacted): $target"
      ;;
  esac

  gitleaks dir "$scan_target" \
    --redact=100 \
    --max-archive-depth "$max_archive_depth" \
    --no-banner \
    --no-color
done

echo "History and artifact scans passed."
