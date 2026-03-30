# ARCHITECTURE.md — Lumi Reading Diary

> **Last updated:** 2026-03-19
> **Project:** Lumi Reading Diary
> **Repository:** lumi_reading_tracker
> **Primary contact:** nicplev
> **Firebase Project:** lumi-kakakids

---

## 1. PROJECT STRUCTURE

```
lumi_reading_tracker/
│
├── lib/                                    # ── Flutter Application ──
│   ├── main.dart                           # Entry point, Firebase init, ProviderScope
│   ├── firebase_options.dart               # Auto-generated Firebase config
│   │
│   ├── core/                               # ── Shared Infrastructure ──
│   │   ├── routing/
│   │   │   └── app_router.dart             # GoRouter: auth guards, role-based routes, deep linking
│   │   ├── theme/
│   │   │   ├── app_theme.dart              # Material ThemeData (light + dark)
│   │   │   ├── app_colors.dart             # Colour palette
│   │   │   ├── lumi_text_styles.dart       # Typography scale
│   │   │   ├── lumi_spacing.dart           # 8pt spacing system
│   │   │   ├── lumi_borders.dart           # Border radii, shadows
│   │   │   ├── teacher_constants.dart      # Teacher UI constants
│   │   │   └── minimal_theme.dart          # Archived legacy theme
│   │   ├── widgets/
│   │   │   ├── common_widgets.dart         # Shared utility widgets
│   │   │   ├── lumi_mascot.dart            # Animated Lumi character
│   │   │   ├── offline_indicator.dart      # Connectivity banner
│   │   │   ├── lumi/                       # ── Lumi Design System (30+ components) ──
│   │   │   │   ├── lumi_buttons.dart
│   │   │   │   ├── lumi_card.dart
│   │   │   │   ├── lumi_input.dart
│   │   │   │   ├── lumi_book_card.dart
│   │   │   │   ├── lumi_skeleton.dart
│   │   │   │   ├── progress_ring.dart
│   │   │   │   ├── week_progress_bar.dart
│   │   │   │   ├── stats_card.dart
│   │   │   │   ├── persistent_cached_image.dart      # Platform-conditional image cache
│   │   │   │   ├── persistent_cached_image_io.dart    # Mobile implementation
│   │   │   │   ├── persistent_cached_image_stub.dart  # Web stub
│   │   │   │   ├── reading_level_picker_sheet.dart
│   │   │   │   ├── reading_level_history_sheet.dart
│   │   │   │   ├── teacher_reading_level_pill.dart
│   │   │   │   ├── teacher_book_assignment_card.dart
│   │   │   │   ├── teacher_student_list_item.dart
│   │   │   │   ├── teacher_class_card.dart
│   │   │   │   ├── teacher_stat_card.dart
│   │   │   │   ├── teacher_filter_chip.dart
│   │   │   │   ├── teacher_alert_banner.dart
│   │   │   │   ├── teacher_settings_item.dart
│   │   │   │   ├── teacher_settings_section.dart
│   │   │   │   └── ...
│   │   │   ├── minimal/                    # Archived minimal-theme widgets
│   │   │   └── glass/                      # Archived glass-theme widgets
│   │   ├── services/
│   │   │   └── navigation_state_service.dart
│   │   ├── utils/
│   │   ├── constants/
│   │   └── exceptions/
│   │
│   ├── data/                               # ── Data Layer ──
│   │   ├── models/                         # Firestore document models (16 models)
│   │   │   ├── user_model.dart             # UserModel (parent / teacher / schoolAdmin)
│   │   │   ├── student_model.dart          # StudentModel + reading level history + stats
│   │   │   ├── book_model.dart             # BookModel + reading history
│   │   │   ├── allocation_model.dart       # AllocationModel (book assignments)
│   │   │   ├── reading_log_model.dart      # ReadingLogModel (sessions)
│   │   │   ├── school_model.dart           # SchoolModel (config, settings)
│   │   │   ├── class_model.dart            # ClassModel
│   │   │   ├── achievement_model.dart      # Badges & milestones
│   │   │   ├── reading_goal_model.dart     # Per-student goals
│   │   │   ├── reading_group_model.dart    # Student grouping
│   │   │   ├── reading_level_event.dart    # Level change audit log
│   │   │   ├── reading_level_option.dart   # Level schema definition
│   │   │   ├── school_code_model.dart      # School access codes
│   │   │   ├── school_onboarding_model.dart# Registration state
│   │   │   └── student_link_code_model.dart# Parent linking codes
│   │   ├── providers/
│   │   │   ├── user_provider.dart          # FutureProvider<UserModel?>
│   │   │   ├── book_lookup_provider.dart   # ISBN lookup provider
│   │   │   └── teacher_stub_data.dart      # Dev test data
│   │   └── repositories/
│   │       └── user_repository.dart        # User CRUD operations
│   │
│   ├── services/                           # ── Business Logic (27 services) ──
│   │   ├── firebase_service.dart           # Firebase singleton, auth, Firestore, storage
│   │   ├── notification_service.dart       # FCM push + local + scheduled reminders
│   │   ├── crash_reporting_service.dart    # Crashlytics error zones
│   │   ├── analytics_service.dart          # Firebase Analytics event tracking
│   │   ├── offline_service.dart            # Hive caching + sync queue + connectivity
│   │   ├── book_lookup_service.dart        # ISBN → metadata (multi-source fallback)
│   │   ├── book_cover_cache_service.dart   # Cover image persistence
│   │   ├── persistent_image_cache_service.dart     # Platform-conditional cache
│   │   ├── persistent_image_cache_service_io.dart  # Mobile file-based cache
│   │   ├── persistent_image_cache_service_stub.dart# Web stub
│   │   ├── llml_book_database.dart         # Local LLLL product catalog (JSON)
│   │   ├── book_recommendation_service.dart# Personalised suggestions
│   │   ├── book_metadata_resolver.dart     # Multi-source data consolidation
│   │   ├── isbn_assignment_service.dart    # ISBN → allocation workflows
│   │   ├── allocation_crud_service.dart    # Allocation management
│   │   ├── school_library_service.dart     # School library management
│   │   ├── school_library_assignment_service.dart
│   │   ├── reading_level_service.dart      # Level schema management
│   │   ├── student_reading_level_service.dart # Per-student level assignments
│   │   ├── csv_import_service.dart         # Bulk CSV import
│   │   ├── pdf_report_service.dart         # PDF report generation
│   │   ├── onboarding_service.dart         # School registration workflow
│   │   ├── parent_linking_service.dart     # Parent-student link codes
│   │   ├── parent_link_export_service.dart # Link code export
│   │   └── school_code_service.dart        # School access codes
│   │
│   └── screens/                            # ── UI Screens (42 screens) ──
│       ├── auth/                           # Login, Register, Forgot Password (6)
│       ├── parent/                         # Parent dashboard & features (11)
│       ├── teacher/                        # Teacher dashboard & features (12)
│       ├── admin/                          # Admin portal (8)
│       ├── onboarding/                     # School registration wizards (3)
│       ├── marketing/                      # Landing page (1)
│       ├── shared/                         # Cross-role screens
│       └── _archived_minimal_theme/        # Deprecated UI (kept for reference)
│
├── functions/                              # ── Firebase Cloud Functions (TypeScript) ──
│   ├── src/
│   │   └── index.ts                        # aggregateStudentStats, scheduleReadingReminders
│   ├── test/
│   │   └── firestore.rules.test.js         # Firestore rules unit tests
│   ├── package.json
│   ├── tsconfig.json
│   └── .eslintrc.js
│
├── test/                                   # ── Tests (23+ files) ──
│   ├── services/                           # Service unit tests
│   ├── models/                             # Model serialisation tests
│   ├── screens/                            # Screen widget tests
│   ├── widgets/                            # Widget unit tests
│   ├── core/                               # Routing tests
│   └── helpers/                            # Mock factories & test utilities
│
├── assets/                                 # ── Static Assets ──
│   ├── images/
│   ├── icons/
│   ├── animations/                         # Lottie JSON animations
│   ├── blobs/                              # Mascot mood SVGs/PNGs
│   └── data/
│       └── llll_books_db.json              # Local LLLL book catalog
│
├── android/                                # Android native project
├── ios/                                    # iOS native project
├── web/                                    # Web entry point
│
├── firebase.json                           # Firebase deployment config
├── firestore.rules                         # Firestore security rules
├── firestore.indexes.json                  # Composite indexes
├── .firebaserc                             # Firebase project alias (lumi-kakakids)
├── pubspec.yaml                            # Flutter dependencies
├── analysis_options.yaml                   # Dart lint rules
└── *.md                                    # Planning & documentation files
```

---

## 2. HIGH-LEVEL SYSTEM DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────┐
│                            CLIENTS                                  │
│                                                                     │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    │
│   │  Parent   │    │ Teacher  │    │  Admin   │    │   Web    │    │
│   │ (iOS/And) │    │ (iOS/And)│    │ (iOS/And)│    │ (Browser)│    │
│   └────┬─────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘    │
│        │               │               │               │           │
│        └───────────────┴───────┬───────┴───────────────┘           │
│                                │                                    │
│              ┌─────────────────▼─────────────────┐                 │
│              │     Flutter App (Dart / GoRouter)  │                 │
│              │  Riverpod State · Hive Offline Cache│                │
│              └─────────────────┬─────────────────┘                 │
└────────────────────────────────┼────────────────────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │      Firebase Suite      │
                    │                          │
                    │  ┌────────────────────┐  │
                    │  │   Firebase Auth     │  │  Email/password authentication
                    │  │  (Email + Password) │  │  Role stored in Firestore
                    │  └────────────────────┘  │
                    │                          │
                    │  ┌────────────────────┐  │
                    │  │  Cloud Firestore   │  │  Primary database (real-time sync)
                    │  │  (Multi-tenant)    │  │  /schools/{id}/* data paths
                    │  └────────────────────┘  │
                    │                          │
                    │  ┌────────────────────┐  │
                    │  │  Firebase Storage  │  │  Profile images, file uploads
                    │  └────────────────────┘  │
                    │                          │
                    │  ┌────────────────────┐  │
                    │  │  Cloud Functions   │  │  aggregateStudentStats (Firestore trigger)
                    │  │  (TypeScript/Node) │  │  scheduleReadingReminders (scheduled)
                    │  └────────────────────┘  │
                    │                          │
                    │  ┌────────────────────┐  │
                    │  │  FCM + Analytics   │  │  Push notifications, event tracking
                    │  │  + Crashlytics     │  │  Error reporting
                    │  └────────────────────┘  │
                    │                          │
                    │  ┌────────────────────┐  │
                    │  │  Firebase Hosting  │  │  Web build (build/web → SPA)
                    │  └────────────────────┘  │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   External Book APIs     │
                    │                          │
                    │  1. Local LLLL DB (JSON) │  ← Fastest (in-memory)
                    │  2. Firestore cache      │  ← School-scoped
                    │  3. Google Books API     │  ← ISBN → metadata
                    │  4. Open Library API     │  ← Fallback + covers
                    └──────────────────────────┘
```

---

## 3. CORE COMPONENTS

### Frontend — Flutter App

| Aspect | Details |
|--------|---------|
| **Framework** | Flutter 3.x+ (Dart ≥3.0.0) |
| **Platforms** | iOS, Android, Web |
| **Navigation** | GoRouter 16.3.0 — declarative routing, auth guards, role-based redirects, deep linking |
| **State management** | Riverpod 3.0.3 (primary) — `FutureProvider`, async patterns; Provider 6.1.2 (legacy) |
| **Offline support** | Hive 2.2.3 local storage with sync queue, connectivity_plus monitoring, 5-min periodic sync |
| **UI system** | Custom "Lumi" design system (30+ components), Material Design base, Lottie animations, SVG mascot |
| **Deployment** | iOS App Store, Google Play, Firebase Hosting (web) |

### Backend Services — Firebase Cloud Functions

| Aspect | Details |
|--------|---------|
| **Runtime** | Node.js 20, TypeScript |
| **Location** | `/functions/src/index.ts` |
| **Key functions** | `aggregateStudentStats` — Firestore trigger on reading log writes; recalculates streaks, totals, averages server-side |
| | `scheduleReadingReminders` — Scheduled FCM batch send (500 msg limit, 5 schools concurrent) |
| **Admin SDK** | firebase-admin 12.0.0 — bypasses security rules for aggregation |
| **Deployment** | `firebase deploy --only functions` with ESLint + TypeScript pre-deploy checks |

### Book Lookup Microservice (In-App)

| Aspect | Details |
|--------|---------|
| **Purpose** | ISBN barcode → book metadata resolution |
| **Fallback chain** | Local LLLL DB → Firestore cache → Google Books API → Open Library API → `null` |
| **Timeout** | 5s per API call |
| **Caching** | Results cached to school-scoped Firestore collection |

---

## 4. DATA STORES

### Cloud Firestore (Primary Database)

**Type:** NoSQL document database with real-time sync
**Multi-tenancy:** All data scoped under `/schools/{schoolId}/`

| Collection | Purpose | Key Fields |
|------------|---------|------------|
| `/schools/{schoolId}` | School configuration | `name`, `levelSchema`, `termDates`, `quietHours`, `timezone`, `settings`, `subscriptionPlan` |
| `/schools/{id}/users/{userId}` | Teachers & admins | `email`, `fullName`, `role` (teacher/schoolAdmin), `classIds[]`, `fcmToken` |
| `/schools/{id}/parents/{parentId}` | Parent accounts | `email`, `fullName`, `linkedChildren[]`, `fcmToken` |
| `/schools/{id}/students/{studentId}` | Student profiles | `firstName`, `lastName`, `classId`, `currentReadingLevel`, `parentIds[]`, `stats{}`, `levelHistory[]` |
| `/schools/{id}/readingLogs/{logId}` | Reading sessions | `studentId`, `date`, `minutesRead`, `feeling`, `bookTitles[]`, `status` |
| `/schools/{id}/allocations/{allocId}` | Book assignments | `classId`, `studentIds[]`, `type` (byLevel/byTitle/freeChoice), `cadence`, `bookItems[]` |
| `/books/{bookId}` | Global book catalog | `title`, `author`, `isbn`, `coverImageUrl`, `genres[]`, `readingLevel` |
| `/studentLinkCodes/{codeId}` | Parent linking | `code` (8-char), `studentId`, `schoolId`, `status`, `expiresAt` |
| `/schoolOnboarding/{id}` | Registration workflow | `schoolName`, `contactEmail`, `status`, `currentStep`, `completedSteps[]` |

### Hive (Local Offline Cache)

**Type:** Lightweight key-value store (Dart)
**Purpose:** Offline-first support — cache data locally, queue writes for sync

| Box | Purpose |
|-----|---------|
| `reading_logs` | Cached reading sessions |
| `students` | Cached student profiles |
| `allocations` | Cached allocations |
| `pending_sync` | Queue of documents awaiting upload |
| `settings` | User preferences and app state |

### Firebase Storage

**Type:** Object/file storage
**Purpose:** Profile images, uploaded files
**Bucket:** `lumi-kakakids.firebasestorage.app`

### Local LLLL Book Database

**Type:** JSON file loaded into memory at startup
**Location:** `/assets/data/llll_books_db.json`
**Purpose:** Instant ISBN lookups for Learning Logic catalogue (no network required)

---

## 5. EXTERNAL INTEGRATIONS

| Service | Purpose | Integration Method |
|---------|---------|-------------------|
| **Firebase Auth** | Email/password authentication, account management | `firebase_auth` SDK — `signInWithEmailAndPassword`, `createUserWithEmailAndPassword`, email verification |
| **Cloud Firestore** | Real-time document database | `cloud_firestore` SDK — streams, snapshots, batch writes |
| **Firebase Storage** | File uploads (profile images) | `firebase_storage` SDK — `putFile`, `getDownloadURL` |
| **Firebase Cloud Messaging (FCM)** | Push notifications | `firebase_messaging` SDK — token management, background handlers |
| **Firebase Analytics** | User event tracking | `firebase_analytics` SDK — custom events (`log_reading`, `scan_isbn`, etc.) |
| **Firebase Crashlytics** | Error reporting & crash logs | `firebase_crashlytics` SDK — error zones, non-fatal reports |
| **Firebase Hosting** | Web app deployment | SPA config with URL rewrites → `index.html` |
| **Google Books API** | ISBN → book metadata (title, author, cover, description) | HTTP GET: `googleapis.com/books/v1/volumes?q=isbn:{isbn}` |
| **Open Library API** | Fallback book metadata + cover images | HTTP GET: `openlibrary.org/api/books?bibkeys=ISBN:{isbn}` |
| **Open Library Covers** | Deterministic cover image URLs | URL pattern: `covers.openlibrary.org/b/isbn/{isbn}-M.jpg` |

---

## 6. DEPLOYMENT & INFRASTRUCTURE

### Cloud Provider

**Firebase (Google Cloud)** — fully managed serverless backend.

| Service | Usage |
|---------|-------|
| **Firebase Auth** | Authentication |
| **Cloud Firestore** | Database |
| **Firebase Storage** | File storage |
| **Cloud Functions** | Server-side logic (Node.js 20) |
| **Firebase Hosting** | Web app (SPA) |
| **FCM** | Push notifications |
| **Firebase Analytics** | Usage tracking |
| **Firebase Crashlytics** | Error reporting |

### Firebase Project Configuration

```
Project ID:     lumi-kakakids
Auth Domain:    lumi-kakakids.firebaseapp.com
Storage Bucket: lumi-kakakids.firebasestorage.app
```

**Platform App IDs:**
- Android: `1:432054475733:android:eecbe226fd3f62ed963b5c`
- iOS: `1:432054475733:ios:3e84170b90653be9963b5c`
- Web: `1:432054475733:web:503da019d86e3de8963b5c`

### Deployment Pipeline

```
Firebase Deployment (firebase.json):
  ├── Firestore Rules    → firestore.rules
  ├── Firestore Indexes  → firestore.indexes.json
  ├── Cloud Functions     → functions/ (TypeScript → JS, ESLint + build pre-deploy)
  └── Hosting             → build/web/ (SPA rewrite to index.html)

Flutter Build:
  ├── flutter clean
  ├── flutter pub get
  ├── flutter pub run build_runner build  (code gen: Hive adapters)
  ├── flutter build ios --release         (iOS)
  ├── flutter build appbundle --release   (Android)
  └── flutter build web --release         (Web → Firebase Hosting)
```

### Monitoring

- **Firebase Crashlytics** — real-time crash reporting, non-fatal error tracking
- **Firebase Analytics** — user engagement events, screen views, custom events
- **Firebase Performance** — available via SDK (not yet integrated)

---

## 7. SECURITY CONSIDERATIONS

### Authentication

| Method | Details |
|--------|---------|
| **Auth provider** | Firebase Auth — email/password only |
| **Email verification** | Required for teachers and admins |
| **Account deletion** | Cascades to Firestore user document |
| **FCM token lifecycle** | Stored on login, cleared on logout |

### Authorisation Model

**Role-based access control (RBAC)** enforced at two levels:

1. **Client-side** — GoRouter auth guards redirect unauthorised users
2. **Server-side** — Firestore security rules enforce per-document access

| Role | Access Scope |
|------|-------------|
| `parent` | Own profile, linked children's data, reading logs, allocations for their children |
| `teacher` | Own profile, assigned classes, all students in those classes, allocations they created |
| `schoolAdmin` | All data within their school |

### Firestore Security Rules (`firestore.rules`)

```
Key rule functions:
  isSignedIn()              → request.auth != null
  isSchoolAdmin(schoolId)   → user doc role == 'schoolAdmin'
  isTeacher(schoolId)       → user doc role == 'teacher'
  isParentMember(schoolId)  → parent doc exists in school
  belongsToSchool(schoolId) → membership check

Key restrictions:
  - Parents can only read allocations for their linked children
  - Teachers see only their assigned classes and students
  - Schools cannot be deleted (soft delete via isActive flag)
  - Counter fields protected from client-side manipulation
  - Server-side aggregation via Cloud Functions (admin SDK)
```

### Data Encryption

| Layer | Method |
|-------|--------|
| **In transit** | TLS (Firebase SDK default) |
| **At rest** | Google-managed encryption (Firestore, Storage) |
| **Local storage** | Hive (unencrypted — device-level protection) |

---

## 8. DEVELOPMENT & TESTING

### Local Setup

```bash
# Prerequisites
- Flutter SDK ≥3.0.0
- Dart ≥3.0.0
- Node.js 20 (for Cloud Functions)
- Java JDK (for Firestore emulator)
- Xcode (iOS builds)
- Android Studio (Android builds)

# Setup
flutter pub get
cd functions && npm install && cd ..
flutter pub run build_runner build       # Generate Hive adapters

# Run
flutter run -d <device>                  # Debug mode
flutter run -d <device> --release        # Release mode
firebase emulators:start                 # Local Firestore emulator

# Cloud Functions (local)
cd functions
npm run build
npm run serve
```

### Testing Frameworks

| Layer | Framework | Command |
|-------|-----------|---------|
| **Flutter unit/widget tests** | `flutter_test`, `mockito` | `flutter test` |
| **Firestore mocks** | `fake_cloud_firestore`, `firebase_auth_mocks` | Used within `flutter test` |
| **Firestore rules tests** | `@firebase/rules-unit-testing` (JS) | `npm --prefix functions run test:rules` (requires emulator) |
| **Cloud Functions lint** | ESLint | `npm --prefix functions run lint` |

### Test Infrastructure

- **Mock factories:** `test/helpers/firebase_mock.dart`, `mock_firebase_service.dart`
- **Test data:** `test/helpers/test_data_factory.dart` — generates sample models
- **Coverage areas:** Services (Firebase, offline, linking, levels), Models (serialisation/deserialisation), Widgets, Routing

### Code Quality

| Tool | Config |
|------|--------|
| **Dart analysis** | `analysis_options.yaml` with `flutter_lints` |
| **ESLint** | `functions/.eslintrc.js` for TypeScript/JS |
| **Git LFS** | `.gitattributes` — large image assets tracked via LFS |

---

## 9. FUTURE CONSIDERATIONS

### Planned — Admin Web Dashboard
- **Technology:** Next.js (planned, documented in `LUMI_ADMIN_BACKEND_PLAN.md`)
- **Purpose:** School admin operations outside the mobile app — bulk user management, analytics, billing
- **Status:** Planning phase

### Known Technical Debt
- **Legacy theme systems** — `_archived_minimal_theme/`, `minimal/`, `glass/` widget directories are deprecated but retained
- **Provider → Riverpod migration** — `provider` 6.1.2 still used alongside `flutter_riverpod` 3.0.3
- **Hive unencrypted** — local cache stores data without encryption (relies on device-level security)
- **No CI/CD pipeline** — builds and deployments are manual (no GitHub Actions or similar)

### Roadmap Items
- Firebase Performance Monitoring integration
- Automated CI/CD pipeline (GitHub Actions)
- Admin web dashboard (Next.js)
- Enhanced offline conflict resolution
- Multi-language (i18n) support expansion

---

## 10. GLOSSARY

| Term | Definition |
|------|-----------|
| **Allocation** | A reading assignment created by a teacher — can be level-based, title-based, or free-choice, with a cadence (daily/weekly/fortnightly) |
| **Cadence** | The frequency of a reading allocation: `daily`, `weekly`, `fortnightly`, or `custom` |
| **FCM** | Firebase Cloud Messaging — Google's push notification service |
| **GoRouter** | Declarative routing package for Flutter with support for deep linking, guards, and redirects |
| **Hive** | Lightweight, fast key-value database for Flutter (used for offline caching) |
| **LLLL** | Learning Logic — a book supplier whose product catalogue is embedded locally for instant ISBN lookups |
| **Level Schema** | The reading level system used by a school: A-to-Z, PM Benchmark, Lexile, or custom |
| **Lumi** | The app's mascot character and the name of the custom design system |
| **Multi-tenant** | Data architecture where all data is scoped under `/schools/{schoolId}/` paths |
| **Parent linking** | Process where parents scan or enter an 8-character code to link their account to their child's student record |
| **Reading log** | A single reading session entry: date, minutes read, feeling (mood), books read |
| **Riverpod** | Reactive state management library for Flutter (successor to Provider) |
| **School code** | An access code used during school registration/onboarding |
| **Soft delete** | Records marked `isActive: false` rather than removed — preserves audit history |
| **Student link code** | An 8-character code (excluding ambiguous chars I, O, 1, 0) that parents use to link to a student |
| **Sync queue** | Hive-backed list of offline changes waiting to upload when connectivity returns |

---

## 11. PROJECT IDENTIFICATION

| Field | Value |
|-------|-------|
| **Project name** | Lumi Reading Diary |
| **Repository** | `lumi_reading_tracker` |
| **Firebase project** | `lumi-kakakids` |
| **Primary contact** | nicplev |
| **Platforms** | iOS, Android, Web |
| **Primary language** | Dart (Flutter) |
| **Backend language** | TypeScript (Cloud Functions) |
| **Date of last update** | 2026-03-19 |
