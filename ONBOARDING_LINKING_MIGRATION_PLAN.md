# Onboarding & Linking Migration Plan

## Goal
Bring existing production data into alignment with beta onboarding/linking contracts without downtime.

## One-Time Migration Order
1. **Deploy updated Firestore rules**
   - File: `firestore.rules`
   - Validate with: `cd functions && npm run test:rules`

2. **Backfill link code metadata and lifecycle fields**
   - Command:
     - `dart run scripts/backfill_parent_link_code_metadata.dart`
   - Ensures:
     - `expiresAt` populated from legacy `expiryDate`
     - `metadata.studentFullName`, `metadata.studentId`, class metadata populated

3. **Backfill onboarding lifecycle fields**
   - Command:
     - `dart run scripts/backfill_onboarding_fields.dart`
   - Ensures:
     - `completedSteps` reflects `currentStep/status`
     - `registrationCompletedAt` present for active records

4. **Post-migration validation**
   - Re-run rules suite.
   - Run Flutter tests:
     - `flutter test`
   - Manual checks:
     - school registration with custom reading schema
     - bulk code generation + CSV export
     - parent code verify + link
     - revoke + unlink actions

## Rollback Posture
1. **Rules rollback**
   - Re-deploy previous known-good `firestore.rules` from VCS tag/commit.

2. **Data rollback**
   - Backfills are additive/non-destructive (field fills and lifecycle normalization).
   - If rollback is required:
     - Keep added fields in place.
     - Revert app/rules behavior to previous version.
   - Do not delete newly populated metadata fields unless a separate incident decision requires it.

3. **Operational fallback**
   - Pause bulk generation/export actions.
   - Use existing active codes while incident triage completes.
