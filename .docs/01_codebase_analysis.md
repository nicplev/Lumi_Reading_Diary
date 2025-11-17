# Lumi Reading Diary - Codebase Analysis
*Generated: 2025-11-16*

## Executive Summary

Lumi Reading Diary is a well-architected Flutter application designed for schools, teachers, parents, and students to track reading progress. Current state: **Solid MVP (60% production-ready)** with excellent architecture but critical gaps in testing, offline functionality, and cloud services.

## App Architecture

### Folder Structure (78 Dart files)
```
lib/
├── core/                    # Shared components
│   ├── theme/              # Material Design 3 themes
│   └── widgets/            # 21 reusable widgets (glass & minimal)
├── data/models/            # 8 data models
├── screens/                # Role-based UI
│   ├── admin/              # 9 screens
│   ├── auth/               # 7 screens
│   ├── parent/             # 5 screens
│   └── teacher/            # 5 screens
├── services/               # Business logic (6 files)
└── utils/                  # Helpers (3 files)
```

### Technology Stack
- **Framework**: Flutter (iOS/Android/Web)
- **Backend**: Firebase (Auth, Firestore, Storage, Messaging)
- **State Management**: Provider + Riverpod (underutilized)
- **Local Storage**: Hive + SharedPreferences
- **Navigation**: Manual (go_router installed but not used)

## Core Features

### ✅ Implemented
1. Multi-role authentication (Parent, Teacher, Admin)
2. School onboarding wizard
3. Parent-student linking with unique codes
4. Daily reading logging
5. Reading allocations/assignments
6. Multi-class/multi-teacher support
7. CSV import/export
8. Reading streak tracking
9. Weekly progress charts
10. Lumi mascot with 7 moods

### ⚠️ Incomplete/Missing
1. **Cloud Functions** - None (stats calculated client-side = security risk)
2. **Offline Sync** - Structure exists, logic incomplete
3. **Push Notifications** - Setup but not delivering
4. **Testing** - 0% coverage
5. **Book Database** - Free text only, no ISBN/covers
6. **Achievements** - Mentioned but not built
7. **Parent-Teacher Messaging** - Not implemented
8. **Dark Mode** - Defined but not active
9. **Analytics Tracking** - Not configured
10. **GDPR Compliance** - Incomplete (delete cascade missing)

## User Roles & Capabilities

### Parents
- Link to multiple children via 8-character codes
- Log daily reading (minutes, books, notes, photos)
- View weekly/monthly progress charts
- Track reading streaks
- **Blocked from web access** (mobile only)

### Teachers
- Manage multiple classes
- Create reading allocations (by level/title/free choice)
- Monitor student progress
- Generate parent linking codes
- Export class data to CSV
- **Can use web version**

### School Admins
- Full user management
- Student CSV bulk import
- Class creation/management
- School-wide analytics
- Parent code oversight
- **Can use web version**

## Data Models (8 Core Models)

1. **UserModel** - Multi-role (parent/teacher/admin)
2. **StudentModel** - Profiles with stats & reading levels
3. **ReadingLogModel** - Daily entries with offline support
4. **SchoolModel** - Institution settings & subscriptions
5. **ClassModel** - Groups with multi-teacher support
6. **AllocationModel** - Reading assignments
7. **StudentLinkCodeModel** - Secure parent linking (365-day validity)
8. **SchoolOnboardingModel** - Registration workflow

## Firebase Architecture

### Firestore Structure (Nested)
```
schools/{schoolId}/
├── users/{userId}              # Teachers, admins
├── parents/{parentId}          # Parents (separate)
├── students/{studentId}        # Student profiles
├── classes/{classId}           # Class groups
├── readingLogs/{logId}         # Daily logs
└── allocations/{allocationId}  # Assignments

Top-level:
├── studentLinkCodes/{codeId}
└── schoolOnboarding/{onboardingId}
```

### Security Rules
- ✅ Comprehensive role-based access control
- ✅ School data isolation
- ✅ Parent-child relationship validation
- ✅ Teacher-class authorization

### Cloud Functions
- ❌ **NOT IMPLEMENTED** - Critical gap for production

## UI/UX Design

### Two Design Systems
1. **Liquid Glass** (Primary) - Glassmorphic with gradients & blur
2. **Minimal** (Alternative) - Clean, simple components

### Widget Library
- **Glass**: GlassCard, GlassButton, GlassProgressBar, GlassStatCard, GlassGoalCard, GlassAchievementBadge
- **Minimal**: RoundedCard, PillButton, PillTabBar, IconCard, BookCard, DateSelector, SearchBar, StreakIndicator

### Lumi Mascot
- Custom painted character
- 7 moods: happy, celebrating, encouraging, thinking, waving, reading, sleeping
- Animated with flutter_animate
- Speech bubbles for contextual messages

## Platform Support

### iOS
- ✅ Fully configured for Firebase
- ✅ APNS token handling
- ⚠️ Needs physical device testing

### Android
- ✅ Basic configuration
- ⚠️ Needs google-services.json verification
- ⚠️ Needs permission manifest updates

### Web
- ✅ Teachers/Admins supported
- ❌ Parents blocked (mobile only)
- ⚠️ Limited functionality

## Code Quality Assessment

### Strengths
- Clear feature-based organization
- Separation of concerns
- Consistent naming conventions
- Reusable widget library
- Excellent external documentation

### Weaknesses
- **Zero test coverage** (only placeholder)
- No error reporting service (Crashlytics)
- Direct Firestore calls (no repository pattern)
- Riverpod underutilized (mostly setState)
- go_router installed but not used
- Magic numbers in code

## Security Analysis

### ✅ Good Practices
- Comprehensive Firestore rules
- Firebase Auth standard
- Server-side validation via rules
- No passwords stored client-side

### ⚠️ Vulnerabilities
- Stats calculated client-side (can be manipulated)
- No rate limiting
- No file upload size limits
- Incomplete GDPR compliance
- No error rate limiting

## Critical Dependencies

### Firebase
- firebase_core: ^4.2.0
- firebase_auth: ^6.1.1
- cloud_firestore: ^6.0.3
- firebase_storage: ^13.0.3
- firebase_messaging: ^16.0.3

### UI/Charts
- fl_chart: ^1.1.1
- flutter_animate: ^4.5.0
- google_fonts: ^6.2.1

### State/Storage
- provider: ^6.1.2
- flutter_riverpod: ^3.0.3
- hive: ^2.2.3

## Production Readiness Score: 60%

### What's Working (60%)
- ✅ Core features functional
- ✅ Solid data architecture
- ✅ Comprehensive security rules
- ✅ Multi-role system
- ✅ Beautiful UI

### Critical Gaps (40%)
- ❌ Zero testing
- ❌ No Cloud Functions
- ❌ Incomplete offline sync
- ❌ No error reporting
- ❌ No analytics tracking
- ❌ Missing GDPR features

## Recommended Timeline: 6-8 Weeks to Production

### Phase 1: Critical Fixes (Week 1-2)
1. Cloud Functions for stats aggregation
2. Complete offline sync
3. Notification delivery system
4. Firebase Crashlytics
5. Testing framework (60% coverage)

### Phase 2: Core Features (Week 3-4)
1. Book database
2. Achievement system
3. Photo upload completion
4. Parent-teacher messaging
5. Scheduled reminders

### Phase 3: Polish (Week 5-6)
1. go_router migration
2. Repository pattern
3. Riverpod migration
4. Dark mode
5. Accessibility
6. Tablet optimization

### Phase 4: Launch Ready (Week 7-8)
1. Physical device testing
2. Performance optimization
3. Multi-language support
4. App store preparation
5. Load testing

## Key Insights

1. **Architecture is solid** - Great foundation for scaling
2. **Firebase integration excellent** - Comprehensive setup
3. **Security rules impressive** - Well thought-out
4. **Missing backend** - Cloud Functions critical for production
5. **Testing gap critical** - Must address before launch
6. **Offline needs work** - Structure there, logic incomplete

---

*Next Steps: Persona-based brainstorming and feature prioritization*
