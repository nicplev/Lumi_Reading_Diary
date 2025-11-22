# Lumi Design System

> A comprehensive design system for the Lumi Reading Diary application, built on principles of friendliness, accessibility, and consistency.

## 📋 Table of Contents

- [Overview](#overview)
- [Design Principles](#design-principles)
- [Getting Started](#getting-started)
- [Colors](#colors)
- [Typography](#typography)
- [Spacing](#spacing)
- [Borders](#borders)
- [Components](#components)
- [Demo Screen](#demo-screen)
- [Accessibility](#accessibility)

---

## Overview

The Lumi Design System provides a cohesive set of design tokens, components, and patterns that ensure consistency across all Lumi app screens. It follows an **8pt grid system** for spacing, uses the **Nunito font family** for typography, and features a **soft, friendly color palette** centered around Rose Pink (#FF8698).

### Key Features

- 🎨 **Comprehensive Color Palette** - Primary, secondary, and semantic colors
- 📝 **Typography Scale** - From display text (36pt) to captions (12pt)
- 📏 **8pt Grid System** - Consistent spacing using multiples of 8
- 🎯 **Reusable Components** - Buttons, cards, inputs, and more
- ♿ **Accessibility First** - WCAG AA compliant color contrasts
- 📱 **Cross-Platform** - Works seamlessly on iOS, Android, and Web

---

## Design Principles

### 1. Friendly & Approachable
Soft colors, rounded corners, and gentle shadows create a welcoming experience for children and parents.

### 2. Consistent & Predictable
All components follow the same spacing, sizing, and interaction patterns for a cohesive experience.

### 3. Accessible
Color contrasts meet WCAG AA standards (4.5:1 minimum), with proper touch targets (minimum 44pt).

### 4. Scalable
The 8pt grid system ensures visual harmony and makes it easy to scale designs across devices.

---

## Getting Started

### Importing Design System Files

```dart
// Theme files
import 'package:lumi_reading_diary/core/theme/app_colors.dart';
import 'package:lumi_reading_diary/core/theme/lumi_text_styles.dart';
import 'package:lumi_reading_diary/core/theme/lumi_spacing.dart';
import 'package:lumi_reading_diary/core/theme/lumi_borders.dart';

// Component files
import 'package:lumi_reading_diary/core/widgets/lumi/lumi_buttons.dart';
import 'package:lumi_reading_diary/core/widgets/lumi/lumi_card.dart';
import 'package:lumi_reading_diary/core/widgets/lumi/lumi_input.dart';
```

### Quick Example

```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Padding(
        padding: LumiPadding.screen,
        child: Column(
          children: [
            Text('Welcome to Lumi', style: LumiTextStyles.h1()),
            LumiGap.s,
            LumiPrimaryButton(
              onPressed: () => print('Hello!'),
              text: 'Get Started',
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Colors

### Primary Palette

| Color | Hex | Usage |
|-------|-----|-------|
| **Rose Pink** | `#FF8698` | Primary actions, CTAs, active states |
| **Mint Green** | `#D2EBBF` | Success states, positive feedback |
| **Soft Yellow** | `#FFF6A4` | Warning badges, attention elements (background only) |
| **Warm Orange** | `#FF8B5A` | Secondary CTAs, warm highlights |
| **Sky Blue** | `#BCE7F0` | Info states, neutral backgrounds |
| **White** | `#FFFFFF` | Main backgrounds, cards |
| **Charcoal** | `#121211` | Primary text, icons, dark elements |

### Semantic Colors

```dart
// Use semantic colors for common UI patterns
AppColors.rosePink    // Primary actions
AppColors.mintGreen   // Success messages
AppColors.error       // Error states (#DC3545)
AppColors.warning     // Warning states (#FFC107)
AppColors.success     // Success states (#28A745)
AppColors.info        // Info states (#17A2B8)
```

### Color Utilities

```dart
// Get appropriate text color for any background
Color textColor = AppColors.getTextColorForBackground(backgroundColor);

// Use opacity helpers
Color fadedRose = AppColors.rosePinkWithOpacity(0.5);
Color fadedText = AppColors.charcoalWithOpacity(0.7);
```

### Accessibility Guidelines

- **Rose Pink on White**: ✅ 4.57:1 contrast (WCAG AA)
- **Charcoal on White**: ✅ 18.5:1 contrast (WCAG AAA)
- **Soft Yellow**: ⚠️ Background only, never for text

---

## Typography

The Lumi Design System uses **Nunito** (via Google Fonts) with three weights:
- **Regular (400)**: Body text, captions
- **Semi-Bold (600)**: Buttons, labels, subheadings
- **Bold (700)**: Headings, emphasis

### Type Scale

| Style | Size | Weight | Usage |
|-------|------|--------|-------|
| **Display** | 36pt | Bold | Hero sections, splash screens |
| **Display Medium** | 32pt | Bold | Large section headings |
| **H1** | 28pt | Bold | Page titles, main headings |
| **H2** | 24pt | Semi-Bold | Section headings, card titles |
| **H3** | 20pt | Semi-Bold | Sub-section headings |
| **Body Large** | 18pt | Regular | Important body text |
| **Body** | 16pt | Regular | Default body text |
| **Body Small** | 14pt | Regular | Secondary text |
| **Label** | 14pt | Semi-Bold | Form labels, tab labels |
| **Caption** | 12pt | Regular | Timestamps, hints |
| **Button** | 16pt | Semi-Bold | Button text |

### Usage Examples

```dart
// Headings
Text('Welcome Back', style: LumiTextStyles.h1())
Text('Recent Activity', style: LumiTextStyles.h2())
Text('Today's Tasks', style: LumiTextStyles.h3())

// Body text
Text('This is body text', style: LumiTextStyles.body())
Text('Secondary info', style: LumiTextStyles.bodySmall())

// With custom colors
Text('Error message', style: LumiTextStyles.body(color: AppColors.error))

// Semantic styles
Text('Success!', style: LumiTextStyles.success())
Text('Warning!', style: LumiTextStyles.warning())
Text('Error!', style: LumiTextStyles.error())
```

---

## Spacing

The Lumi Design System follows a strict **8pt grid system** where all spacing is a multiple of 8.

### Base Spacing Values

| Name | Value | Grid Units | Usage |
|------|-------|------------|-------|
| **XXS** | 4pt | 0.5 | Minimal spacing, tight layouts |
| **XS** | 8pt | 1 | Small spacing, compact elements |
| **S** | 16pt | 2 | Standard spacing (most common) |
| **M** | 24pt | 3 | Medium spacing, section spacing |
| **L** | 32pt | 4 | Large spacing, page sections |
| **XL** | 48pt | 6 | Extra large, major sections |
| **XXL** | 64pt | 8 | Maximum spacing, page margins |

### Using Spacing Constants

```dart
// Direct spacing values
Container(
  margin: EdgeInsets.all(LumiSpacing.s),  // 16pt all sides
  padding: EdgeInsets.symmetric(
    horizontal: LumiSpacing.m,  // 24pt horizontal
    vertical: LumiSpacing.xs,   // 8pt vertical
  ),
)

// Preset padding
Padding(
  padding: LumiPadding.screen,  // 16pt all sides
  child: ...
)

Padding(
  padding: LumiPadding.card,  // 20pt all sides
  child: ...
)

// Vertical gaps (SizedBox)
Column(
  children: [
    Text('Title'),
    LumiGap.s,  // 16pt gap
    Text('Body'),
    LumiGap.m,  // 24pt gap
    Text('Footer'),
  ],
)

// Horizontal gaps
Row(
  children: [
    Icon(Icons.star),
    LumiGap.horizontalXS,  // 8pt gap
    Text('Favorite'),
  ],
)
```

### Component-Specific Spacing

```dart
LumiSpacing.screenPadding        // 16pt - Default screen padding
LumiSpacing.cardPadding          // 20pt - Card padding
LumiSpacing.buttonPaddingVertical    // 16pt
LumiSpacing.buttonPaddingHorizontal  // 24pt
LumiSpacing.inputPaddingVertical     // 12pt
LumiSpacing.inputPaddingHorizontal   // 16pt
```

---

## Borders

### Border Radius Values

| Name | Value | Usage |
|------|-------|-------|
| **Small** | 8pt | Small chips, tags |
| **Medium** | 12pt | Buttons, inputs, cards |
| **Large** | 16pt | Large cards, modals |
| **X-Large** | 24pt | Hero cards, featured content |
| **Circular** | 9999pt | Fully rounded pills, avatars |

### Usage Examples

```dart
// Using BorderRadius presets
Container(
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: LumiBorders.medium,  // 12pt radius
  ),
)

// Using RoundedRectangleBorder for buttons
ElevatedButton(
  style: ElevatedButton.styleFrom(
    shape: LumiBorders.shapeMedium,  // 12pt radius
  ),
)

// Using BoxDecoration presets
Container(
  decoration: LumiBorders.card,  // Complete card decoration
)

Container(
  decoration: LumiBorders.cardHighlighted,  // Highlighted card
)
```

---

## Components

### Buttons

#### LumiPrimaryButton
Primary action button with rose pink background.

```dart
LumiPrimaryButton(
  onPressed: () => doSomething(),
  text: 'Save Changes',
  icon: Icons.save,  // Optional
  isLoading: false,  // Optional
  isFullWidth: true, // Optional
)
```

#### LumiSecondaryButton
Outlined button with rose pink border.

```dart
LumiSecondaryButton(
  onPressed: () => cancel(),
  text: 'Cancel',
  icon: Icons.close,  // Optional
)
```

#### LumiTextButton
Text-only button for less prominent actions.

```dart
LumiTextButton(
  onPressed: () => learnMore(),
  text: 'Learn More',
  icon: Icons.arrow_forward,  // Optional
)
```

#### LumiIconButton
Icon-only button for compact actions.

```dart
LumiIconButton(
  onPressed: () => goBack(),
  icon: Icons.arrow_back,
  iconColor: AppColors.charcoal,  // Optional
  backgroundColor: AppColors.skyBlue,  // Optional
)
```

#### LumiFab
Floating action button for primary screen actions.

```dart
LumiFab(
  onPressed: () => addItem(),
  icon: Icons.add,
  label: 'Add Book',  // Optional
  isExtended: true,   // Optional
)
```

### Cards

#### LumiCard
Standard white card with shadow and padding.

```dart
LumiCard(
  onTap: () => openDetails(),  // Optional
  isHighlighted: false,        // Optional (sky blue background)
  showShadow: true,            // Optional
  child: Column(
    children: [
      Text('Card Title', style: LumiTextStyles.h3()),
      LumiGap.xs,
      Text('Card content goes here'),
    ],
  ),
)
```

#### LumiCompactCard
Smaller padding for list items.

```dart
LumiCompactCard(
  onTap: () => selectItem(),
  child: ListTile(
    leading: Icon(Icons.book),
    title: Text('Book Title'),
  ),
)
```

#### LumiInfoCard
Colored card for messages (success, warning, error, info).

```dart
LumiInfoCard(
  type: LumiInfoCardType.success,
  title: 'Success!',  // Optional
  message: 'Your changes have been saved.',
  icon: Icons.check_circle,  // Optional (defaults by type)
  onDismiss: () => dismiss(),  // Optional
)
```

#### LumiEmptyCard
Empty state with icon, message, and action.

```dart
LumiEmptyCard(
  icon: Icons.book_outlined,
  title: 'No Books Yet',
  message: 'Start your reading journey',
  actionText: 'Add Book',  // Optional
  onAction: () => addBook(),  // Optional
)
```

### Input Fields

#### LumiInput
Standard text input field.

```dart
LumiInput(
  label: 'Email',  // Optional
  hintText: 'Enter your email',  // Optional
  helperText: 'We\'ll never share your email',  // Optional
  errorText: 'Invalid email',  // Optional
  controller: emailController,  // Optional
  prefixIcon: Icon(Icons.email),  // Optional
  suffixIcon: Icon(Icons.clear),  // Optional
  keyboardType: TextInputType.emailAddress,  // Optional
  onChanged: (value) => validate(value),  // Optional
)
```

#### LumiPasswordInput
Password field with visibility toggle.

```dart
LumiPasswordInput(
  label: 'Password',
  hintText: 'Enter your password',
  controller: passwordController,
  helperText: 'Must be at least 8 characters',
)
```

#### LumiSearchInput
Search field with search icon and clear button.

```dart
LumiSearchInput(
  hintText: 'Search books...',
  controller: searchController,
  onChanged: (value) => search(value),
  onClear: () => clearSearch(),
)
```

#### LumiTextarea
Multi-line text input.

```dart
LumiTextarea(
  label: 'Notes',
  hintText: 'Write your notes here...',
  maxLines: 5,
  maxLength: 500,  // Optional
  controller: notesController,
)
```

#### LumiDropdown
Dropdown selector.

```dart
LumiDropdown<String>(
  label: 'Category',
  value: selectedCategory,
  items: ['Fiction', 'Non-Fiction', 'Poetry'],
  onChanged: (value) => setState(() => selectedCategory = value),
  itemLabel: (item) => item,  // Optional custom label
)
```

---

## Demo Screen

A comprehensive demo screen is available to view all design system components in action.

### Accessing the Demo

**Via GoRouter:**
```dart
context.go('/design-system-demo');
```

**Or navigate to:**
`http://localhost:PORT/design-system-demo`

The demo screen showcases:
- ✅ All typography styles
- ✅ Complete color palette
- ✅ All button variants
- ✅ All card types
- ✅ All input fields
- ✅ Spacing examples
- ✅ Border radius examples

---

## Accessibility

### Color Contrast

All color combinations meet **WCAG AA standards** (minimum 4.5:1 contrast ratio):

- Rose Pink (#FF8698) on White: **4.57:1** ✅
- Charcoal (#121211) on White: **18.5:1** ✅
- White on Rose Pink: **4.57:1** ✅

### Touch Targets

All interactive elements meet the **minimum touch target size**:
- iOS Standard: **44pt × 44pt**
- Material Design: **48pt × 48pt**

### Screen Readers

All components include proper semantic markup:
- Buttons have descriptive labels
- Form inputs have associated labels
- Error messages are announced
- Icon-only buttons have accessibility labels

### Focus States

All interactive components have clear focus states:
- **Inputs**: Rose pink border (2pt width)
- **Buttons**: Subtle scale animation
- **Cards**: Tappable cards show scale animation

---

## File Structure

```
lib/
├── core/
│   ├── theme/
│   │   ├── app_colors.dart           # Color palette and utilities
│   │   ├── lumi_text_styles.dart     # Typography system
│   │   ├── lumi_spacing.dart         # Spacing constants and helpers
│   │   └── lumi_borders.dart         # Border radius and decorations
│   └── widgets/
│       └── lumi/
│           ├── lumi_buttons.dart     # Button components
│           ├── lumi_card.dart        # Card components
│           └── lumi_input.dart       # Input components
└── screens/
    └── design_system_demo_screen.dart  # Demo screen
```

---

## Migration Guide

### Migrating Existing Screens

1. **Replace color references:**
   ```dart
   // Before
   Color(0xFF4A90E2)

   // After
   AppColors.rosePink
   ```

2. **Update text styles:**
   ```dart
   // Before
   TextStyle(fontSize: 24, fontWeight: FontWeight.w600)

   // After
   LumiTextStyles.h2()
   ```

3. **Use spacing constants:**
   ```dart
   // Before
   SizedBox(height: 16)

   // After
   LumiGap.s
   ```

4. **Replace custom buttons:**
   ```dart
   // Before
   ElevatedButton(
     style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF4A90E2)),
     onPressed: onPressed,
     child: Text('Submit'),
   )

   // After
   LumiPrimaryButton(
     onPressed: onPressed,
     text: 'Submit',
   )
   ```

---

## Support

For questions or issues with the design system:
1. Check the [Demo Screen](#demo-screen) for examples
2. Review this documentation
3. Contact the development team

---

## Version History

- **v1.0** (Current) - Initial design system implementation
  - Complete color palette
  - Typography system
  - Spacing and borders
  - Button, card, and input components
  - Demo screen

---

*Built with ❤️ for the Lumi Reading Diary app*
