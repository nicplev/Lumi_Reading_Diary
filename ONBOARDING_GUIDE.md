# Lumi Onboarding & Parent Linking Guide (Beta)

## Overview
This guide describes the implemented onboarding and parent-linking behavior in the current beta codebase.

Primary implementation files:
- `lib/screens/onboarding/school_registration_wizard.dart`
- `lib/services/onboarding_service.dart`
- `lib/screens/admin/parent_linking_management_screen.dart`
- `lib/services/parent_linking_service.dart`
- `lib/services/parent_link_export_service.dart`
- `firestore.rules`

## School Onboarding Flow
### Entry points
- Demo request: `/onboarding/demo-request`
- Registration wizard: `/onboarding/school-registration?onboardingId=...`

### Wizard steps
1. **School Info**
   - Captures school profile details.
2. **Admin Account**
   - Captures admin identity + credentials.
3. **Reading Levels**
   - User selects schema (`aToZ`, `pmBenchmark`, `lexile`, `custom`).
   - Custom schema requires comma-separated levels.
4. **Complete**
   - Setup confirmation and login CTA.

### Persisted behavior
- Step 3 schema is persisted to school settings.
- `createSchoolAndAdmin(...)` writes school + admin and updates onboarding status.
- `applyReadingLevelConfiguration(...)` writes selected schema/custom levels.
- `completeOnboarding(...)` sets onboarding to `active` and `currentStep=completed`.

### Onboarding status model
- `demo`
- `interested`
- `registered`
- `setupInProgress`
- `active`
- `suspended`

## Parent Linking Flow
### Admin code generation
Screen: `/admin/parent-linking`

- Individual generation per student.
- Bulk generation (`Generate All Missing Codes`).
- Lifecycle default: one active code per student.
- New code generation revokes prior active code for that student.

### Link code lifecycle
- `active` -> `used`
- `active` -> `revoked`
- `active` -> `expired`

### Parent registration
Screen: `/auth/parent-register`

1. Parent submits 8-char student code.
2. Code is verified against active/non-expired records.
3. Parent account is created or resumed.
4. Parent is linked to student atomically.
5. Code is marked `used`.

### Deterministic verification behavior
`ParentLinkingService.verifyCode(...)`:
- Queries matching code records.
- Prioritizes active + non-expired records.
- Handles legacy duplicate records with deterministic priority.

## Admin CSV Export Workflow
Export implementation: `ParentLinkExportService`

CSV columns:
- `Student Name`
- `Student ID`
- `Class`
- `Link Code`
- `Code Status`
- `Created At`
- `Expires At`
- `Linked Parent Count`

Platform behavior:
- Mobile (iOS/Android): temp file + system share sheet
- Desktop/Web: file download/save

## Revoke / Unlink Operations
On admin parent-linking screen:
- **Revoke code**
  - Confirmation dialog
  - Optional reason capture
- **Unlink parent**
  - Select parent ID
  - Optional reason capture

Debug diagnostics UI is debug-gated and not visible in beta builds.

## Security Contracts
Rules file: `firestore.rules`

Implemented hardening includes:
- Restricted self-create behavior for `schools/{schoolId}/users` and `parents`.
- Controlled school counter increments (role + single-field increment checks).
- Bounded unauthenticated verification queries for:
  - `schoolCodes` (`limit(1)`)
  - `studentLinkCodes` (bounded small-limit verification query)
- Tightened access for `userSchoolIndex` (self-owned index rows only).

Rules tests:
- `functions/test/firestore.rules.test.js`
- Run with: `cd functions && npm run test:rules`

## QA Coverage Added
- `test/services/onboarding_service_test.dart`
- `test/services/parent_linking_service_test.dart`
- `test/services/parent_link_export_service_test.dart`
- `test/screens/onboarding/school_registration_wizard_test.dart`

## Operations References
- Admin runbook: `ADMIN_PARENT_LINKING_RUNBOOK.md`
- Migration order/rollback: `ONBOARDING_LINKING_MIGRATION_PLAN.md`
- Backfill scripts:
  - `scripts/backfill_parent_link_code_metadata.dart`
  - `scripts/backfill_onboarding_fields.dart`
