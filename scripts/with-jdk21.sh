#!/usr/bin/env bash
# Runs a command with a JDK 21+ on PATH, which firebase-tools requires for the
# emulators.
#
# Why this exists: the npm scripts used to inline
#   JAVA_HOME="${JAVA_HOME:-/opt/.../openjdk@21/...}" PATH="$JAVA_HOME/bin:$PATH" firebase ...
# In a single assignment list the shell expands $JAVA_HOME to its OLD value, so
# PATH never actually picked up the pinned JDK and firebase fell back to system
# java. On a machine whose default java is < 21 every emulator suite failed with
# "firebase-tools no longer supports Java version before 21" — so they tended to
# get skipped locally and only ran in CI (which has no system java to shadow it).
# That is how a storage.rules regression stayed green for five days.
#
# Respects an existing JAVA_HOME if it already points at 21+.
set -euo pipefail

FALLBACK_JDK="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"

java_major() {
  local home="$1"
  [ -x "$home/bin/java" ] || return 1
  "$home/bin/java" -version 2>&1 \
    | awk -F'"' '/version/ {split($2, v, "."); print (v[1] == 1 ? v[2] : v[1]); exit}'
}

pick_jdk() {
  if [ -n "${JAVA_HOME:-}" ]; then
    local major
    major="$(java_major "$JAVA_HOME" || true)"
    if [ -n "$major" ] && [ "$major" -ge 21 ]; then
      echo "$JAVA_HOME"
      return 0
    fi
  fi
  if [ -d "$FALLBACK_JDK" ]; then
    echo "$FALLBACK_JDK"
    return 0
  fi
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    /usr/libexec/java_home -v 21+ 2>/dev/null && return 0
  fi
  return 1
}

if ! JDK="$(pick_jdk)"; then
  cat >&2 <<'EOF'
error: no JDK 21+ found — the Firebase emulators need one.
       macOS: brew install openjdk@21
       Or set JAVA_HOME to a 21+ install before running.
EOF
  exit 1
fi

export JAVA_HOME="$JDK"
export PATH="$JAVA_HOME/bin:$PATH"
exec "$@"
