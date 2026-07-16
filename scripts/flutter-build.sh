#!/usr/bin/env bash
# Thin wrapper around `flutter build` that always picks up the
# repo-wide dart-defines from .dart_define.json.
#
# Usage:
#   ./scripts/flutter-build.sh ios            # release ios
#   ./scripts/flutter-build.sh ipa             # ipa for TestFlight
#   ./scripts/flutter-build.sh apk             # release apk
#   ./scripts/flutter-build.sh appbundle       # play store aab
#   ./scripts/flutter-build.sh web             # web release
#
# Pass extra flags after the target:
#   ./scripts/flutter-build.sh ios --release --no-codesign

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES_FILE="${REPO_ROOT}/.dart_define.json"

if [[ ! -f "${DEFINES_FILE}" ]]; then
  echo "error: ${DEFINES_FILE} not found" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <target> [extra flutter flags]" >&2
  echo "  target: ios | ipa | apk | appbundle | web | macos | linux | windows" >&2
  exit 1
fi

target="$1"
shift

# Store-bound mobile artifacts must never silently omit App Check. Debug runs
# can still choose their provider/token explicitly with `flutter run`, while
# every release build produced by this supported wrapper is attested from its
# first Firebase request.
case "${target}" in
  ios|ipa|apk|appbundle)
    if ! grep -Eq '"LUMI_APP_CHECK_ENABLED"[[:space:]]*:[[:space:]]*true' "${DEFINES_FILE}"; then
      echo "error: mobile release builds require LUMI_APP_CHECK_ENABLED=true in ${DEFINES_FILE}" >&2
      exit 1
    fi
    ;;
esac

exec flutter build "${target}" \
  --dart-define-from-file="${DEFINES_FILE}" \
  "$@"
