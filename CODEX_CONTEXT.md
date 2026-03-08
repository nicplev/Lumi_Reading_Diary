# CODEX Context: Lumi Reading Tracker

Last updated: 2026-03-08

## Purpose
This file is a fast orientation guide for Codex agents working in this repo. It summarizes the app structure, runtime flow, data model, backend, and practical editing guidance.

## What This App Is
- Flutter + Firebase reading diary app for three roles:
- `parent`: logs student reading and views progress.
- `teacher`: manages classes, allocations, and reporting.
- `schoolAdmin`: manages school users/classes and admin tools.

## Tech Stack
- Frontend: Flutter (Dart, Material 3)
- State: Riverpod + direct singleton services
- Navigation: `go_router`
- Backend: Firebase Auth + Firestore + Storage + Messaging + Analytics + Crashlytics
- Local/offline: Hive + connectivity tracking
- Cloud backend jobs: Firebase Cloud Functions (TypeScript)

## High-Level Repository Map
- `lib/main.dart`: app bootstrap (Firebase, crash reporting, analytics, Riverpod)
- `lib/core/routing/app_router.dart`: routes + auth/role guards
- `lib/screens/`: UI by domain (`auth`, `parent`, `teacher`, `admin`, `onboarding`, `marketing`)
- `lib/data/models/`: Firestore/domain models
- `lib/services/`: business/service layer (Firebase, offline, notifications, onboarding, linking, reports)
- `lib/core/services/`: shared app-level helpers (e.g., navigation temp state, email-school index)
- `functions/src/index.ts`: Cloud Functions triggers/scheduled jobs
- `firestore.rules`: Firestore security model
- `firestore.indexes.json`: composite indexes
- `test/`: models, services, widgets, routing tests

## Runtime Startup Flow
1. `main()` in `lib/main.dart` initializes:
- Flutter bindings
- orientation lock (mobile only)
- Hive
- Firebase
- `CrashReportingService`
- `FirebaseService`
- `AnalyticsService`
2. App mounts `ProviderScope` and uses `GoRouter` from `routerProvider`.
3. Initial route is `/splash`; splash checks auth + user profile and routes by role.

## Routing and Access Control
Defined in `lib/core/routing/app_router.dart`.

Key behaviors:
- Public routes: `/splash`, `/auth/*`, `/landing`, `/onboarding/*`
- Non-public routes require authenticated Firebase user + resolvable `UserModel`
- Role-locked sections:
- `/parent/*` for parents only
- `/teacher/*` for teachers only
- `/admin/*` for school admins only
- Parent web access is blocked and redirected to `/auth/web-not-available`
- Many routes expect `state.extra` data objects; one path (`/parent/log-reading`) uses `NavigationStateService` temp storage.

## Role-Specific Screen Hubs
- Parent hub: `lib/screens/parent/parent_home_screen.dart`
- Teacher hub: `lib/screens/teacher/teacher_home_screen.dart`
- Admin hub: `lib/screens/admin/admin_home_screen.dart`

## Data Architecture (Important)
Canonical structure is nested by school:

`schools/{schoolId}`
- `users/{userId}` (teacher/admin)
- `parents/{parentId}`
- `students/{studentId}`
- `classes/{classId}`
- `readingLogs/{logId}`
- `allocations/{allocationId}`

Top-level collections are still present for specific workflows/migrations:
- `schoolOnboarding`
- `studentLinkCodes`
- `schoolCodes`
- `notifications`
- `userSchoolIndex`
- legacy/testing references to top-level `users`, `students`, `classes`, `readingLogs` still exist in some code/docs/scripts.

## Core Domain Models
Located under `lib/data/models/`.

Most critical:
- `UserModel` + `UserRole` (`parent`, `teacher`, `schoolAdmin`)
- `StudentModel` (+ `StudentStats`, level history)
- `ClassModel` (supports both legacy `teacherId` and new `teacherIds`)
- `ReadingLogModel` (`ReadingFeeling`, parent/teacher comments)
- `AllocationModel` (type + cadence, target minutes/date window)
- `SchoolModel` (reading schema config, quiet hours, counts)
- Supporting: `SchoolCodeModel`, `StudentLinkCodeModel`, `ReadingGoalModel`, `BookModel`, `AchievementModel`, `ReadingGroupModel`, `SchoolOnboardingModel`

## Service Layer Map
- `firebase_service.dart`: wrapper for Auth/Firestore/Storage/Messaging init + basic data calls
- `offline_service.dart`: Hive boxes + pending sync queue
- `notification_service.dart`: local + FCM notifications, scheduled daily reminders
- `analytics_service.dart`: typed analytics events
- `crash_reporting_service.dart`: Crashlytics setup + error capture helpers
- `parent_linking_service.dart`: student-parent link code creation/verification/linking
- `school_code_service.dart`: teacher school-code validation/management
- `onboarding_service.dart`: demo request + school/admin onboarding
- `csv_import_service.dart`: class/student bulk import
- `pdf_report_service.dart`: student/class PDF exports
- `book_recommendation_service.dart`: Firestore book recommendation/search queries
- `core/services/user_school_index_service.dart`: hashed email lookup index for faster login resolution

## Auth and Registration Reality
- Login (`auth/login`) performs optimized school lookup via `userSchoolIndex`, with fallback scans for backward compatibility.
- Registration (`auth/register`) writes teacher/admin to `schools/{id}/users`, parent to `schools/{id}/parents`.
- Parent registration has dedicated code flow (`auth/parent-register`) using `studentLinkCodes` + transactional linking.

## Cloud Functions
File: `functions/src/index.ts`

Deployed functions include:
- `aggregateStudentStats`: recalculates student stats from reading logs
- `sendReadingReminders`: scheduled daily parent reminders
- `detectAchievements`: milestone detection on student updates
- `validateReadingLog`: validates new reading logs server-side
- `cleanupExpiredLinkCodes`: scheduled expiry job
- `updateClassStats`: class stats updater

Note:
- `updateClassStats` currently queries reading logs with `where("studentId", "in", studentData.classId)` which looks incorrect (class ID used as student ID list). Verify before relying on this function.

## Security and Indexes
- Firestore rules in `firestore.rules` enforce school-scoped access by role.
- Rules include mixed legacy + current behavior to support migrations and onboarding flows.
- Composite indexes in `firestore.indexes.json` rely heavily on collection-group indexes for nested subcollections.

## UI System Notes
- Primary design system: Lumi components under `lib/core/widgets/lumi/`
- Additional minimal design widgets under `lib/core/widgets/minimal/`
- Teacher/admin-specific typography/constants in `lib/core/theme/teacher_constants.dart`
- Shared app theme/colors in `lib/core/theme/`

## Tests Snapshot
Tests exist for:
- models: `test/models/*`
- widgets: `test/widgets/*`
- services: `test/services/*`
- routing: `test/core/routing/app_router_test.dart`

Coverage focus is partial and practical, not exhaustive.

## Existing Docs Worth Checking First
- `README.md`
- `APP_FLOW.md`
- `ONBOARDING_GUIDE.md`
- `FIREBASE_SETUP.md`
- `SCHOOL_CODE_SETUP.md` / `SCHOOL_CODE_QUICKSTART.md`
- `FIRESTORE_OPTIMIZATION_DEPLOYMENT.md`

## Common Change Playbook
When editing:
1. Confirm whether code path is nested school structure or legacy top-level path.
2. Check router guard + `state.extra` expectations for any new screen/flow.
3. Keep role constraints aligned in both router logic and Firestore rules.
4. If adding Firestore query patterns, verify index requirements.
5. If editing stats logic, reconcile client-side updates with Cloud Function aggregators.
6. Add/update tests in the closest existing test area.

## Known Pitfalls
- Mixed legacy/new Firestore paths in different files.
- Some flows depend on passing full model objects in router `extra`.
- `NavigationStateService` temp-data workaround is easy to break if route transitions change.
- Offline service has partial model reconstruction gaps (`getLocalStudent`/`getLocalAllocations` placeholders).
- Parent web is intentionally blocked.

## Useful Commands
- `flutter pub get`
- `flutter run`
- `flutter test`
- `dart run scripts/backfill_user_school_index.dart`
- `dart run scripts/migrate_link_code_fields.dart`
- `dart run scripts/setup_test_school_code.dart`
- Functions: run from `functions/` (`npm run build`, `npm run serve`, `npm run deploy`)

