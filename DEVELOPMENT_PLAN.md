# Lumi Reading Tracker - Continued Development Plan

## Context

Lumi is a ~40K-line Flutter app for tracking children's reading habits, serving parents, teachers, and school admins. The core screens and data models are built, but the app has significant gaps between its current implementation and the design vision in `Lumi_Style_Preview.html`. The theme system still uses legacy blue colors and Poppins/Inter fonts instead of the Lumi coral palette and Nunito font. The most critical parent interaction — the reading log flow with blob character assessment — is incomplete. Testing coverage is minimal (~9 test files), and the RBAC system needs hardening before beta. This plan targets **iOS-only beta readiness first**, then a full UI/UX overhaul.

---

## Phase 1: Foundation & Security

**Goal**: Harden RBAC, fix critical safety issues, establish test infrastructure.

### 1.1 RBAC Hardening in Router
**File**: `lib/core/routing/app_router.dart`
- Move web-platform check for parent routes into the global `redirect` handler (currently only checked inside individual route builders)
- Add null-safety guards for `state.extra` across all routes — currently several routes force-unwrap (`user!`) which will crash on deep-link or cold-start
- Add onboarding/marketing route guards (currently unprotected — `/landing`, `/onboarding/*` should be accessible without auth but `/design-system-demo` should not be publicly accessible in production)
- Extract role-checking logic into a testable `RouteGuard` utility class

### 1.2 Null-Safety Audit for Route Builders
**Files**: All route builders in `lib/core/routing/app_router.dart`
- Routes like `/parent/profile` and `/admin/parent-linking` use `user!` without null check — add fallback to LoginScreen
- Routes passing data via `state.extra` need defensive handling for when users navigate via URL directly

### 1.3 Test Infrastructure Setup
**Files**: Create/update test helpers
- Create `test/helpers/test_app_wrapper.dart` — a reusable widget wrapper with ProviderScope + MaterialApp + GoRouter for widget tests
- Create `test/helpers/mock_providers.dart` — centralized mock providers for Riverpod
- Verify existing mocks in `test/helpers/` work with current codebase
- Add `test/helpers/test_data_factory.dart` — factory methods for creating test instances of all models

### 1.4 Model Unit Tests
**Files**: Create tests under `test/models/`
- `user_model_test.dart` — serialization roundtrip, role enum, copyWith
- `book_model_test.dart` — serialization, reading history
- `achievement_model_test.dart` — badge definitions, earned status
- `allocation_model_test.dart` — allocation types, cadence
- `class_model_test.dart`, `school_model_test.dart` — basic serialization
- Expand existing `student_model_test.dart` and `reading_log_model_test.dart`

**Verification**: `flutter test test/models/` — all pass

---

## Phase 2: Core UX Completion

**Goal**: Build the missing reading log flow with blob assessment, success celebration, and streak display. This is the highest-value UX work.

### 2.1 Extend ReadingLogModel with Child Feeling
**File**: `lib/data/models/reading_log_model.dart`
- Add `ReadingFeeling` enum: `hard`, `tricky`, `okay`, `good`, `great` (maps to the 5 blob characters)
- Add `childFeeling` field (nullable `ReadingFeeling`) to `ReadingLogModel`
- Update `toFirestore()`, `fromFirestore()`, `toLocal()`, `fromLocal()` serialization
- Add `parentComment` field if not already present (for template chip comments)
- Update existing tests in `test/models/reading_log_model_test.dart`

### 2.2 Create Blob Assessment Selector Widget
**File**: Create `lib/core/widgets/lumi/blob_selector.dart`
- Widget displays 5 blob characters from `assets/blobs/` (blob-hard.png, blob-tricky.png, blob-okay.png, blob-good.png, blob-great.png)
- Each blob: 80x88px display, 16px border-radius container, label underneath
- Selection state: `scale(1.25)` animation, colored halo background matching blob's associated color
- Hover/tap state: `scale(1.15)` with transition
- Associated colors per Style Preview:
  - Hard: `#6FA8DC` (Sky Blue)
  - Tricky: `#7CB97C` (Sage Green)
  - Okay: `#E8C547` (Golden Yellow)
  - Good: `#F5A347` (Soft Orange)
  - Great: `#E86B6B` (Coral Red)
- Callback: `onFeelingSelected(ReadingFeeling feeling)`
- Use `flutter_animate` for selection transitions

### 2.3 Create Comment Chips Widget
**File**: Create `lib/core/widgets/lumi/comment_chips.dart`
- Pre-written comment templates organized by category:
  - Encouragement: "Great job!", "Keep it up!", "Loved hearing you read!"
  - Reading Skills: "Sounded out words well", "Good finger tracking", "Read with expression"
  - Comprehension: "Understood the story well", "Asked great questions", "Made predictions"
- Chip style per Style Preview: 8px vertical / 16px horizontal padding, 20px pill radius
- Default: light gray background, 1px divider border
- Selected: Lumi Mint background, Sage Green border, checkmark prepended
- Multi-select enabled — concatenate selected chips into parent comment string
- Callback: `onCommentsChanged(List<String> selectedComments)`

### 2.4 Refactor Log Reading Screen into Multi-Step Flow
**File**: `lib/screens/parent/log_reading_screen.dart`
- Convert from single-page form to 4-step `PageView` flow:
  - **Step 1: Select Book** — radio list of assigned books (from allocation) + manual entry option
  - **Step 2: Child Assessment** — `BlobSelector` widget (from 2.2)
  - **Step 3: Parent Comment** — `CommentChips` widget (from 2.3) + optional free-text notes
  - **Step 4: Confirmation** — summary card showing book, feeling, comments; "I read with my child tonight" confirmation button with green gradient
- Add step indicator (dots or progress bar) at top
- Add back/next navigation buttons
- Save `childFeeling` and `parentComment` to the `ReadingLogModel`
- On confirmation, navigate to success celebration screen

### 2.5 Create Success Celebration Screen
**File**: Create `lib/screens/parent/reading_success_screen.dart`
- Displays after reading is logged successfully
- Content per Style Preview:
  - Confetti animation (use `flutter_animate` or custom painter)
  - Large checkmark icon
  - "Reading Logged!" heading
  - Night count: "Night X complete"
  - Streak badge: flame emoji + "X Day Streak"
  - Achievement notification if badge earned: "1 Badge Earned!"
  - Progress to next milestone bar
  - "Done" button returns to parent home
- Route: Add `/parent/reading-success` to `lib/core/routing/app_router.dart`
- Receives reading log data + student stats as navigation parameters

### 2.6 Connect Streak Tracking
**File**: `lib/screens/parent/parent_home_screen.dart`
- Ensure `StudentModel.stats` (currentStreak, bestStreak, totalReadingNights) are displayed
- Wire up streak calculation logic — compare `lastReadDate` to today
- Display streak prominently with flame icon per Style Preview
- Update streak on reading log submission

**Verification**: Manual flow test — open app as parent, navigate to log reading, complete all 4 steps with blob selection, see celebration screen, return home and verify streak updated.

---

## Phase 3: Theme Migration

**Goal**: Fully migrate the MaterialApp theme from legacy blue/Poppins to Lumi coral/Nunito, matching the Style Preview.

### 3.1 Clean Up app_colors.dart
**File**: `lib/core/theme/app_colors.dart`
- Add missing Style Preview colors:
  - `lumiPeach`: `#FFAB91` (gradient endpoint)
  - `lumiLavender`: `#D2EBBF` (book covers)
  - `textSecondary`: `#6B7280` (secondary text)
  - `divider`: `#E5E7EB` (borders)
  - `background`: `#F5F5F7` (app background)
  - `libraryGreen`: `#81C784` (library book badges)
  - `decodableBlue`: `#64B5F6` (decodable book badges)
- Update semantic colors extension to use these values
- Add gradient definitions as static methods:
  - `primaryGradient` → `LinearGradient(135deg, #FF8698, #FFAB91)`
  - `successGradient` → `LinearGradient(135deg, #4CAF50, #66BB6A)`

### 3.2 Rewrite app_theme.dart
**File**: `lib/core/theme/app_theme.dart`
- Replace ALL `AppColors.primaryBlue` references with `AppColors.rosePink`
- Replace ALL `GoogleFonts.poppins()` with `GoogleFonts.nunito()`
- Replace ALL `GoogleFonts.inter()` with `GoogleFonts.nunito()`
- Update `colorScheme` to Lumi palette:
  - `primary`: rosePink, `primaryContainer`: lumiPeach
  - `secondary`: mintGreen, `secondaryContainer`: skyBlue
  - `surface`: white, `background`: #F5F5F7
  - `onPrimary`: white, `onSurface`: charcoal
- Update `scaffoldBackgroundColor` to `#F5F5F7`
- Update `cardTheme`: borderRadius 20px, elevation 0, shadow `BoxShadow(0, 2, 8, rgba(0,0,0,0.04))`
- Update `elevatedButtonTheme`: borderRadius 28px (pill), background rosePink, height 56px
- Update `inputDecorationTheme`: borderRadius 12px, focusedBorder uses rosePink
- Update `bottomNavigationBarTheme`: selectedItemColor rosePink, top corners rounded 24px
- Update `chipTheme`: borderRadius 20px, selectedColor mintGreen
- Match all text sizes to the type scale in `lumi_text_styles.dart`

### 3.3 Update Lumi Component Widgets
**Files**:
- `lib/core/widgets/lumi/lumi_buttons.dart` — ensure gradient backgrounds use `primaryGradient`, pill shape 28px radius, 56px height, shadow `0 4px 12px rgba(255,134,152,0.3)`
- `lib/core/widgets/lumi/lumi_card.dart` — 20px radius, padding 20-24px, shadow `0 2px 8px rgba(0,0,0,0.04)`
- `lib/core/widgets/lumi/lumi_input.dart` — 12px radius, focus border rosePink

### 3.4 Update LumiMascot Legacy References
**File**: `lib/core/widgets/lumi_mascot.dart`
- Replace `AppColors.primaryBlue` reference (sleeping Z's) with `AppColors.rosePink`
- Replace `AppColors.secondaryPurple` (book) with `AppColors.rosePink`
- Replace `AppColors.gray` (shadow) with `AppColors.charcoal.withOpacity(0.1)`

### 3.5 Audit All Screens for Legacy Color References
**Scope**: All files under `lib/screens/`
- Search for `AppColors.primaryBlue`, `AppColors.primaryLightBlue`, `AppColors.primaryDarkBlue`
- Search for `GoogleFonts.poppins`, `GoogleFonts.inter`
- Search for `AppColors.secondaryOrange`, `AppColors.secondaryPurple`
- Replace all with Lumi Design System equivalents
- Search for hardcoded `BorderRadius.circular(16)` on cards → change to 20
- Search for hardcoded colors (hex values in code rather than AppColors references)

**Verification**: `flutter build ios --debug` succeeds. Visual inspection of all screens shows coral palette, Nunito font, rounded pill buttons. No blue or Poppins remnants.

---

## Phase 4: UI Polish & New Components

**Goal**: Build the remaining UI components from the Style Preview that don't exist yet.

### 4.1 Progress Ring Widget
**File**: Create `lib/core/widgets/lumi/progress_ring.dart`
- Multi-layer concentric ring widget per Style Preview:
  - Outer ring (180px diameter, 12px stroke): total nights — coral/peach gradient
  - Middle ring (140px, 10px stroke): weekly progress — segmented (blue/green/yellow/orange at 72deg)
  - Inner ring (100px, 8px stroke): today's status — mint if complete, gray if pending
  - Center: large number (48px bold) + label (14px secondary)
- Parameters: `totalNights`, `weeklyProgress` (0-7), `todayComplete`, `label`
- Use `CustomPainter` for ring rendering with gradient arcs

### 4.2 Week Progress Bar Widget
**File**: Create `lib/core/widgets/lumi/week_progress_bar.dart`
- 7 circles (M T W T F S S) showing daily completion
- Circle size: 40px, gap: 8px
- States per Style Preview:
  - Completed: Lumi Mint fill with checkmark
  - Today (not done): 2px coral border outline only
  - Today (done): Coral fill with checkmark
  - Future: divider gray fill
  - Missed: unfilled with gray outline
- Parameters: `completedDays` (Set of weekday indices), `currentDay`

### 4.3 Stats Card Widget
**File**: Create `lib/core/widgets/lumi/stats_card.dart`
- 3-column layout with vertical dividers
- Each stat: icon (28px), number (24px bold), label (12px secondary)
- Stats: Current Streak (flame), Best Streak (trophy), Total Nights (book)
- Parameters: `currentStreak`, `bestStreak`, `totalNights`

### 4.4 Book Card Widget
**File**: Create or update `lib/core/widgets/minimal/book_card.dart`
- Match Style Preview: 16px radius, 12px padding, flex layout
- Book cover thumbnail: 50x65px, gradient placeholder, 8px radius
- Title: 15px / 600 weight
- Type badge: pill shape — Library (green #81C784) or Decodable (blue #90CAF9)
- Status indicator (assigned date, read status)

### 4.5 Bottom Navigation Bar Redesign
**File**: Update `lib/screens/parent/parent_home_screen.dart` (and any shared nav)
- Match Style Preview: white background, rounded top corners (24px), upward shadow
- 4 items: Home, My Books, Awards, Settings
- Active state: Lumi Coral color
- Inactive: secondary gray
- Icon size: 24px, label: 12px, gap: 4px

### 4.6 Placeholder Asset Setup
**Files**: Create placeholder assets
- `assets/icons/` — use Flutter Icons as placeholders, document each with a README listing what real assets should replace them
- `assets/images/` — create placeholder book cover gradient image
- Create `assets/README.md` listing all placeholder assets and their intended replacements

### 4.7 Update Parent Home Screen
**File**: `lib/screens/parent/parent_home_screen.dart`
- Replace current stats display with `ProgressRing` widget (4.1)
- Add `WeekProgressBar` widget (4.2)
- Add `StatsCard` widget (4.3)
- Update "Tonight's Books" section to use new `BookCard` widget (4.4)
- Update "Log Reading" CTA button to gradient pill style
- Apply new bottom navigation (4.5)

**Verification**: Parent home screen visually matches Style Preview mockup. All widgets render with correct colors, spacing, and animations.

---

## Phase 5: Comprehensive Testing

**Goal**: Achieve meaningful test coverage for beta confidence.

### 5.1 Router & RBAC Tests
**File**: Expand `test/core/routing/app_router_test.dart`
- Test unauthenticated redirect to login
- Test parent role accessing teacher routes → redirect
- Test teacher role accessing admin routes → redirect
- Test parent web access → redirect to web-not-available
- Test null `state.extra` handling for all routes
- Test deep-link navigation with no prior state

### 5.2 Service Tests
**Files**: Create under `test/services/`
- `firebase_service_test.dart` — reading log CRUD, student queries, using fake_cloud_firestore
- `parent_linking_service_test.dart` — code generation, validation, expiry
- `notification_service_test.dart` — reminder scheduling
- Expand existing `offline_service_test.dart` — sync queue, conflict resolution

### 5.3 Widget Tests for Critical Screens
**Files**: Create under `test/screens/`
- `log_reading_screen_test.dart` — 4-step flow navigation, blob selection, comment chips, submission
- `parent_home_screen_test.dart` — data display, navigation to log reading
- `login_screen_test.dart` — form validation, submission, error display
- `splash_screen_test.dart` — routing based on auth state

### 5.4 New Widget Component Tests
**Files**: Create under `test/widgets/`
- `blob_selector_test.dart` — selection state, callback, animation trigger
- `progress_ring_test.dart` — rendering with various values
- `week_progress_bar_test.dart` — day states, current day highlighting
- `comment_chips_test.dart` — multi-select, deselect, callback

**Verification**: `flutter test` — all tests pass. Coverage report shows >70% on models, >60% on services, >50% on critical screens.

---

## Phase 6: Beta Deployment Preparation

**Goal**: Prepare for iOS TestFlight distribution.

### 6.1 Analytics & Crash Reporting Verification
**Files**: `lib/services/crash_reporting_service.dart`, `lib/services/firebase_service.dart`
- Verify Crashlytics is receiving test crashes
- Add custom analytics events for key actions:
  - `reading_logged` — with feeling, book count, duration
  - `badge_earned` — with badge type
  - `streak_milestone` — with streak count
  - `app_opened` — with role
- Verify Firebase Analytics dashboard shows events

### 6.2 iOS Build Configuration
**Files**: `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/`
- Set correct bundle identifier, version, build number
- Configure App Store Connect metadata
- Set up signing certificates and provisioning profiles
- Verify camera/photo library permissions for reading log photos
- Verify push notification entitlements

### 6.3 In-App Feedback Widget
**File**: Create `lib/core/widgets/lumi/feedback_widget.dart`
- Floating action button or settings menu item labeled "Send Feedback"
- Opens bottom sheet with:
  - Category selector (Bug, Feature Request, General Feedback)
  - Text field for description
  - Optional screenshot attachment (use image_picker)
  - Submit button — saves to Firestore `feedback` collection with userId, role, timestamp, device info
- Add to parent/teacher/admin profile screens

### 6.4 Performance Optimization
- Audit all `StreamBuilder` and `FutureBuilder` widgets for unnecessary rebuilds
- Add `const` constructors where missing
- Verify image assets are optimized (blob PNGs are 21-40KB — acceptable)
- Profile app startup time on physical iOS device

### 6.5 Pre-Launch Checklist
- [ ] All Phase 1 security fixes applied
- [ ] Log reading 4-step flow works end-to-end with blob selection
- [ ] Success celebration screen shows correct data
- [ ] Theme fully migrated — no legacy blue or Poppins visible
- [ ] All tests pass (`flutter test`)
- [ ] iOS build succeeds (`flutter build ios --release`)
- [ ] Crashlytics receiving events
- [ ] Analytics events firing
- [ ] Feedback mechanism working
- [ ] Offline reading log + sync works
- [ ] Parent registration with student code works
- [ ] Push notifications work on physical device

---

## Phase Dependencies

```
Phase 1 (Foundation) ──> Phase 2 (Core UX) ──> Phase 3 (Theme) ──> Phase 4 (UI Polish) ──> Phase 5 (Testing) ──> Phase 6 (Beta Prep)
```

Phases 2 and 3 can be worked on partially in parallel since they touch different files, but Phase 3 should be finalized before Phase 4 to ensure new components use the correct theme tokens.

---

## Key Files Reference

| File | Phase | Changes |
|------|-------|---------|
| `lib/core/routing/app_router.dart` | 1 | RBAC hardening, null safety, route guards |
| `lib/data/models/reading_log_model.dart` | 2 | Add ReadingFeeling enum, childFeeling field |
| `lib/screens/parent/log_reading_screen.dart` | 2 | Convert to 4-step flow with blobs |
| `lib/core/theme/app_colors.dart` | 3 | Add missing colors, gradients, clean legacy |
| `lib/core/theme/app_theme.dart` | 3 | Full rewrite: Nunito, coral palette, pill buttons |
| `lib/core/widgets/lumi_mascot.dart` | 3 | Replace legacy color references |
| `lib/core/widgets/lumi/lumi_buttons.dart` | 3 | Gradient backgrounds, pill shape |
| `lib/screens/parent/parent_home_screen.dart` | 4 | Progress ring, week bar, stats card, bottom nav |
| All screens under `lib/screens/` | 3, 4 | Legacy color/font audit and replacement |
| `test/` directory | 1, 5 | Infrastructure + comprehensive test suite |

## New Files to Create

| File | Phase | Purpose |
|------|-------|---------|
| `lib/core/widgets/lumi/blob_selector.dart` | 2 | 5-blob child assessment widget |
| `lib/core/widgets/lumi/comment_chips.dart` | 2 | Template parent comment chips |
| `lib/screens/parent/reading_success_screen.dart` | 2 | Post-reading celebration screen |
| `lib/core/widgets/lumi/progress_ring.dart` | 4 | Multi-layer concentric progress rings |
| `lib/core/widgets/lumi/week_progress_bar.dart` | 4 | 7-day circle progress display |
| `lib/core/widgets/lumi/stats_card.dart` | 4 | 3-column streak/stats display |
| `lib/core/widgets/lumi/feedback_widget.dart` | 6 | In-app beta feedback form |
| `test/helpers/test_app_wrapper.dart` | 1 | Reusable test widget wrapper |
| `test/helpers/test_data_factory.dart` | 1 | Factory methods for test data |
| `assets/README.md` | 4 | Placeholder asset documentation |
