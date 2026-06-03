#!/usr/bin/env bash
# Publish, read, or clear the in-app status banner served by the Cloudflare
# status-worker. See docs/status-messages.md for the runbook.
#
# Quick reference:
#   ./scripts/status-message.sh warn "Lumi is having trouble"
#   ./scripts/status-message.sh info "Scheduled maintenance Sunday 02:00 UTC"
#   ./scripts/status-message.sh critical "Logging is temporarily unavailable" --no-dismiss
#   ./scripts/status-message.sh show
#   ./scripts/status-message.sh clear
#   ./scripts/status-message.sh token-set     # one-time, stash bearer in macOS keychain
#
# Auth token resolution (first hit wins):
#   1. $LUMI_STATUS_ADMIN_TOKEN env var
#   2. macOS keychain entry  service=lumi-status-admin-token, account=$USER

set -euo pipefail

WORKER_URL="${LUMI_STATUS_WORKER_URL:-https://lumistatus.aged-morning-985b.workers.dev/status}"
KEYCHAIN_SERVICE="lumi-status-admin-token"

usage() {
  cat >&2 <<EOF
Usage: $0 <command> [args]

Commands:
  warn     <message> [opts]    publish a warn-severity message (yellow)
  info     <message> [opts]    publish an info-severity message (blue)
  critical <message> [opts]    publish a critical-severity message (red)
  post <severity> <message> [opts]
                              same as the shortcuts but with explicit severity

  show                        fetch and print the current message
  clear                       delete the current message

  token-set                   prompt for bearer token, stash in macOS keychain
  token-show                  print the resolved token (for debugging)

Options for post/warn/info/critical:
  --id <slug>                 stable id (default: today's date + severity)
  --version <n>               explicit version (default: auto-increment from
                              the currently-published version)
  --no-dismiss                make the banner non-dismissible (use sparingly,
                              auto-true for "critical" if omitted)

Environment:
  LUMI_STATUS_WORKER_URL     override worker URL (default points at prod)
  LUMI_STATUS_ADMIN_TOKEN    bearer token (overrides keychain)
EOF
  exit "${1:-1}"
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command '$1' not found" >&2
    exit 1
  fi
}

resolve_token() {
  if [[ -n "${LUMI_STATUS_ADMIN_TOKEN:-}" ]]; then
    echo "${LUMI_STATUS_ADMIN_TOKEN}"
    return
  fi
  if command -v security >/dev/null 2>&1; then
    if token=$(security find-generic-password \
        -a "${USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null); then
      echo "${token}"
      return
    fi
  fi
  cat >&2 <<EOF
error: no bearer token. Either:
  1. export LUMI_STATUS_ADMIN_TOKEN=<token>, or
  2. run: $0 token-set
EOF
  exit 1
}

cmd_token_set() {
  require security
  read -rsp 'Paste the ADMIN_TOKEN (input hidden): ' token
  echo
  if [[ -z "${token}" ]]; then
    echo "error: empty token, nothing stored" >&2
    exit 1
  fi
  # Update if exists, else add. -U makes add idempotent.
  security add-generic-password -U \
    -a "${USER}" -s "${KEYCHAIN_SERVICE}" -w "${token}"
  echo "stored in macOS keychain (service=${KEYCHAIN_SERVICE} account=${USER})"
}

cmd_token_show() {
  resolve_token
}

cmd_show() {
  require jq
  curl -sS "${WORKER_URL}" | jq .
}

cmd_clear() {
  require jq
  local token; token=$(resolve_token)
  curl -sS -X DELETE "${WORKER_URL}" \
    -H "Authorization: Bearer ${token}" | jq .
}

# build_and_post <severity> <message> [opts...]
cmd_post() {
  require jq
  local severity="$1"
  local message="$2"
  shift 2

  case "${severity}" in
    info|warn|critical) ;;
    *)
      echo "error: severity must be info, warn, or critical (got: ${severity})" >&2
      exit 1
      ;;
  esac

  if [[ -z "${message}" ]]; then
    echo "error: message must be non-empty" >&2
    exit 1
  fi

  local id=""
  local version=""
  # Default: critical is non-dismissible, others are dismissible.
  local dismissible
  if [[ "${severity}" == "critical" ]]; then
    dismissible="false"
  else
    dismissible="true"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      --version) version="$2"; shift 2 ;;
      --no-dismiss) dismissible="false"; shift ;;
      --dismiss) dismissible="true"; shift ;;
      *) echo "error: unknown option: $1" >&2; usage 1 ;;
    esac
  done

  if [[ -z "${id}" ]]; then
    id="$(date -u +%Y-%m-%d)-${severity}"
  fi

  if [[ -z "${version}" ]]; then
    # Auto-increment from the currently-published version. New id starts at 1.
    local current_json
    current_json=$(curl -sS "${WORKER_URL}" || echo '{}')
    local current_id current_version
    current_id=$(echo "${current_json}" | jq -r '.id // ""')
    current_version=$(echo "${current_json}" | jq -r '.version // 0')
    if [[ "${current_id}" == "${id}" ]]; then
      version=$((current_version + 1))
    else
      version=1
    fi
  fi

  local token; token=$(resolve_token)

  local payload
  payload=$(jq -nc \
    --argjson version "${version}" \
    --arg id "${id}" \
    --arg message "${message}" \
    --arg severity "${severity}" \
    --argjson dismissible "${dismissible}" \
    '{version: $version, id: $id, message: $message, severity: $severity, dismissible: $dismissible}')

  echo "→ POST ${WORKER_URL}" >&2
  echo "  ${payload}" >&2
  curl -sS -X POST "${WORKER_URL}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" | jq .
}

if [[ $# -lt 1 ]]; then
  usage 1
fi

case "$1" in
  -h|--help|help) usage 0 ;;
  show) cmd_show ;;
  clear) shift; cmd_clear "$@" ;;
  token-set) cmd_token_set ;;
  token-show) cmd_token_show ;;
  post)
    shift
    if [[ $# -lt 2 ]]; then usage 1; fi
    cmd_post "$@"
    ;;
  info|warn|critical)
    severity="$1"; shift
    if [[ $# -lt 1 ]]; then usage 1; fi
    message="$1"; shift
    cmd_post "${severity}" "${message}" "$@"
    ;;
  *)
    echo "error: unknown command: $1" >&2
    usage 1
    ;;
esac
