#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() {
  printf '\n==> %s\n' "$1"
}

step "Deterministic demo plan"
pnpm test:demo-plan

step "Redacted live preflight core"
pnpm test:demo-preflight

step "Live demo feature controls"
pnpm test:demo-controls

step "Fenced Auth/Firestore/Storage reseed"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}" \
  PATH="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}/bin:$PATH" \
  "$ROOT/functions/node_modules/.bin/firebase" emulators:exec \
    --config firebase.deletion.json \
    --only firestore,auth,storage \
    --project demo-lumi-reseed \
    "pnpm --dir '$ROOT' exec tsx --test packages/server-ops/test/demoSchool.reseed.integration.test.ts"

step "Cloud Functions demo read-only guard"
(cd functions && npm run build && node --test test/read_only_guard.test.js)

step "Firestore tenant and demo-role Rules"
(cd functions && npm run test:rules)

step "Storage isolation and demo upload Rules"
(cd functions && npm run test:rules:storage)

# Was a hardcoded list of 8 test files covering the login/routing/Terms
# boundary. That meant a change to any other Flutter screen, widget or
# service ran no tests at all — the workflow's path filter didn't even
# trigger for them. Eight tests had rotted behind intentional UI changes
# without anyone noticing. Run the whole suite instead: it takes ~15s.
step "Flutter test suite"
flutter test

# Likewise was 8 named files. --no-fatal-infos keeps the pre-existing
# deprecation notices (Radio.groupValue, dart:html) non-blocking while still
# failing the gate on any real error or warning.
step "Flutter analysis"
flutter analyze --no-fatal-infos lib/

step "School portal session/read-only security"
pnpm --filter lumi-school-admin test:security
pnpm --filter lumi-school-admin exec tsc --noEmit

step "Super-admin demo orchestration typecheck"
pnpm --filter lumi-admin-scaffold exec tsc --noEmit

step "Patch integrity"
git diff --check

printf '\nDEMO REGRESSION GATE PASSED\n'
