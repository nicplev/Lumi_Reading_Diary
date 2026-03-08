# Lumi Teacher/Admin UI Specification
## Flutter Implementation Guide

**Version:** 1.0
**Last Updated:** February 2026
**Target Platform:** iOS & Android (Flutter)

---

## Table of Contents
1. [Design System](#design-system)
2. [Navigation Structure](#navigation-structure)
3. [Dashboard Screen](#dashboard-screen)
4. [Classroom Screen](#classroom-screen)
5. [Library Screen](#library-screen)
6. [Settings Screen](#settings-screen)
7. [Profile Screen](#profile-screen)
8. [Student Detail Screen](#student-detail-screen)
9. [Reusable Components](#reusable-components)
10. [Data Models](#data-models)

---

## Design System

### Color Palette

```dart
// lib/core/constants/teacher_colors.dart

class TeacherColors {
  // Primary Colors
  static const Color primary = Color(0xFF5C6BC0);        // Indigo - main teacher theme
  static const Color primaryLight = Color(0xFFC5CAE9);   // Light indigo for backgrounds
  static const Color accent = Color(0xFF7986CB);         // Accent indigo

  // Shared Lumi Colors (from parent app)
  static const Color lumiCoral = Color(0xFFFF8698);
  static const Color lumiPeach = Color(0xFFFFAB91);
  static const Color lumiMint = Color(0xFFBCE7F0);
  static const Color lumiLavender = Color(0xFFD2EBBF);

  // Secondary Colors
  static const Color sunnyYellow = Color(0xFFFFF6A4);
  static const Color skyBlue = Color(0xFF90CAF9);
  static const Color softOrange = Color(0xFFFFCC80);
  static const Color sageGreen = Color(0xFFA5D6A7);

  // Book Type Colors
  static const Color decodableBlue = Color(0xFF64B5F6);
  static const Color libraryGreen = Color(0xFF81C784);

  // Decodable Level/Tier Colors
  static const Color tierRed = Color(0xFFEF9A9A);      // Level 1 - CVC
  static const Color tierOrange = Color(0xFFFFCC80);   // Level 2 - Digraphs
  static const Color tierYellow = Color(0xFFFFF59D);   // Level 3 - Blends
  static const Color tierGreen = Color(0xFFA5D6A7);    // Level 4 - CVCE
  static const Color tierBlue = Color(0xFF90CAF9);     // Level 5 - Vowel Teams
  static const Color tierPurple = Color(0xFFCE93D8);   // Level 6 - R-Controlled

  // Semantic Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFEF5350);

  // Neutrals
  static const Color background = Color(0xFFF5F5F7);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF121211);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
}
```

### Typography

```dart
// lib/core/constants/teacher_typography.dart

class TeacherTypography {
  static const String fontFamily = 'Nunito';

  // Headings
  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: TeacherColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: TeacherColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: TeacherColors.textPrimary,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: TeacherColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: TeacherColors.textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: TeacherColors.textSecondary,
  );

  // Special
  static const TextStyle statValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: TeacherColors.textPrimary,
  );

  static const TextStyle buttonText = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
}
```

### Spacing & Sizing

```dart
// lib/core/constants/teacher_dimensions.dart

class TeacherDimensions {
  // Padding
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 12.0;
  static const double paddingL = 16.0;
  static const double paddingXL = 20.0;
  static const double paddingXXL = 24.0;

  // Border Radius
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 20.0;
  static const double radiusRound = 50.0;

  // Card Shadows
  static BoxShadow cardShadow = BoxShadow(
    color: Colors.black.withOpacity(0.04),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  // Avatar Sizes
  static const double avatarS = 40.0;
  static const double avatarM = 64.0;
  static const double avatarL = 80.0;

  // Icon Sizes
  static const double iconS = 18.0;
  static const double iconM = 24.0;
  static const double iconL = 36.0;
}
```

---

## Navigation Structure

### Bottom Navigation Bar

```
┌─────────────────────────────────────────────┐
│  Dashboard  │  Class  │  Library  │ Settings │
│     📊      │   👥    │    📚     │    ⚙️    │
└─────────────────────────────────────────────┘
```

**Implementation Notes:**
- Use `BottomNavigationBar` with 4 items
- Active state: filled icon + primary color
- Inactive state: outlined icon + textSecondary color
- Label font: Nunito 11px SemiBold

```dart
// Navigation items
final List<BottomNavigationBarItem> navItems = [
  BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
  BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Class'),
  BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Library'),
  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
];
```

---

## Dashboard Screen

### Layout Structure

```
┌─────────────────────────────────────────────┐
│ [Status Bar]                                │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ GRADIENT HEADER                         │ │
│ │ "Good Morning, Ms. Johnson"             │ │
│ │ "Monday, February 22, 2026"             │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐                   │
│ │ 👨‍🎓 24   │ │ ✓ 18    │  ← Stats Row 1    │
│ │ Students │ │ Read     │                   │
│ └──────────┘ └──────────┘                   │
│ ┌──────────┐ ┌──────────┐                   │
│ │ 🔥 12    │ │ 📚 47   │  ← Stats Row 2    │
│ │ Streaks  │ │ Books    │                   │
│ └──────────┘ └──────────┘                   │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ CLASS CARD (Clickable)                  │ │
│ │ "Year 1 Blue"          [24 Students]    │ │
│ │ ████████████░░░░ 75% reading rate       │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ WEEKLY CHART                            │ │
│ │ "Weekly Reading Activity"  [This Week]  │ │
│ │                                         │ │
│ │   █   █   █   █   █                     │ │
│ │   █   █   █   █   █   █                 │ │
│ │   █   █   █   █   █   █   ░             │ │
│ │  Mon Tue Wed Thu Fri Sat Sun            │ │
│ │                                         │ │
│ │     Average: 18/24 students per night   │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ ⚠️ 6 students haven't logged this week │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ [Bottom Navigation]                         │
└─────────────────────────────────────────────┘
```

### Dashboard Header Widget

```dart
// Widget: DashboardHeader
// Location: lib/features/teacher/widgets/dashboard_header.dart

Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [TeacherColors.primary, TeacherColors.accent],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  padding: EdgeInsets.all(20),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Good Morning, Ms. Johnson', style: h2.copyWith(color: Colors.white)),
      SizedBox(height: 4),
      Text('Monday, February 22, 2026', style: bodyMedium.copyWith(color: Colors.white70)),
    ],
  ),
)
```

### Stat Card Widget

```dart
// Widget: StatCard
// Props: icon (Widget), value (String), label (String), iconBgColor (Color), valueColor (Color?)

class StatCard extends StatelessWidget {
  final Widget icon;
  final String value;
  final String label;
  final Color iconBgColor;
  final Color? valueColor;

  // Layout:
  // ┌────────────────┐
  // │ [Icon Box]     │  ← 40x40 rounded container with iconBgColor
  // │                │
  // │ 24             │  ← statValue style, optional valueColor
  // │ Total Students │  ← bodySmall style
  // └────────────────┘
}
```

### Weekly Chart Widget

```dart
// Widget: WeeklyEngagementChart
// Props: data (List<int>), labels (List<String>), maxValue (int)

// Use fl_chart package or custom painter
// Bar colors:
//   - Current/past days: TeacherColors.primary
//   - Today: TeacherColors.accent
//   - Future days: TeacherColors.divider (gray)

// Chart dimensions:
// - Bar width: 32px
// - Bar border radius: 8px top corners
// - Chart height: 120px
// - Gap between bars: auto-distributed
```

---

## Classroom Screen

### Layout Structure

```
┌─────────────────────────────────────────────┐
│ [Status Bar]                                │
├─────────────────────────────────────────────┤
│ "Year 1 Blue"                               │
│ "24 Students • 47 Books Assigned"           │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ 📷 SCANNER CARD (Gradient BG)          │ │
│ │                                         │ │
│ │ "Scan ISBN to Assign Books"             │ │
│ │ "Quickly assign books to students..."   │ │
│ │                                         │ │
│ │        [ Open Scanner ]                 │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ Students                    Sort by: Name ▼ │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ [E] Emma Thompson        🔥 14          │ │
│ │     3 books assigned                    │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ [L] Liam Chen            🔥 8           │ │
│ │     2 books assigned                    │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ [O] Olivia Martinez      🔥 21          │ │
│ │     2 books assigned                    │ │
│ └─────────────────────────────────────────┘ │
│                  ...                        │
├─────────────────────────────────────────────┤
│ [Bottom Navigation]                         │
└─────────────────────────────────────────────┘
```

### ISBN Scanner Card Widget

```dart
// Widget: ISBNScannerCard
// Gradient background: primary → accent

Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [TeacherColors.primary, TeacherColors.accent],
    ),
    borderRadius: BorderRadius.circular(20),
  ),
  padding: EdgeInsets.all(24),
  child: Column(
    children: [
      // Circular icon container (64x64)
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.qr_code_scanner, size: 28, color: Colors.white),
      ),
      SizedBox(height: 16),
      Text('Scan ISBN to Assign Books', style: h3.copyWith(color: Colors.white)),
      SizedBox(height: 8),
      Text('Quickly assign books...', style: bodyMedium.copyWith(color: Colors.white70)),
      SizedBox(height: 16),
      // White button
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: TeacherColors.primary,
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        ),
        onPressed: () => _openScanner(),
        child: Text('Open Scanner', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  ),
)
```

### Student List Item Widget

```dart
// Widget: StudentListItem
// Props: student (Student), onTap (VoidCallback)

// Layout:
// ┌─────────────────────────────────────────────────┐
// │ [Avatar]  Name                      🔥 Streak  │
// │           X books assigned                      │
// └─────────────────────────────────────────────────┘

class StudentListItem extends StatelessWidget {
  // Avatar: 40x40 circle with student's initial
  // Avatar color: assigned based on first letter or student ID
  // Name: bodyMedium, fontWeight 600
  // Books assigned: bodySmall, textSecondary
  // Streak: softOrange color with fire emoji, or "—" if no streak

  // Container styling:
  // - Background: cardWhite
  // - Border radius: 12
  // - Padding: 14 horizontal, 16 vertical
  // - Box shadow: cardShadow
  // - On hover/tap: background changes to primaryLight
}
```

---

## Library Screen

### Layout Structure

```
┌─────────────────────────────────────────────┐
│ [Status Bar]                                │
├─────────────────────────────────────────────┤
│ "Book Library"                              │
│ "156 Decodable Books Available"             │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ 🔍 Search books...                      │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ [All] [Decodable] [Library] [Recently Added]│  ← Horizontal scroll chips
├─────────────────────────────────────────────┤
│ 🔴 Level 1 - CVC Words (24 books)           │
│ ┌────┐ ┌────┐ ┌────┐                        │
│ │Book│ │Book│ │Book│  ← 3-column grid       │
│ │Sam │ │Hop │ │Big │                        │
│ └────┘ └────┘ └────┘                        │
├─────────────────────────────────────────────┤
│ 🟡 Level 2 - Digraphs (32 books)            │
│ ┌────┐ ┌────┐ ┌────┐                        │
│ │Book│ │Book│ │Book│                        │
│ │Ship│ │Chip│ │Fish│                        │
│ └────┘ └────┘ └────┘                        │
├─────────────────────────────────────────────┤
│ 🟢 Level 3 - Blends (28 books)              │
│ ┌────┐ ┌────┐ ┌────┐                        │
│ │Book│ │Book│ │Book│                        │
│ │Frog│ │Drum│ │Clap│                        │
│ └────┘ └────┘ └────┘                        │
├─────────────────────────────────────────────┤
│ [Bottom Navigation]                         │
└─────────────────────────────────────────────┘
```

### Decodable Levels Reference

| Level | Name | Color | Example Words |
|-------|------|-------|---------------|
| 1 | CVC Words | `tierRed` #EF9A9A | cat, hop, big |
| 2 | Digraphs | `tierOrange` #FFCC80 | ship, chip, fish |
| 3 | Blends | `tierYellow` #FFF59D | frog, drum, clap |
| 4 | CVCE (Magic E) | `tierGreen` #A5D6A7 | cake, bike, home |
| 5 | Vowel Teams | `tierBlue` #90CAF9 | rain, boat, team |
| 6 | R-Controlled | `tierPurple` #CE93D8 | car, her, bird |

### Filter Chip Widget

```dart
// Widget: FilterChip (custom, not Material)
// Props: label (String), isActive (bool), onTap (VoidCallback)

Container(
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  decoration: BoxDecoration(
    color: isActive ? TeacherColors.primary : TeacherColors.cardWhite,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: isActive ? TeacherColors.primary : Colors.transparent,
      width: 2,
    ),
  ),
  child: Text(
    label,
    style: TextStyle(
      color: isActive ? Colors.white : TeacherColors.textSecondary,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
  ),
)
```

### Book Grid Item Widget

```dart
// Widget: BookGridItem
// Props: book (Book), onTap (VoidCallback)

// Layout:
// ┌──────────────┐
// │  [Cover]     │  ← Gradient placeholder or actual image
// │              │     Height: 80px, full width
// │              │
// ├──────────────┤
// │ Book Title   │  ← 11px, fontWeight 600, max 2 lines
// └──────────────┘

// Container:
// - Background: cardWhite
// - Border radius: 12
// - Padding: 10
// - On tap: navigate to book detail or show assign modal
```

### Tier Section Widget

```dart
// Widget: TierSection
// Props: level (int), name (String), color (Color), bookCount (int), books (List<Book>)

Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Header row
    Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: 10),
        Text('Level $level - $name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        SizedBox(width: 8),
        Text('($bookCount books)', style: TextStyle(color: textSecondary, fontSize: 13)),
      ],
    ),
    SizedBox(height: 12),
    // 3-column grid
    GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) => BookGridItem(book: books[index]),
    ),
  ],
)
```

---

## Settings Screen

### Layout Structure

```
┌─────────────────────────────────────────────┐
│ [Status Bar]                                │
├─────────────────────────────────────────────┤
│ "Settings"                                  │
├─────────────────────────────────────────────┤
│ ┌─ CLASSROOM ─────────────────────────────┐ │
│ │ 🏫 Manage Classes                    ›  │ │
│ │ 👨‍🎓 Student Management               ›  │ │
│ │ 📚 Book Levels                       ›  │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ┌─ NOTIFICATIONS ─────────────────────────┐ │
│ │ 🔔 Push Notifications            [ON]  │ │
│ │ 📧 Email Summaries               [ON]  │ │
│ │ ⚠️ Inactivity Alerts             [ON]  │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ┌─ APP ───────────────────────────────────┐ │
│ │ 🌙 Dark Mode                     [OFF] │ │
│ │ 🔒 Privacy & Security                ›  │ │
│ │ ❓ Help & Support                    ›  │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│            [ Log Out ]                      │
├─────────────────────────────────────────────┤
│ [Bottom Navigation]                         │
└─────────────────────────────────────────────┘
```

### Settings Section Widget

```dart
// Widget: SettingsSection
// Props: title (String), items (List<SettingsItem>)

Container(
  decoration: BoxDecoration(
    color: TeacherColors.cardWhite,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    children: [
      // Header
      Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: TeacherColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: TeacherColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ),
      // Items
      ...items.map((item) => SettingsItemTile(item: item)),
    ],
  ),
)
```

### Settings Item Widget

```dart
// Widget: SettingsItemTile
// Props: icon (IconData), iconBgColor (Color), label (String),
//        trailing (Widget - either arrow or toggle), onTap (VoidCallback)

ListTile(
  leading: Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: iconBgColor,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: iconColor),
  ),
  title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
  trailing: trailing, // Either Icon(Icons.chevron_right) or CustomToggle
  onTap: onTap,
)
```

---

## Profile Screen

### Layout Structure

```
┌─────────────────────────────────────────────┐
│ [Status Bar]                                │
├─────────────────────────────────────────────┤
│ "Profile"                                   │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │           [SJ]  ← 80px avatar           │ │
│ │                                         │ │
│ │      Sarah Johnson                      │ │
│ │  Year 1 Teacher • Oakwood Primary       │ │
│ │                                         │ │
│ │   24        156        89%              │ │
│ │ Students   Books    Engagement          │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ This Term's Progress                    │ │
│ │ ┌──────────┐ ┌──────────┐               │ │
│ │ │  1,247   │ │    52    │               │ │
│ │ │ Sessions │ │   Days   │               │ │
│ │ └──────────┘ └──────────┘               │ │
│ │ 🎉 Top 10% for reading consistency!     │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ ✏️ Edit Profile                      ›  │ │
│ │ 🏫 School Settings                   ›  │ │
│ │ 📊 Export Reports                    ›  │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ [Bottom Navigation]                         │
└─────────────────────────────────────────────┘
```

### Profile Card Widget

```dart
// Widget: ProfileCard
// Props: teacher (Teacher)

Container(
  padding: EdgeInsets.all(24),
  decoration: BoxDecoration(
    color: TeacherColors.cardWhite,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [TeacherDimensions.cardShadow],
  ),
  child: Column(
    children: [
      // Avatar (80x80 with gradient)
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [TeacherColors.primary, TeacherColors.accent]),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text('SJ', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
      SizedBox(height: 16),
      Text('Sarah Johnson', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      SizedBox(height: 4),
      Text('Year 1 Teacher • Oakwood Primary', style: TextStyle(color: textSecondary, fontSize: 14)),
      SizedBox(height: 16),
      // Stats row
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ProfileStat(value: '24', label: 'Students'),
          SizedBox(width: 32),
          _ProfileStat(value: '156', label: 'Books'),
          SizedBox(width: 32),
          _ProfileStat(value: '89%', label: 'Engagement'),
        ],
      ),
    ],
  ),
)
```

---

## Student Detail Screen

### Layout Structure

```
┌─────────────────────────────────────────────┐
│ [Status Bar]                                │
├─────────────────────────────────────────────┤
│ ← Back                                      │
├─────────────────────────────────────────────┤
│ [E]  Emma Thompson                          │
│      Year 1 Blue                            │
├─────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐                   │
│ │ 🔥 14    │ │    47    │                   │
│ │Day Streak│ │Total Nts │                   │
│ └──────────┘ └──────────┘                   │
├─────────────────────────────────────────────┤
│ Assigned Books              [+ Assign]      │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ [Cover] Sam the Cat           ✓         │ │
│ │         Level 1 - CVC  [Decodable]      │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ [Cover] The Big Fish     In progress    │ │
│ │         Level 2  [Decodable]            │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ [Cover] Where the Wild...    New        │ │
│ │         Maurice Sendak  [Library]       │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ Latest Parent Comment                       │
│ ┌─────────────────────────────────────────┐ │
│ │ "Emma read beautifully tonight! She     │ │
│ │  sounded out all the tricky words..."   │ │
│ │                    — Parent • Yesterday │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Book Assignment Card Widget

```dart
// Widget: BookAssignmentCard
// Props: book (AssignedBook), status (BookStatus)

Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: TeacherColors.cardWhite,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [TeacherDimensions.cardShadow],
  ),
  child: Row(
    children: [
      // Book cover (50x70)
      Container(
        width: 50, height: 70,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: book.coverGradient),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      SizedBox(width: 12),
      // Book details
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            SizedBox(height: 2),
            Text(book.subtitle, style: TextStyle(color: textSecondary, fontSize: 12)),
            SizedBox(height: 6),
            BookTypeBadge(type: book.type), // Decodable or Library
          ],
        ),
      ),
      // Status indicator
      _StatusIndicator(status: status), // ✓, "In progress", or "New"
    ],
  ),
)
```

---

## Reusable Components

### Alert Banner Widget

```dart
// Widget: AlertBanner
// Props: message (String), type (AlertType - warning or success), icon (IconData or emoji)

Container(
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  decoration: BoxDecoration(
    color: type == AlertType.warning ? Color(0xFFFFF3E0) : Color(0xFFE8F5E9),
    borderRadius: BorderRadius.only(
      topRight: Radius.circular(12),
      bottomRight: Radius.circular(12),
    ),
    border: Border(
      left: BorderSide(
        color: type == AlertType.warning ? TeacherColors.softOrange : TeacherColors.sageGreen,
        width: 4,
      ),
    ),
  ),
  child: Row(
    children: [
      Text(icon, style: TextStyle(fontSize: 20)),
      SizedBox(width: 12),
      Expanded(child: Text(message, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
    ],
  ),
)
```

### Book Type Badge Widget

```dart
// Widget: BookTypeBadge
// Props: type (BookType - decodable or library)

Container(
  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: type == BookType.decodable ? Color(0xFFE3F2FD) : Color(0xFFE8F5E9),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    type == BookType.decodable ? 'Decodable' : 'Library',
    style: TextStyle(
      color: type == BookType.decodable ? Color(0xFF1976D2) : Color(0xFF388E3C),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  ),
)
```

### Primary Action Button

```dart
// Widget: PrimaryActionButton
// Props: label (String), icon (IconData?), onPressed (VoidCallback), isSecondary (bool)

ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: isSecondary ? TeacherColors.background : TeacherColors.primary,
    foregroundColor: isSecondary ? TeacherColors.primary : Colors.white,
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    elevation: 0,
  ),
  onPressed: onPressed,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[Icon(icon, size: 20), SizedBox(width: 8)],
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    ],
  ),
)
```

---

## Data Models

```dart
// lib/features/teacher/models/

class Teacher {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String schoolName;
  final String role; // e.g., "Year 1 Teacher"
  final List<String> classIds;

  String get initials => '${firstName[0]}${lastName[0]}';
  String get fullName => '$firstName $lastName';
}

class ClassRoom {
  final String id;
  final String name; // e.g., "Year 1 Blue"
  final String teacherId;
  final List<String> studentIds;
  final int totalBooks;

  int get studentCount => studentIds.length;
}

class Student {
  final String id;
  final String firstName;
  final String lastName;
  final String classId;
  final int currentStreak;
  final int totalReadingNights;
  final List<String> assignedBookIds;
  final Color avatarColor;

  String get initial => firstName[0].toUpperCase();
  String get fullName => '$firstName $lastName';
}

class Book {
  final String id;
  final String title;
  final String? author;
  final String isbn;
  final BookType type; // decodable or library
  final int? decodableLevel; // 1-6 for decodable books
  final String? levelName; // "CVC Words", "Digraphs", etc.
  final List<Color> coverGradient;
}

enum BookType { decodable, library }

class AssignedBook {
  final String id;
  final String bookId;
  final String studentId;
  final DateTime assignedDate;
  final BookStatus status;
  final DateTime? completedDate;
}

enum BookStatus { new_, inProgress, completed }

class ReadingSession {
  final String id;
  final String studentId;
  final String bookId;
  final DateTime date;
  final String? parentComment;
  final int? feelingRating; // 1-5
}

class DashboardStats {
  final int totalStudents;
  final int readLastNight;
  final int onStreak; // 7+ day streak
  final int totalBooksAssigned;
  final List<int> weeklyEngagement; // 7 values for Mon-Sun
}
```

---

## File Structure Recommendation

```
lib/
├── core/
│   ├── constants/
│   │   ├── teacher_colors.dart
│   │   ├── teacher_typography.dart
│   │   └── teacher_dimensions.dart
│   └── widgets/
│       ├── alert_banner.dart
│       ├── book_type_badge.dart
│       └── primary_action_button.dart
│
├── features/
│   └── teacher/
│       ├── models/
│       │   ├── teacher.dart
│       │   ├── classroom.dart
│       │   ├── student.dart
│       │   └── book.dart
│       ├── screens/
│       │   ├── teacher_dashboard_screen.dart
│       │   ├── classroom_screen.dart
│       │   ├── library_screen.dart
│       │   ├── settings_screen.dart
│       │   ├── profile_screen.dart
│       │   └── student_detail_screen.dart
│       ├── widgets/
│       │   ├── dashboard_header.dart
│       │   ├── stat_card.dart
│       │   ├── class_card.dart
│       │   ├── weekly_chart.dart
│       │   ├── isbn_scanner_card.dart
│       │   ├── student_list_item.dart
│       │   ├── filter_chip.dart
│       │   ├── tier_section.dart
│       │   ├── book_grid_item.dart
│       │   ├── settings_section.dart
│       │   ├── profile_card.dart
│       │   └── book_assignment_card.dart
│       └── providers/
│           └── teacher_provider.dart
```

---

## Implementation Notes

1. **State Management:** Consider using Riverpod or Provider for state management across teacher screens.

2. **ISBN Scanning:** Use `mobile_scanner` or `flutter_barcode_scanner` package for ISBN scanning functionality.

3. **Charts:** Use `fl_chart` package for the weekly engagement bar chart.

4. **Navigation:** Use `go_router` for declarative routing between screens.

5. **Responsive Design:** These specs are for mobile-first. For tablet, consider a side navigation rail and wider content areas.

6. **Animations:** Add subtle animations for list items, card taps, and screen transitions using Flutter's built-in animation widgets.

7. **Accessibility:** Ensure all interactive elements have semantic labels and sufficient contrast ratios.

---

*End of Specification*
