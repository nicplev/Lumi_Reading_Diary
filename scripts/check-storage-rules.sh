#!/usr/bin/env bash
# Guardrail: fail if storage.rules reintroduces cross-service Firestore reads.
#
# Storage rules CANNOT read Firestore in this project. The Firebase rules
# compiler reports "Invalid function name: firestore.get" — a WARNING, so the
# deploy still succeeds — and every guarded write then fails closed with
# [firebase_storage/unauthorized].
#
# This has now bitten twice:
#   PR #107  2026-06-19  diagnosed and removed it
#   PR #390  2026-07-15  silently reintroduced it -> comprehension audio AND
#                        community book covers broken for five days, with the
#                        compiler warning printing on every deploy, unread
#   PR #475  2026-07-20  removed it again
#
# A warning nobody reads is not a safeguard, so this makes it an error.
# Firestore-dependent conditions belong in a callable, where they can be
# enforced with Admin credentials — see confirmComprehensionAudioUpload.
#
# Usage: ./scripts/check-storage-rules.sh [path/to/storage.rules]
# Exit 0 clean, 1 on violation. No credentials or network required.

set -uo pipefail
RULES="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/storage.rules}"

if [ ! -f "$RULES" ]; then
  echo "check-storage-rules: cannot find $RULES" >&2
  exit 1
fi

# Ignore comment lines so the explanatory notes in storage.rules don't trip it.
HITS=$(grep -nE '(^|[^[:alnum:]_.])firestore\.(get|exists|getAfter)[[:space:]]*\(' "$RULES" \
       | grep -vE '^[0-9]+:[[:space:]]*//' || true)

if [ -n "$HITS" ]; then
  cat >&2 <<EOF
✖ storage.rules calls Firestore from Storage rules — this DOES NOT WORK here.

$HITS

The compiler only warns ("Invalid function name: firestore.get") so the deploy
would appear to succeed, then every guarded upload would fail closed with
[firebase_storage/unauthorized]. This exact regression broke comprehension
recordings and book covers for five days (PR #390, fixed in #475).

Enforce Firestore-dependent conditions in a callable instead — the pending
upload namespace is untrusted by design and confirmComprehensionAudioUpload
re-validates ownership, gates, signature, size and rate limits with Admin
credentials before promoting anything.
EOF
  exit 1
fi

echo "✓ storage.rules: no cross-service Firestore reads"
exit 0
