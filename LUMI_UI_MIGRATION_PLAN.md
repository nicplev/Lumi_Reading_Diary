# Lumi Design System - Complete Migration Plan

**Created:** 2025-11-23
**Status:** Ready to Execute
**Remaining Screens:** 24 of 35 (69%)
**Estimated Timeline:** 12-15 working days

---

## Executive Summary

This plan provides a comprehensive, prioritized roadmap for migrating all remaining screens in the Lumi Reading Tracker app to the Lumi Design System. The migration is organized into 5 phases based on user impact, feature area, and complexity.

**Current Status:**
- ✅ **Completed:** 11 screens (10 parent screens + 1 admin screen)
- 🔄 **Remaining:** 24 screens across auth, teacher, admin, and onboarding flows

---

## Phase Breakdown

| Phase | Focus Area | Screens | Effort | Priority |
|-------|-----------|---------|--------|----------|
| **1** | Auth & Core Flows | 5 | 14-19h | CRITICAL |
| **2** | Teacher Core | 6 | 28-37h | HIGH |
| **3** | Minimal Themes | 2 | 11-15h | HIGH |
| **4** | Admin Tools | 7 | 34-44h | MEDIUM |
| **5** | Onboarding | 4 | 15-20h | LOW |
| **Total** | **All Areas** | **24** | **102-135h** | **Mixed** |

---

## PHASE 1: Authentication & Core User Flows 🔐

**Timeline:** Days 1-3 (3 days)
**Priority:** CRITICAL - User entry points
**Effort:** 14-19 hours

### 1.1 splash_screen.dart
- **Path:** `lib/screens/auth/splash_screen.dart`
- **Lines:** 172
- **Complexity:** ⭐ Simple
- **Effort:** 1-2 hours
- **Components:** LumiMascot, CircularProgressIndicator, minimal layout
- **Special Notes:**
  - Already uses LumiMascot
  - Quick win to build momentum
  - Auth state checking logic (keep intact)
- **Migration Focus:**
  - Update text styles → LumiTextStyles
  - Update spacing → LumiGap/LumiPadding
  - Verify background color → AppColors.offWhite

### 1.2 forgot_password_screen.dart
- **Path:** `lib/screens/auth/forgot_password_screen.dart`
- **Lines:** 326
- **Complexity:** ⭐ Simple
- **Effort:** 2-3 hours
- **Components:** FormBuilder, ElevatedButton, TextButton, Container
- **Special Notes:**
  - Email reset flow with state management
  - Success/error states with animations
  - LumiMascot integration
- **Migration Focus:**
  - Replace ElevatedButton → LumiPrimaryButton
  - Replace TextButton → LumiTextButton
  - Update FormBuilderTextField decoration
  - Replace success Container → LumiCard
  - Update all colors, text styles, spacing

### 1.3 register_screen.dart
- **Path:** `lib/screens/auth/register_screen.dart`
- **Lines:** 711
- **Complexity:** ⭐⭐ Medium
- **Effort:** 4-5 hours
- **Components:** FormBuilder (5 fields), custom _RoleCard widget
- **Special Notes:**
  - Role selection cards (Parent/Teacher)
  - School code validation for teachers
  - Password visibility toggles
  - Complex registration logic
- **Migration Focus:**
  - Migrate custom _RoleCard to use LumiCard
  - Replace all buttons → Lumi equivalents
  - Update form field styling
  - Update role selection cards
  - Apply LumiTextStyles throughout

### 1.4 parent_registration_screen.dart
- **Path:** `lib/screens/auth/parent_registration_screen.dart`
- **Lines:** 701
- **Complexity:** ⭐⭐ Medium
- **Effort:** 4-5 hours
- **Components:** Multi-step FormBuilder, LinearProgressIndicator
- **Special Notes:**
  - Multi-step wizard (3 steps: Parent Info → Student Info → Confirmation)
  - Progress indicator bar
  - Student linking logic
  - LumiMascot mood changes per step
- **Migration Focus:**
  - Update LinearProgressIndicator colors → AppColors.rosePink
  - Replace step cards → LumiCard
  - Update all form fields
  - Replace buttons → Lumi components
  - Update spacing between steps

### 1.5 web_not_available_screen.dart
- **Path:** `lib/screens/auth/web_not_available_screen.dart`
- **Lines:** 345
- **Complexity:** ⭐⭐ Medium
- **Effort:** 3-4 hours
- **Components:** OutlinedButton, custom _AppStoreButton, _FeatureItem widgets
- **Special Notes:**
  - **⚠️ REMOVE LinearGradient backgrounds**
  - App store download links
  - Long-press to copy functionality
  - Feature list display
- **Migration Focus:**
  - **Remove ALL LinearGradient** → Replace with AppColors.offWhite
  - Replace OutlinedButton → LumiSecondaryButton
  - Migrate custom widgets to use Lumi components
  - Update icon styling and colors
  - Update feature cards → LumiCard

---

## PHASE 2: Teacher Screens - Core Functionality 👨‍🏫

**Timeline:** Days 4-7 (4 days)
**Priority:** HIGH - Primary teacher workflows
**Effort:** 28-37 hours

### 2.1 teacher_profile_screen.dart
- **Path:** `lib/screens/teacher/teacher_profile_screen.dart`
- **Lines:** 368
- **Complexity:** ⭐ Simple
- **Effort:** 2-3 hours
- **Components:** Card, ListTile, AlertDialog, TextFormField
- **Special Notes:**
  - Profile editing form
  - Password change dialog
  - Simple layout
- **Migration Focus:**
  - Replace Card → LumiCard
  - Replace ElevatedButton → LumiPrimaryButton
  - Update AlertDialog styling with LumiBorders.shapeLarge
  - Update TextFormField decoration
  - Apply LumiTextStyles to ListTile

### 2.2 class_report_screen.dart
- **Path:** `lib/screens/teacher/class_report_screen.dart`
- **Lines:** 535
- **Complexity:** ⭐⭐ Medium
- **Effort:** 3-4 hours
- **Components:** Card, DatePickers, PDF generation
- **Special Notes:**
  - Date range selector
  - PDF report generation (keep existing logic)
  - Student data aggregation
- **Migration Focus:**
  - Replace Card → LumiCard
  - Replace ElevatedButton/OutlinedButton → Lumi buttons
  - Update date picker button styling
  - Update preview cards
  - **Keep PDF service unchanged**

### 2.3 class_detail_screen.dart
- **Path:** `lib/screens/teacher/class_detail_screen.dart`
- **Lines:** 576
- **Complexity:** ⭐⭐ Medium
- **Effort:** 4-5 hours
- **Components:** Table, Dropdown, FloatingActionButton, CSV export
- **Special Notes:**
  - Student list with sorting (name, level, streak)
  - Table/DataTable for student display
  - CSV export functionality
  - Period selector (week/month)
- **Migration Focus:**
  - Replace FloatingActionButton → LumiFab
  - Update Table/DataTable cell styling
  - Replace Dropdown decoration
  - Update sorting controls
  - **Keep CSV export logic unchanged**

### 2.4 reading_groups_screen.dart
- **Path:** `lib/screens/teacher/reading_groups_screen.dart`
- **Lines:** 1,102
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 6-8 hours
- **Components:** RefreshIndicator, GridView, drag-and-drop, multiple dialogs
- **Special Notes:**
  - **Largest teacher screen**
  - Reading group management
  - Student assignment with drag-drop
  - Multiple dialogs (create group, assign students)
- **Migration Focus:**
  - Replace all Card → LumiCard
  - Replace FloatingActionButton → LumiFab
  - Update GridView item styling
  - Update all dialogs → LumiBorders.shapeLarge
  - Replace all buttons → Lumi components
  - **Keep drag-drop logic unchanged**

### 2.5 allocation_screen.dart
- **Path:** `lib/screens/teacher/allocation_screen.dart`
- **Lines:** 1,115
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 7-9 hours
- **Components:** TabBar (3 tabs), Checkbox lists, DatePicker, forms
- **Special Notes:**
  - **Largest screen in entire app**
  - Book allocation system
  - 3 tabs: Allocate, History, Returns
  - Checkbox selection for students
  - Date-based tracking
  - Complex state management
- **Migration Focus:**
  - Update AppBar and TabBar styling
  - Replace all Card → LumiCard
  - Update Checkbox styling (colors)
  - Replace all buttons → Lumi components
  - Update DatePicker button styling
  - Apply LumiTextStyles throughout all 3 tabs
  - **Keep business logic unchanged**

### 2.6 teacher_home_screen.dart
- **Path:** `lib/screens/teacher/teacher_home_screen.dart`
- **Lines:** 1,065
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 6-8 hours
- **Components:** **LiquidGlassTheme**, **glass_widgets**, BarChart, TabBar
- **Special Notes:**
  - **⚠️ CRITICAL: Remove ALL glass effects**
  - Main teacher dashboard
  - Class selector and statistics
  - BarChart from fl_chart
  - Bottom navigation
- **Migration Focus:**
  - **Remove `import 'liquid_glass_theme.dart'`**
  - **Remove `import 'glass_widgets.dart'`**
  - Replace LiquidGlassTheme gradient → AppColors.offWhite
  - Replace GlassCard → LumiCard
  - Replace GlassButton → LumiPrimaryButton
  - Replace GlassMiniStat → Create `_buildMiniStat` helper (see parent_home_screen.dart:151 for reference)
  - Update BarChart colors → Lumi palette (rosePink, mintGreen, warmOrange)
  - Update TabBar styling
  - Update bottom navigation colors

**📚 Reference:** See [parent_home_screen.dart](lib/screens/parent/parent_home_screen.dart) for glass-to-Lumi conversion patterns

---

## PHASE 3: Teacher & Admin Screens - Minimal Variants 🎨

**Timeline:** Days 8-9 (2 days)
**Priority:** HIGH - Alternate theme removal
**Effort:** 11-15 hours

### 3.1 teacher_home_screen_minimal.dart
- **Path:** `lib/screens/teacher/teacher_home_screen_minimal.dart`
- **Lines:** 882
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 5-7 hours
- **Components:** **MinimalTheme**, minimal_widgets, charts, statistics
- **Special Notes:**
  - **⚠️ Remove MinimalTheme** (separate design system)
  - Similar to teacher_home_screen but different theme
  - Charts and statistics
- **Migration Focus:**
  - **Remove `import 'minimal_theme.dart'`**
  - **Remove `import 'minimal_widgets.dart'`**
  - Replace minimal widgets with Lumi equivalents
  - Replace minimal cards → LumiCard
  - Replace minimal buttons → Lumi buttons
  - Update chart colors → Lumi palette
  - Update statistics cards

### 3.2 admin_home_screen_minimal.dart
- **Path:** `lib/screens/admin/admin_home_screen_minimal.dart`
- **Lines:** 1,168
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 6-8 hours
- **Components:** **MinimalTheme**, minimal_widgets, TabBar, statistics
- **Special Notes:**
  - **⚠️ Remove MinimalTheme**
  - TabBar with multiple management sections
  - School-wide statistics
  - User management integration
- **Migration Focus:**
  - **Remove MinimalTheme imports**
  - Replace all minimal components → Lumi equivalents
  - Update TabBar styling
  - Replace statistics cards → LumiCard
  - Update all buttons → Lumi components
  - Apply LumiTextStyles throughout

---

## PHASE 4: Admin Screens - Management Tools ⚙️

**Timeline:** Days 10-12 (3 days)
**Priority:** MEDIUM - Secondary admin workflows
**Effort:** 34-44 hours

### 4.1 database_migration_screen.dart
- **Path:** `lib/screens/admin/database_migration_screen.dart`
- **Lines:** 494
- **Complexity:** ⭐ Simple
- **Effort:** 3-4 hours
- **Components:** LinearProgressIndicator, ListView, ScrollController
- **Special Notes:**
  - Migration progress tracking
  - Scrollable list of migration steps
  - Progress indicators
- **Migration Focus:**
  - Replace Card → LumiCard
  - Replace ElevatedButton → LumiPrimaryButton
  - Update LinearProgressIndicator colors → AppColors.rosePink
  - Update AlertDialog styling
  - Apply LumiTextStyles to migration steps

### 4.2 class_management_screen.dart
- **Path:** `lib/screens/admin/class_management_screen.dart`
- **Lines:** 914
- **Complexity:** ⭐⭐ Medium
- **Effort:** 4-5 hours
- **Components:** FloatingActionButton, TextField search, StreamBuilder, CSV
- **Special Notes:**
  - **Partially migrated** (uses some Lumi colors)
  - CSV import dialog integration
  - Class CRUD operations
  - Search functionality
- **Migration Focus:**
  - Complete partial migration
  - Replace FloatingActionButton → LumiFab
  - Update TextField decoration
  - Replace remaining buttons → Lumi components
  - Update ListTile styling

### 4.3 csv_import_dialog.dart
- **Path:** `lib/screens/admin/csv_import_dialog.dart`
- **Lines:** 981
- **Complexity:** ⭐⭐ Medium
- **Effort:** 5-6 hours
- **Components:** Dialog, file picker, CSV parsing, data tables
- **Special Notes:**
  - CSV upload and parsing
  - Preview table
  - Validation and error handling
  - Reusable component used by multiple screens
- **Migration Focus:**
  - Update AlertDialog styling → LumiBorders.shapeLarge
  - Replace all buttons → Lumi components
  - Update Table/DataTable styling
  - Update progress indicators
  - Replace error/success cards → LumiCard
  - **Keep CSV parsing logic unchanged**

### 4.4 student_management_screen.dart
- **Path:** `lib/screens/admin/student_management_screen.dart`
- **Lines:** 1,039
- **Complexity:** ⭐⭐ Medium
- **Effort:** 5-6 hours
- **Components:** StreamBuilder, search, forms, CSV import
- **Special Notes:**
  - **Partially migrated**
  - Student CRUD operations
  - CSV import integration
  - Parent linking
- **Migration Focus:**
  - Complete partial migration
  - Replace FloatingActionButton → LumiFab
  - Update search TextField decoration
  - Replace all buttons → Lumi components
  - Update form dialogs
  - Update student cards → LumiCard

### 4.5 parent_linking_management_screen.dart
- **Path:** `lib/screens/admin/parent_linking_management_screen.dart`
- **Lines:** 1,092
- **Complexity:** ⭐⭐ Medium
- **Effort:** 5-7 hours
- **Components:** Clipboard, StreamBuilder, code generation, actions
- **Special Notes:**
  - Parent-student link management
  - Code generation and copying
  - Link/unlink workflows
  - Real-time updates
- **Migration Focus:**
  - Replace Card → LumiCard
  - Replace IconButton → LumiIconButton
  - Replace ElevatedButton → LumiPrimaryButton
  - Update code display styling
  - Update status indicators
  - Apply LumiTextStyles throughout

### 4.6 school_analytics_dashboard.dart
- **Path:** `lib/screens/admin/school_analytics_dashboard.dart`
- **Lines:** 1,091
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 6-8 hours
- **Components:** **fl_chart** (BarChart, LineChart, PieChart), date filters
- **Special Notes:**
  - Multiple chart types
  - School-wide analytics
  - Date range filtering
  - Statistics cards
- **Migration Focus:**
  - Replace Card → LumiCard
  - Update BarChart colors → Lumi palette
  - Update LineChart colors → Lumi palette
  - Update PieChart colors → Lumi palette
  - Replace all buttons → Lumi components
  - Update date filter styling
  - Update statistics cards
  - **Keep chart logic unchanged**

### 4.7 admin_home_screen.dart
- **Path:** `lib/screens/admin/admin_home_screen.dart`
- **Lines:** 1,183
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 6-8 hours
- **Components:** **MinimalTheme**, TabBar, statistics, user management
- **Special Notes:**
  - **⚠️ Remove MinimalTheme**
  - Main admin dashboard
  - Statistics overview
  - TabBar navigation
  - Integration with other admin screens
- **Migration Focus:**
  - **Remove MinimalTheme imports**
  - Replace all minimal components → Lumi equivalents
  - Update TabBar styling
  - Replace statistics cards → LumiCard
  - Update FloatingActionButton → LumiFab
  - Apply LumiTextStyles throughout

---

## PHASE 5: Onboarding & Marketing 🚀

**Timeline:** Days 13-15 (3 days)
**Priority:** LOW - Public-facing screens
**Effort:** 15-20 hours

### 5.1 demo_request_screen.dart
- **Path:** `lib/screens/onboarding/demo_request_screen.dart`
- **Lines:** 348
- **Complexity:** ⭐ Simple
- **Effort:** 2-3 hours
- **Components:** FormBuilder (6 fields), Dropdown, AlertDialog
- **Special Notes:**
  - Demo request form
  - Dropdown for referral source
  - Success dialog → registration wizard
  - LumiMascot integration
- **Migration Focus:**
  - Replace ElevatedButton → LumiPrimaryButton
  - Update FormBuilderTextField decoration
  - Update Dropdown styling
  - Update AlertDialog → LumiBorders.shapeLarge
  - Apply LumiTextStyles throughout

### 5.2 school_demo_screen.dart
- **Path:** `lib/screens/onboarding/school_demo_screen.dart`
- **Lines:** 388
- **Complexity:** ⭐⭐ Medium
- **Effort:** 3-4 hours
- **Components:** PageView, custom _DemoSlide widget, LinearGradient
- **Special Notes:**
  - **⚠️ REMOVE LinearGradient backgrounds**
  - PageView slider with demo content
  - Custom slide widget
  - Page indicators
- **Migration Focus:**
  - **Remove ALL LinearGradient** → Replace with AppColors.offWhite
  - Migrate _DemoSlide widget to use Lumi components
  - Replace ElevatedButton/TextButton → Lumi buttons
  - Update page indicator styling
  - Update slide content cards

### 5.3 school_registration_wizard.dart
- **Path:** `lib/screens/onboarding/school_registration_wizard.dart`
- **Lines:** 608
- **Complexity:** ⭐⭐ Medium
- **Effort:** 4-5 hours
- **Components:** Multi-step form, FormBuilder, progress indicator
- **Special Notes:**
  - Multi-step registration wizard
  - School setup process
  - Form validation across steps
  - Progress tracking
- **Migration Focus:**
  - Update progress indicator → AppColors.rosePink
  - Replace all Card → LumiCard
  - Replace all buttons → Lumi components
  - Update FormBuilderTextField decoration
  - Apply LumiSpacing between steps
  - Update step transition animations

### 5.4 landing_screen.dart
- **Path:** `lib/screens/marketing/landing_screen.dart`
- **Lines:** 1,135
- **Complexity:** ⭐⭐⭐ Complex
- **Effort:** 6-8 hours
- **Components:** **RadialGradient**, **GoogleFonts**, animations, sections
- **Special Notes:**
  - **⚠️ REMOVE RadialGradient** animated blobs
  - **⚠️ EVALUATE GoogleFonts** - keep if part of Lumi branding
  - Marketing landing page
  - Multiple sections: hero, features, how-it-works, benefits, CTA, footer
  - Animations with flutter_animate
  - ScrollController for navigation
- **Migration Focus:**
  - **Remove ALL RadialGradient** → Replace with solid AppColors.offWhite
  - **Decide on GoogleFonts** - coordinate with design team
  - Replace ElevatedButton/OutlinedButton → Lumi buttons
  - Update all section containers
  - Replace feature cards → LumiCard
  - Update hero section styling
  - Apply LumiTextStyles throughout (or keep GoogleFonts for headings)
  - Update footer styling
  - **Keep animation logic unchanged**

---

## Migration Process (Per Screen)

Follow this exact process for each screen:

### Step 1: Read & Understand
```bash
# Read the screen file
Read lib/screens/[category]/[screen_name].dart
```

### Step 2: Add Imports
Add these imports at the top (if not already present):
```dart
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
```

### Step 3: Systematic Replacement
Work through the file section by section:
1. **Scaffold & AppBar** - Update backgroundColor, title styles
2. **Main content** - Replace containers, cards, spacing
3. **Buttons** - Convert to Lumi button components
4. **Text** - Replace all Theme.of(context) with LumiTextStyles
5. **Dialogs/Modals** - Update shapes and padding
6. **SnackBars** - Update background colors

### Step 4: Verification
Run these grep checks (all should return empty):
```bash
# Check for hardcoded Color() values
grep -n "Color(0x" lib/screens/[category]/[screen_name].dart

# Check for Theme.of(context).textTheme
grep -n "Theme.of(context).textTheme" lib/screens/[category]/[screen_name].dart

# Check for hardcoded TextStyle
grep -n "TextStyle(" lib/screens/[category]/[screen_name].dart

# Check for legacy color names
grep -n "primaryBlue\|backgroundPrimary\|gray\|darkGray" lib/screens/[category]/[screen_name].dart

# Check for deprecated .withOpacity
grep -n "\.withOpacity(" lib/screens/[category]/[screen_name].dart
```

### Step 5: Commit
```bash
git add lib/screens/[category]/[screen_name].dart
git commit -m "refactor: Migrate [screen_name] to Lumi Design System

- Replace all hardcoded colors with AppColors
- Replace all Theme.of(context).textTheme with LumiTextStyles
- Replace all hardcoded spacing with LumiSpacing/LumiGap/LumiPadding
- Replace all buttons with Lumi button components
- Replace all cards with LumiCard
- Replace all hardcoded BorderRadius with LumiBorders
[Add other specific changes]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Special Considerations

### 1. Glass Effects Removal (4 screens)

**Affected Screens:**
- teacher_home_screen.dart
- teacher_home_screen_minimal.dart (if it uses glass)
- parent_home_screen.dart (DONE)

**Action Items:**
- Remove `import '../../core/theme/liquid_glass_theme.dart';`
- Remove `import '../../core/widgets/glass/glass_widgets.dart';`
- Replace `LiquidGlassTheme.backgroundGradient` → `AppColors.offWhite` (solid color)
- Replace `GlassCard` → `LumiCard`
- Replace `AnimatedGlassCard` → `LumiCard`
- Replace `GlassButton` → `LumiPrimaryButton`
- Replace `GlassMiniStat` → Create custom `_buildMiniStat` helper

**Reference Implementation:**
See [parent_home_screen.dart:151-189](lib/screens/parent/parent_home_screen.dart#L151-L189) for `_buildMiniStat` helper pattern.

### 2. Minimal Theme Removal (4 screens)

**Affected Screens:**
- admin_home_screen.dart
- admin_home_screen_minimal.dart
- teacher_home_screen_minimal.dart

**Action Items:**
- Remove `import '../../core/theme/minimal_theme.dart';`
- Remove `import '../../core/widgets/minimal/minimal_widgets.dart';`
- Replace minimal cards → LumiCard
- Replace minimal buttons → Lumi button components
- Replace minimal colors → AppColors
- Update TabBar styling with Lumi colors

### 3. Gradient Backgrounds Removal (3 screens)

**Affected Screens:**
- web_not_available_screen.dart (LinearGradient)
- school_demo_screen.dart (LinearGradient)
- landing_screen.dart (RadialGradient)

**Action Items:**
- Remove ALL `LinearGradient` decorations
- Remove ALL `RadialGradient` decorations
- Replace gradient containers → solid `AppColors.offWhite`
- Simplify animated blob decorations (landing_screen)
- Update to clean, modern flat design
- Maintain visual hierarchy with cards and spacing instead of gradients

### 4. Chart Libraries (4 screens)

**Affected Screens:**
- teacher_home_screen.dart (BarChart)
- school_analytics_dashboard.dart (BarChart, LineChart, PieChart)
- reading_history_screen.dart (DONE - BarChart, LineChart)

**Action Items:**
- **Keep fl_chart library** - it's excellent
- Update BarChart colors:
  - Primary bars: `AppColors.rosePink`
  - Secondary bars: `AppColors.mintGreen`
  - Tertiary bars: `AppColors.warmOrange`
- Update LineChart colors:
  - Line colors: `AppColors.rosePink`, `AppColors.skyBlue`
  - Grid lines: `AppColors.charcoal.withValues(alpha: 0.1)`
- Update PieChart colors:
  - Use Lumi palette: rosePink, mintGreen, warmOrange, softYellow, skyBlue
- Update tooltip styling:
  - Background: `AppColors.charcoal`
  - Text: `AppColors.white`
  - TextStyle: `LumiTextStyles.bodySmall()`
- Update axis labels:
  - TextStyle: `LumiTextStyles.label(color: AppColors.charcoal)`

**Reference Implementation:**
See [reading_history_screen.dart:394-579](lib/screens/parent/reading_history_screen.dart#L394-L579) for chart color patterns.

### 5. Form Builder Screens (6 screens)

**Affected Screens:**
- forgot_password_screen.dart
- register_screen.dart
- parent_registration_screen.dart
- demo_request_screen.dart
- school_registration_wizard.dart

**Action Items:**
- **Keep flutter_form_builder** - works well with Lumi
- Update FormBuilderTextField InputDecoration:
  ```dart
  decoration: InputDecoration(
    labelText: 'Field Name',
    labelStyle: LumiTextStyles.body(color: AppColors.charcoal.withValues(alpha: 0.7)),
    border: OutlineInputBorder(borderRadius: LumiBorders.medium),
    focusedBorder: OutlineInputBorder(
      borderRadius: LumiBorders.medium,
      borderSide: BorderSide(color: AppColors.rosePink, width: 2),
    ),
  ),
  ```
- Update error message styling:
  ```dart
  errorStyle: LumiTextStyles.bodySmall(color: AppColors.error)
  ```
- Replace submit buttons → LumiPrimaryButton
- Replace secondary buttons → LumiSecondaryButton/LumiTextButton
- Update validator text with LumiTextStyles

### 6. CSV Import Functionality (4 screens)

**Affected Screens:**
- class_management_screen.dart
- student_management_screen.dart
- csv_import_dialog.dart
- class_detail_screen.dart

**Action Items:**
- **Keep ALL existing CSV parsing and import logic**
- **UI changes only** - do not refactor business logic
- Migrate dialog styling:
  ```dart
  shape: LumiBorders.shapeLarge,
  ```
- Update buttons in dialogs → Lumi components
- Update LinearProgressIndicator colors → AppColors.rosePink
- Update data table/preview styling:
  - Header row background: `AppColors.skyBlue.withValues(alpha: 0.3)`
  - Border: `AppColors.charcoal.withValues(alpha: 0.2)`
  - Text: `LumiTextStyles.label()`
- Replace success/error cards → LumiCard with semantic colors

### 7. PDF Generation (2 screens)

**Affected Screens:**
- class_report_screen.dart
- student_report_screen.dart (DONE)

**Action Items:**
- **Keep ALL existing PDF generation logic**
- **UI changes only** - do not touch pdf_report_service.dart
- Update report preview cards → LumiCard
- Replace download/share buttons → LumiPrimaryButton/LumiSecondaryButton
- Update date picker buttons
- Update loading states with `LumiPrimaryButton(isLoading: true)`
- **Optional future task:** Update PDF template colors (separate from migration)

---

## Testing Strategy

### Per-Screen Testing Checklist

After migrating each screen, verify:

- [ ] **Visual Inspection**
  - [ ] Colors match Lumi palette (no legacy colors)
  - [ ] Typography uses LumiTextStyles (consistent hierarchy)
  - [ ] Spacing follows 8pt grid (no odd numbers)
  - [ ] Border radius uses LumiBorders (consistent roundness)
  - [ ] Buttons use Lumi components (consistent appearance)
  - [ ] Cards use LumiCard (consistent elevation/padding)

- [ ] **Grep Verification** (all should return empty)
  - [ ] No hardcoded `Color(0x...)`
  - [ ] No `Theme.of(context).textTheme`
  - [ ] No hardcoded `TextStyle(...)`
  - [ ] No legacy colors (`primaryBlue`, `backgroundPrimary`, `gray`, `darkGray`)
  - [ ] No deprecated `.withOpacity()` (use `.withValues(alpha:)`)

- [ ] **Functional Testing**
  - [ ] All buttons trigger correct actions
  - [ ] Forms validate and submit correctly
  - [ ] Navigation works as expected
  - [ ] Dialogs/modals open and close
  - [ ] Charts render correctly (if applicable)
  - [ ] CSV import works (if applicable)
  - [ ] PDF generation works (if applicable)

- [ ] **Code Review**
  - [ ] All required imports added
  - [ ] No unused imports remaining
  - [ ] Code is clean and readable
  - [ ] No console errors or warnings

### End-of-Phase Testing

After completing each phase:

1. **Build & Run**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Test All Screens in Phase**
   - Navigate to each screen
   - Perform key user actions
   - Verify visual consistency

3. **Regression Testing**
   - Spot-check previously migrated screens
   - Verify no unintended changes

4. **Performance Check**
   - Check for smooth scrolling
   - Verify animations are smooth
   - Check memory usage (if concerns)

---

## Risk Assessment & Mitigation

### High Risk Areas

#### 1. Glass Widgets Dependencies
- **Risk:** Other unmigrated components may depend on glass_widgets
- **Mitigation:**
  - Search for all imports before removal: `grep -r "glass_widgets" lib/`
  - Create compatibility layer if needed
  - Migrate screens using glass components first

#### 2. Chart Color Breakage
- **Risk:** fl_chart updates may break visualizations or data display
- **Mitigation:**
  - Test charts thoroughly after color changes
  - Keep color mappings documented
  - Compare before/after screenshots
  - Verify data accuracy remains unchanged

#### 3. Complex State Management
- **Risk:** allocation_screen and reading_groups_screen have complex state
- **Mitigation:**
  - **UI-only changes** - do not refactor business logic
  - Test all user workflows extensively
  - Keep existing Provider/StreamBuilder patterns
  - Verify state updates still work

#### 4. Form Validation
- **Risk:** FormBuilder styling changes may affect validation display
- **Mitigation:**
  - Test all form submissions (valid and invalid)
  - Check error message display
  - Verify focus behavior
  - Test password visibility toggles

### Medium Risk Areas

#### 1. Multi-step Wizards
- **Risk:** Progress indicators and step transitions may break
- **Mitigation:**
  - Test each step individually
  - Verify state persistence between steps
  - Check back/next navigation
  - Test validation at each step

#### 2. CSV/PDF Services
- **Risk:** External service integrations could be affected
- **Mitigation:**
  - **Do not touch service logic** - UI only
  - Test end-to-end workflows
  - Verify file generation/download
  - Check error handling

#### 3. Responsive Layouts
- **Risk:** Landing page and marketing screens are responsive
- **Mitigation:**
  - Test on multiple screen sizes (mobile, tablet, desktop)
  - Verify breakpoints still work
  - Check text wrapping
  - Test images and media queries

---

## Execution Strategies

### Option A: Single Developer (12-15 days)
**Best for:** Solo projects, learning the design system thoroughly

- Follow phases sequentially (1 → 2 → 3 → 4 → 5)
- Complete one screen fully before moving to next
- Commit after each screen
- Test at end of each phase
- Build momentum with simple screens first

**Pros:**
- Consistent implementation
- Deep understanding of design system
- Fewer merge conflicts

**Cons:**
- Longer overall timeline
- Can become monotonous

### Option B: Two Developers (7-9 days)
**Best for:** Small teams, faster delivery

**Developer 1:** Phases 1, 3, 5 (Auth, Minimal, Marketing)
- Day 1-3: Auth screens (5)
- Day 4-5: Minimal themes (2)
- Day 6-9: Onboarding/Marketing (4)

**Developer 2:** Phases 2, 4 (Teacher, Admin)
- Day 1-4: Teacher screens (6)
- Day 5-9: Admin screens (7)

**Coordination:**
- Daily 15-min standup
- Cross-review each other's PRs
- Shared checklist tracking
- Pair on complex screens (allocation, landing)

**Pros:**
- Faster completion
- Knowledge sharing
- Built-in code review

**Cons:**
- Requires coordination
- Potential merge conflicts
- Need clear ownership

### Option C: Three Developers (5-7 days)
**Best for:** Larger teams, urgent deadlines

**Developer 1 (UI Specialist):** Phase 1 + Phase 2.1-2.3
- Day 1-2: Auth screens (5)
- Day 3-5: Simple teacher screens (3)

**Developer 2 (Complex Features):** Phase 2.4-2.6 + Phase 3
- Day 1-3: Complex teacher screens (3)
- Day 4-5: Minimal themes (2)

**Developer 3 (Admin/Marketing):** Phase 4 + Phase 5
- Day 1-4: Admin screens (7)
- Day 5-7: Onboarding/Marketing (4)

**Coordination:**
- Daily standup at 9am
- Lead developer reviews all PRs
- Shared documentation updates
- Weekly design system sync

**Pros:**
- Fastest completion
- Specialized expertise
- Parallel progress

**Cons:**
- Highest coordination overhead
- Risk of inconsistency
- Requires strong lead

---

## Quick Reference

### Design System Files

**Theme Tokens:**
- [app_colors.dart](lib/core/theme/app_colors.dart) - Color palette
- [lumi_text_styles.dart](lib/core/theme/lumi_text_styles.dart) - Typography
- [lumi_spacing.dart](lib/core/theme/lumi_spacing.dart) - Spacing system
- [lumi_borders.dart](lib/core/theme/lumi_borders.dart) - Border radius

**Components:**
- [lumi_buttons.dart](lib/core/widgets/lumi/lumi_buttons.dart) - All button variants
- [lumi_card.dart](lib/core/widgets/lumi/lumi_card.dart) - Card component
- [lumi_input.dart](lib/core/widgets/lumi/lumi_input.dart) - Input fields

**Reference Screens:**
- [design_system_demo_screen.dart](lib/screens/design_system_demo_screen.dart) - Live component examples
- [parent_home_screen.dart](lib/screens/parent/parent_home_screen.dart) - Glass → Lumi conversion
- [reading_history_screen.dart](lib/screens/parent/reading_history_screen.dart) - Chart color patterns

### Color Mappings Quick Reference

| Old | New |
|-----|-----|
| `AppColors.primaryBlue` | `AppColors.rosePink` |
| `AppColors.secondaryGreen` | `AppColors.mintGreen` |
| `AppColors.secondaryOrange` | `AppColors.warmOrange` |
| `AppColors.backgroundPrimary` | `AppColors.offWhite` |
| `AppColors.gray` | `AppColors.charcoal.withValues(alpha: 0.7)` |
| `AppColors.darkGray` | `AppColors.charcoal` |
| `Colors.green` | `AppColors.mintGreen` or `AppColors.success` |
| `Colors.red` | `AppColors.error` |

### Component Mappings Quick Reference

| Old | New |
|-----|-----|
| `TextButton` | `LumiTextButton` |
| `ElevatedButton` | `LumiPrimaryButton` |
| `OutlinedButton` | `LumiSecondaryButton` |
| `IconButton` | `LumiIconButton` |
| `FloatingActionButton` | `LumiFab` |
| `Card` | `LumiCard` |

### Spacing Quick Reference

| Old | New |
|-----|-----|
| `EdgeInsets.all(16)` | `LumiPadding.allS` |
| `EdgeInsets.all(24)` | `LumiPadding.allM` |
| `SizedBox(height: 4)` | `LumiGap.xxs` |
| `SizedBox(height: 8)` | `LumiGap.xs` |
| `SizedBox(height: 16)` | `LumiGap.s` |
| `SizedBox(height: 24)` | `LumiGap.m` |

---

## Progress Tracking

Use this checklist to track your progress:

### Phase 1: Auth (5 screens)
- [ ] splash_screen.dart
- [ ] forgot_password_screen.dart
- [ ] register_screen.dart
- [ ] parent_registration_screen.dart
- [ ] web_not_available_screen.dart

### Phase 2: Teacher Core (6 screens)
- [ ] teacher_profile_screen.dart
- [ ] class_report_screen.dart
- [ ] class_detail_screen.dart
- [ ] reading_groups_screen.dart
- [ ] allocation_screen.dart
- [ ] teacher_home_screen.dart

### Phase 3: Minimal Themes (2 screens)
- [ ] teacher_home_screen_minimal.dart
- [ ] admin_home_screen_minimal.dart

### Phase 4: Admin Tools (7 screens)
- [ ] database_migration_screen.dart
- [ ] class_management_screen.dart
- [ ] csv_import_dialog.dart
- [ ] student_management_screen.dart
- [ ] parent_linking_management_screen.dart
- [ ] school_analytics_dashboard.dart
- [ ] admin_home_screen.dart

### Phase 5: Onboarding (4 screens)
- [ ] demo_request_screen.dart
- [ ] school_demo_screen.dart
- [ ] school_registration_wizard.dart
- [ ] landing_screen.dart

---

## Success Criteria

### Per Screen:
- ✅ All grep verification checks pass (zero results)
- ✅ Functional testing complete (all features work)
- ✅ Visual inspection approved (matches Lumi design)
- ✅ Individual commit created
- ✅ No console errors or warnings

### Per Phase:
- ✅ All screens in phase complete
- ✅ End-to-phase testing passed
- ✅ No regressions in previous phases
- ✅ Documentation updated

### Overall Migration:
- ✅ All 24 screens migrated (100%)
- ✅ Zero hardcoded colors
- ✅ Zero Theme.of(context).textTheme
- ✅ Zero hardcoded spacing
- ✅ All deprecated APIs updated
- ✅ glass_widgets removed
- ✅ minimal_theme removed
- ✅ All tests passing
- ✅ App compiles without warnings

---

## Post-Migration Tasks

After completing all 24 screens:

### 1. Cleanup
- [ ] Remove unused `glass_widgets/` directory (if no other usage)
- [ ] Remove unused `minimal_theme.dart` (if no other usage)
- [ ] Remove unused `minimal_widgets/` directory (if no other usage)
- [ ] Update `pubspec.yaml` if any dependencies can be removed
- [ ] Run `flutter clean && flutter pub get`

### 2. Documentation
- [ ] Update MIGRATION_STATUS.md to 100% (35/35 screens)
- [ ] Document any new patterns discovered
- [ ] Create before/after screenshot gallery
- [ ] Update README.md with design system links

### 3. Code Quality
- [ ] Run `flutter analyze` - resolve all issues
- [ ] Run `flutter test` - ensure all tests pass
- [ ] Check code coverage (if applicable)
- [ ] Review and consolidate any duplicate code

### 4. Performance Review
- [ ] Measure app size (before vs after)
- [ ] Check rendering performance
- [ ] Profile build times
- [ ] Optimize if needed

### 5. Design System Evolution
- [ ] Review patterns from complex screens
- [ ] Identify reusable components
- [ ] Extract common patterns into widgets
- [ ] Update design_system_demo_screen.dart with new examples

---

## Getting Help

### Resources
- **Design System Guide:** [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)
- **Migration Status:** [MIGRATION_STATUS.md](MIGRATION_STATUS.md)
- **Demo Screen:** [design_system_demo_screen.dart](lib/screens/design_system_demo_screen.dart)

### Common Issues

**Issue:** Colors don't match designs
**Solution:** Double-check AppColors palette, ensure using rosePink not primaryBlue

**Issue:** Spacing looks wrong
**Solution:** Verify 8pt grid system, use LumiSpacing constants

**Issue:** Buttons don't respond to clicks
**Solution:** Check onPressed is not null, verify button is not disabled

**Issue:** Forms won't submit
**Solution:** Check FormBuilder key, verify validators, test with valid data

**Issue:** Charts don't render
**Solution:** Verify data is not empty, check fl_chart version, update colors only

---

## Quick Start Commands

### To Start a New Screen Migration:
```bash
# Read the screen
Read lib/screens/[category]/[screen_name].dart

# Start migration following the 5-step process
# (See "Migration Process" section above)
```

### To Resume Migration:
```
I'm continuing the Lumi Design System migration.

Current phase: [Phase number]
Next screen: [screen_name].dart

Please read LUMI_UI_MIGRATION_PLAN.md for the screen details and follow the migration process.
```

---

**Remember:** Quality over speed. Each screen should be 100% migrated with NO hardcoded values before moving to the next.

**Let's build a beautifully consistent design system! 🎨✨**
