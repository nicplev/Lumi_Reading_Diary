#!/usr/bin/env bash
# PostToolUse hook: run the function-estate health audit after any command
# that could silently break function invocation.
#
# Exists because a missing per-service `roles/run.invoker` is invisible —
# Eventarc retries, gives up, and the only trace is a 403 in that one
# service's logs. maintainClassDailyReading was broken that way for three
# days (982 dropped invocations). The two triggers below are exactly the
# actions that caused it: a deploy that creates new functions, and an IAM
# change that can drop an existing binding.
#
# Runs async (never blocks the session) and de-bounced, so a burst of IAM
# commands produces one audit, not five. Exits 2 only when the audit finds
# something ACTIONABLE, which wakes the model with the details.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AUDIT="$ROOT/scripts/audit-function-health.sh"
STATE_DIR="${TMPDIR:-/tmp}/claude-lumi-fnaudit"
STAMP="$STATE_DIR/last-run"
LOG="$STATE_DIR/last-report.txt"
DEBOUNCE_SECONDS=600

CMD=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Trigger 1: a deploy that can CREATE functions (new services start with no
# invoker binding). Trigger 2: any IAM mutation (can REMOVE one).
DEPLOY_RE='firebase[[:space:]]+deploy.*functions'
IAM_RE='(add|remove|set)-iam-policy-binding|set-iam-policy|iam[[:space:]]+roles[[:space:]]+(create|update|delete)'
if ! echo "$CMD" | grep -qE "$DEPLOY_RE" && ! echo "$CMD" | grep -qE "$IAM_RE"; then
  exit 0
fi

# Read-only gcloud calls (get-iam-policy, list) must not trigger it.
echo "$CMD" | grep -qE 'get-iam-policy|iam[[:space:]]+roles[[:space:]]+describe' \
  && ! echo "$CMD" | grep -qE "$DEPLOY_RE|(add|remove)-iam-policy-binding" && exit 0

[ -x "$AUDIT" ] || exit 0

mkdir -p "$STATE_DIR"
if [ -f "$STAMP" ]; then
  LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  [ $((NOW - LAST)) -lt "$DEBOUNCE_SECONDS" ] && exit 0
fi
date +%s > "$STAMP"

"$AUDIT" > "$LOG" 2>&1

# Only these three are actionable RIGHT NOW. Section [1] lists invoker-403s
# over a 30-day window, so it keeps reporting an incident for weeks after
# it is fixed — waking the model on that would train everyone to ignore it.
ACTIONABLE=$(grep -E 'MISSING run\.invoker|FAILED:|ATTENTION ' "$LOG" || true)
if [ -n "$ACTIONABLE" ]; then
  echo "Function-estate audit found issues after an infra change:"
  echo "$ACTIONABLE"
  echo "Full report: $LOG"
  exit 2
fi
exit 0
