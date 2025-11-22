# Lumi Design System Migration - Status & Guide

**Last Updated:** 2025-11-22
**Progress:** 4/10 Parent Screens Completed (40%)

## 🎯 Mission

Systematically migrate all Parent screens in the Lumi Reading Diary app to use the new Lumi Design System, replacing legacy LiquidGlassTheme and hardcoded values with consistent design tokens.

---

## ✅ COMPLETED SCREENS (3/10)

### 1. parent_profile_screen.dart ✓
- **Commit:** `52c6910` - "refactor: Migrate parent_profile_screen to Lumi Design System"
- **Changes:**
  - Replaced all colors (primaryBlue → rosePink, gray → charcoal)
  - Updated all typography to LumiTextStyles
  - Applied LumiSpacing/LumiGap/LumiPadding throughout
  - Converted TextButton → LumiTextButton
  - Updated CircleAvatar, SwitchListTile, Dialog shapes
  - Applied LumiBorders for all border radius

### 2. student_goals_screen.dart ✓
- **Commit:** `db077b9` - "refactor: Migrate student_goals_screen to Lumi Design System"
- **Changes:**
  - Migrated AppBar with custom TabBar styling
  - Replaced FloatingActionButton → LumiFab
  - Converted all Card → LumiCard (with isHighlighted for summary)
  - Updated ElevatedButton/OutlinedButton → Lumi button components
  - Applied design system to goal cards, progress indicators, empty states
  - Updated dialogs, bottom sheets, and snackbars
  - Fixed all color references (green → mintGreen, orange → warmOrange)

### 3. log_reading_screen.dart ✓
- **Commit:** `28c1913` - "refactor: Migrate log_reading_screen to Lumi Design System"
- **Changes:**
  - Replaced all deprecated colors (backgroundPrimary → offWhite, primaryBlue → rosePink)
  - Updated all Theme.of(context).textTheme → LumiTextStyles
  - Converted all Card → LumiCard
  - Replaced ElevatedButton → LumiPrimaryButton (with isLoading support)
  - Replaced TextButton → LumiTextButton
  - Applied LumiPadding/LumiGap/LumiSpacing throughout (including Wrap spacing)
  - Applied LumiBorders for all border radius
  - Replaced .withOpacity() → .withValues(alpha:)
  - Updated success dialog with Lumi components
  - Migrated form inputs with time selector, book list, notes, and photo attachment

### 4. parent_home_screen.dart ✓
- **Commit:** `1979a05` - "refactor: Migrate parent_home_screen to Lumi Design System"
- **Changes:**
  - Replaced LiquidGlassTheme gradient backgrounds with solid AppColors.offWhite
  - Replaced all GlassCard/AnimatedGlassCard → LumiCard
  - Replaced GlassButton → LumiPrimaryButton
  - Updated all Theme.of(context).textTheme → LumiTextStyles
  - Replaced all deprecated colors (primaryBlue → rosePink, secondaryGreen → mintGreen, secondaryOrange → warmOrange, gray/darkGray → charcoal, lightGray → skyBlue)
  - Applied LumiPadding/LumiGap/LumiSpacing throughout
  - Replaced IconButton → LumiIconButton
  - Applied LumiBorders for all border radius
  - Created custom _buildMiniStat helper to replace GlassMiniStat component
  - Replaced .withOpacity() → .withValues(alpha:)
  - Updated BottomNavigationBar with Lumi colors
  - Migrated loading states, empty states, and all three navigation tabs

---

## 📋 REMAINING SCREENS (6/10)

### High Priority / High Complexity
5. **reading_history_screen.dart** - Charts and data visualization
6. **book_browser_screen.dart** - Complex search/browse UI with tabs

### Medium Priority / Medium Complexity
7. **achievements_screen.dart** - Badge system and gamification
8. **offline_management_screen.dart** - Settings and switches
9. **reminder_settings_screen.dart** - Heavy gradients, needs simplification
10. **student_report_screen.dart** - Reporting interface

---

## ✅ ADMIN SCREENS COMPLETED (1)

### 1. user_management_screen.dart ✓
- **Commit:** `21eadbc` - "refactor: Migrate user_management_screen to Lumi Design System"
- **Changes:**
  - Replaced all deprecated colors (primaryBlue → rosePink, gray → charcoal)
  - Updated all typography to LumiTextStyles (AppBar, cards, badges)
  - Replaced FloatingActionButton.extended → LumiFab(isExtended: true)
  - Converted TextButton → LumiTextButton
  - Replaced ElevatedButton → LumiPrimaryButton
  - Converted all Card → LumiCard (with padding: EdgeInsets.zero for ListTile)
  - Applied LumiPadding/LumiGap/LumiSpacing throughout
  - Applied LumiBorders for all border radius
  - Replaced .withOpacity() → .withValues(alpha:)
  - Updated role badges and status tags with Lumi text styles
  - Maintained error-colored delete buttons with proper Lumi styling

---

## 🎨 DESIGN SYSTEM REFERENCE

### Required Imports
```dart
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
```

### Color Mappings
| Old (Legacy) | New (Lumi) |
|--------------|------------|
| `AppColors.primaryBlue` | `AppColors.rosePink` |
| `AppColors.secondaryGreen` | `AppColors.mintGreen` |
| `AppColors.secondaryOrange` | `AppColors.warmOrange` |
| `AppColors.secondaryYellow` | `AppColors.softYellow` |
| `AppColors.gray` / `Colors.grey[600]` | `AppColors.charcoal.withValues(alpha: 0.7)` |
| `AppColors.darkGray` | `AppColors.charcoal` |
| `AppColors.backgroundPrimary` | `AppColors.offWhite` |
| `AppColors.white` | `AppColors.white` (keep) |
| `Colors.green` | `AppColors.mintGreen` |
| `Colors.red` | `AppColors.error` |

### Typography Mappings
| Old (Legacy) | New (Lumi) |
|--------------|------------|
| `Theme.of(context).textTheme.headlineSmall` | `LumiTextStyles.h2()` |
| `Theme.of(context).textTheme.titleLarge` | `LumiTextStyles.h2()` |
| `Theme.of(context).textTheme.titleMedium` | `LumiTextStyles.h3()` |
| `Theme.of(context).textTheme.bodyLarge` | `LumiTextStyles.bodyLarge()` |
| `Theme.of(context).textTheme.bodyMedium` | `LumiTextStyles.body()` |
| `Theme.of(context).textTheme.bodySmall` | `LumiTextStyles.bodySmall()` |
| `Theme.of(context).textTheme.labelMedium` | `LumiTextStyles.label()` |
| `TextStyle(fontSize: 36, fontWeight: bold)` | `LumiTextStyles.display()` |

### Spacing Mappings
| Old (Legacy) | New (Lumi) |
|--------------|------------|
| `EdgeInsets.all(16)` | `LumiPadding.allS` |
| `EdgeInsets.all(24)` | `LumiPadding.allM` |
| `EdgeInsets.all(32)` | `LumiPadding.allL` |
| `EdgeInsets.symmetric(horizontal: 16)` | `LumiPadding.horizontalS` |
| `SizedBox(height: 4)` | `LumiGap.xxs` |
| `SizedBox(height: 8)` | `LumiGap.xs` |
| `SizedBox(height: 16)` | `LumiGap.s` |
| `SizedBox(height: 24)` | `LumiGap.m` |
| `SizedBox(height: 32)` | `LumiGap.l` |
| `SizedBox(width: 8)` | `LumiGap.horizontalXS` |

### Component Mappings
| Old (Legacy) | New (Lumi) |
|--------------|------------|
| `TextButton` | `LumiTextButton` |
| `ElevatedButton` | `LumiPrimaryButton` |
| `OutlinedButton` | `LumiSecondaryButton` |
| `IconButton` | `LumiIconButton` |
| `FloatingActionButton` | `LumiFab` |
| `FloatingActionButton.extended` | `LumiFab(isExtended: true)` |
| `Card` | `LumiCard` |
| `TextFormField` | `LumiInput` (when available) |

### Border Radius Mappings
| Old (Legacy) | New (Lumi) |
|--------------|------------|
| `BorderRadius.circular(8)` | `LumiBorders.small` |
| `BorderRadius.circular(12)` | `LumiBorders.medium` |
| `BorderRadius.circular(16)` | `LumiBorders.large` |
| `BorderRadius.circular(20)` | `LumiBorders.xLarge` |
| `BorderRadius.circular(999)` | `LumiBorders.circular` |
| `RoundedRectangleBorder(...)` | `LumiBorders.shapeMedium` or `LumiBorders.shapeLarge` |

---

## 🔄 MIGRATION PROCESS (Per Screen)

### Step 1: Read & Understand
```bash
# Read the current screen file
Read lib/screens/parent/[screen_name].dart
```

### Step 2: Add Imports
Add design system imports at the top of the file:
```dart
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
```bash
# Check for hardcoded Color() values
grep -n "Color(0x" lib/screens/parent/[screen_name].dart

# Check for Theme.of(context).textTheme
grep -n "Theme.of(context).textTheme" lib/screens/parent/[screen_name].dart

# Check for hardcoded TextStyle
grep -n "TextStyle(" lib/screens/parent/[screen_name].dart

# Check for legacy color names
grep -n "primaryBlue\|backgroundPrimary\|gray\|darkGray" lib/screens/parent/[screen_name].dart
```

All checks should return "✓ No [item] found" or be empty.

### Step 5: Commit
```bash
git add lib/screens/parent/[screen_name].dart
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

## 📝 MIGRATION EXAMPLES

### Example 1: AppBar
```dart
// ❌ BEFORE
AppBar(
  title: const Text('Reading Goals'),
  backgroundColor: AppColors.primaryBlue,
)

// ✅ AFTER
AppBar(
  title: Text('Reading Goals', style: LumiTextStyles.h3()),
  backgroundColor: AppColors.white,
  elevation: 0,
)
```

### Example 2: Button
```dart
// ❌ BEFORE
ElevatedButton(
  onPressed: () => doSomething(),
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primaryBlue,
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  ),
  child: const Text('Submit'),
)

// ✅ AFTER
LumiPrimaryButton(
  onPressed: () => doSomething(),
  text: 'Submit',
)
```

### Example 3: Card
```dart
// ❌ BEFORE
Card(
  elevation: 2,
  margin: const EdgeInsets.only(bottom: 12),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Text('Content'),
  ),
)

// ✅ AFTER
Padding(
  padding: EdgeInsets.only(bottom: LumiSpacing.listItemSpacing),
  child: LumiCard(
    child: Text('Content'),
  ),
)
```

### Example 4: Text Styles
```dart
// ❌ BEFORE
Text(
  'Hello',
  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
    fontWeight: FontWeight.bold,
  ),
)

// ✅ AFTER
Text('Hello', style: LumiTextStyles.h2())
```

### Example 5: Spacing
```dart
// ❌ BEFORE
Column(
  children: [
    Widget1(),
    const SizedBox(height: 16),
    Widget2(),
    const SizedBox(height: 24),
    Widget3(),
  ],
)

// ✅ AFTER
Column(
  children: [
    Widget1(),
    LumiGap.s,
    Widget2(),
    LumiGap.m,
    Widget3(),
  ],
)
```

---

## ⚠️ IMPORTANT RULES

### STRICT REQUIREMENTS
1. **NO hardcoded Color() values** - All must use AppColors.*
2. **NO hardcoded TextStyle()** - All must use LumiTextStyles.*
3. **NO hardcoded spacing numbers** - All must use LumiSpacing/LumiGap/LumiPadding
4. **NO Theme.of(context).textTheme** - Replace with LumiTextStyles
5. **NO legacy button widgets** - Use Lumi button components
6. **NO legacy Card widgets** - Use LumiCard
7. **NO hardcoded BorderRadius** - Use LumiBorders.*
8. **8pt grid system** - All spacing must be multiples of 8pt

### Color Deprecation Notes
- Replace `.withOpacity(0.X)` with `.withValues(alpha: 0.X)` (new Flutter API)
- `AppColors.primaryBlue` is DEPRECATED → use `AppColors.rosePink`
- `AppColors.backgroundPrimary` is DEPRECATED → use `AppColors.offWhite`
- Semantic colors: `AppColors.success`, `AppColors.error`, `AppColors.warning`

### LumiCard Notes
- LumiCard does NOT support `backgroundColor` parameter (use `isHighlighted: true` for skyBlue)
- LumiCard does NOT support `margin` parameter (wrap with Padding if needed)
- LumiCard includes default padding of `LumiPadding.card` (20pt all sides)
- Override padding with `padding` parameter if needed

---

## 🎯 NEXT STEPS

1. **Start with:** `parent_home_screen.dart` (main dashboard with GlassCards and stats)
2. **Then:** `reading_history_screen.dart` (charts and data visualization)
3. **Continue with:** remaining screens in priority order

### Recommended Approach
- Work on ONE screen at a time
- Read the entire file first to understand structure
- Make changes systematically (imports → colors → text → spacing → components)
- Verify with grep checks before committing
- Commit after each successful migration
- Update this file's progress as you go

---

## 📚 REFERENCE FILES

### Design System Documentation
- `/Users/nicplev/lumi_reading_tracker/DESIGN_SYSTEM.md` - Complete design system spec
- `/Users/nicplev/lumi_reading_tracker/lib/screens/design_system_demo_screen.dart` - Live examples

### Design Tokens
- `/Users/nicplev/lumi_reading_tracker/lib/core/theme/app_colors.dart`
- `/Users/nicplev/lumi_reading_tracker/lib/core/theme/lumi_text_styles.dart`
- `/Users/nicplev/lumi_reading_tracker/lib/core/theme/lumi_spacing.dart`
- `/Users/nicplev/lumi_reading_tracker/lib/core/theme/lumi_borders.dart`

### Components
- `/Users/nicplev/lumi_reading_tracker/lib/core/widgets/lumi/lumi_buttons.dart`
- `/Users/nicplev/lumi_reading_tracker/lib/core/widgets/lumi/lumi_card.dart`
- `/Users/nicplev/lumi_reading_tracker/lib/core/widgets/lumi/lumi_input.dart`

### Completed Examples
- `/Users/nicplev/lumi_reading_tracker/lib/screens/parent/parent_profile_screen.dart`
- `/Users/nicplev/lumi_reading_tracker/lib/screens/parent/student_goals_screen.dart`

---

## 💡 TIPS

1. **Read completed screens first** to see patterns
2. **Use design_system_demo_screen.dart** as reference for complex components
3. **Work section by section** - don't try to convert entire file at once
4. **Test after each screen** to ensure functionality isn't broken
5. **Commit frequently** - one screen per commit
6. **Ask for clarification** if unsure about a conversion
7. **Check for .withOpacity()** deprecations and update to `.withValues(alpha:)`

---

## 🚀 QUICK START COMMAND

To resume migration in a new Claude Code session:

```
I need to continue migrating Parent screens to the Lumi Design System.

Please read MIGRATION_STATUS.md to understand the current progress and approach.

Then start migrating the next screen on the list: [screen_name].dart

Follow the migration process exactly as documented in MIGRATION_STATUS.md.
```

---

**Remember:** Quality over speed. Each screen should be 100% migrated with NO hardcoded values remaining before moving to the next.
