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

step "Flutter login, routing, Terms and recovery UI"
flutter test \
  test/core/routing/app_router_test.dart \
  test/screens/auth/login_screen_policy_test.dart \
  test/data/providers/user_provider_auth_resolution_test.dart \
  test/screens/auth/terms_account_load_error_test.dart \
  test/screens/parent/comprehension_recording_demo_preview_test.dart \
  test/models/comprehension_recording_settings_test.dart \
  test/models/user_model_test.dart \
  test/assets_bundled_test.dart

step "Flutter changed demo boundary analysis"
flutter analyze \
  lib/core/routing/app_router.dart \
  lib/screens/auth/login_screen.dart \
  lib/data/providers/user_provider.dart \
  lib/screens/auth/terms_acceptance_screen.dart \
  lib/data/models/comprehension_recording_settings.dart \
  lib/screens/parent/widgets/comprehension_recording_step.dart \
  lib/screens/parent/log_reading_screen.dart \
  lib/screens/parent/reading_success_screen.dart

step "School portal session/read-only security"
pnpm --filter lumi-school-admin test:security
pnpm --filter lumi-school-admin exec tsc --noEmit

step "Super-admin demo orchestration typecheck"
pnpm --filter lumi-admin-scaffold exec tsc --noEmit

step "Patch integrity"
git diff --check

printf '\nDEMO REGRESSION GATE PASSED\n'
