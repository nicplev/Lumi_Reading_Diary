# Lumi Reading Diary — Design System Overhaul

This file is the working brief for the Lumi UI overhaul. Read it at session start, follow the rules in Part A on every change, and use Part B once to scaffold the foundation files. Part C is the migration plan — refactor screen by screen, never the whole app at once.

---

## Project context

Lumi is a digital home-reading diary for Australian primary schools. It replaces the paper reading journal that travels in school bags. Parents log a nightly read in under 30 seconds (no typing). Teachers see a live class dashboard with engagement charts and nudges. Kids stay motivated by a red flame mascot called Lumi, plus streaks, badges, and a library of selectable profile pictures.

Stack: Flutter (Dart), Firebase (Firestore + Auth + Functions). Australian English throughout.

---

# PART A — Rules

These are non-negotiable. Re-read before every UI change.

## A1. Colour as section theme, not semantic role

The four brand colours map to app sections, not to semantic categories. Each screen takes one colour as its theme — headers, primary CTAs, active nav, and key UI elements use it. Other colours appear only as accents.

**Teacher app — 4 sections:**

| Section | Colour | Hex | Use |
|---|---|---|---|
| Dashboard | Lumi Blue | `#56C8E6` | Live engagement, charts, nudges |
| Class | Lumi Red | `#EC4544` | Students, reading groups, daily activity |
| Library | Lumi Yellow | `#FFCB05` | Decodables, levelled readers, ISBN scanner |
| Settings | Lumi Green | `#51BA65` | Account, school config, notifications |

**Parent app — 3 sections:**

| Section | Colour | Hex | Use |
|---|---|---|---|
| Home | Lumi Red | `#EC4544` | Tonight's read, streak, mood logging |
| Library | Lumi Yellow | `#FFCB05` | Assigned books, child's reading history |
| Settings | Lumi Green | `#51BA65` | Reminders, multi-child, account |

Blue isn't used in the parent app — analytics live with the teacher.

## A2. Never hard-code colours

Always pull from `LumiTokens` or the active `LumiSectionTheme`. If you find yourself writing `Color(0xFF...)` in a widget, stop and add a token instead. If a colour you need isn't in the system, raise it for discussion before introducing it.

## A3. Always use design-system widgets

Buttons, chips, cards, mood selector, streak counter, badges — these all live in `lib/design_system/`. Never reach for raw `ElevatedButton`, `Card`, or `Container` with custom styling when a Lumi widget exists. If one doesn't exist for what you need, add it to `lib/design_system/` rather than styling inline.

## A4. Typography

Two faces in conversation:

- **Display / headings:** Nunito ExtraBold (weight 800). Tight letter-spacing. Used for the wordmark, big numbers, headings, button labels.
- **Body / long-form:** Helvetica Neue Thin if licensed; otherwise Inter Light (weight 300) as a free cross-platform substitute. Loaded via `google_fonts`.

Type scale lives in `LumiType`. Use those styles directly; don't hand-roll `TextStyle` objects in screens.

## A5. The Lumi mascot

- The red flame is the default. It anchors the brand everywhere — wordmark dot, splash, streak counter, loading states.
- The seven other colour variants exist only to display the colour palette and show the mascot from different angles. They aren't separate characters and don't have names.
- Costumes (8) and animal characters (7) are selectable profile pictures. They aren't rewards earned through gameplay.
- Specific in-app poses, expressions, and animations are still being designed. The contextual illustrations (Lumi with books, with trophy, with open book) are the early-stage assets available today. Expect this library to grow — don't bake assumptions about pose count into widget APIs.
- Lumi celebrates but never delivers bad news, errors, or teacher nudges. Errors are written in the interface voice, not spoken by the mascot.

## A6. Product principles to honour

1. **The physical book is sacred.** The app tracks reading — it doesn't replace it. Get parent and child back to the paperback as quickly as possible.
2. **Thirty seconds, no typing.** Logging is tap-only: book → mood → chips → save. Keyboard is for setup, not nightly use.
3. **Cheer, don't shame.** Streaks include rest days. Missed nights don't punish. Teacher nudges go to teachers, never to kids.
4. **Teachers see, parents do.** Parent app is small, calm, focused on tonight. Teacher dashboard is wide, data-dense, built for thirty students.

## A7. Voice

- Buttons: imperative and specific. **"Log tonight's read"**, not "Submit reading entry".
- Celebrations: declarative and grounded. **"16 nights in a row. That's a record."**, not "Congratulations! You have reached a streak milestone!"
- Errors: calm, factual, never blaming. **"Saved on your phone. We'll sync when you're back online."**, not "Network error. Unable to upload data to server."
- Australian English spelling everywhere. `colour`, `organised`, `centre`.

---

# PART B — Foundation files to create

Create these files first, in this order. They're the foundation everything else builds on.

## B1. `pubspec.yaml` additions

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.2.1

flutter:
  uses-material-design: true
  assets:
    - assets/mascot/flames/
    - assets/mascot/costumes/
    - assets/mascot/friends/
    - assets/mascot/contextual/
    - assets/mascot/moods/
```

Asset folder layout (place the PNG files Nic has on hand):

```
assets/mascot/
├── flames/         red.png, orange.png, yellow.png, green.png,
│                   light_blue.png, dark_blue.png, purple.png, pink.png
├── costumes/       crown.png, wizard.png, pirate.png, astronaut.png,
│                   chef.png, cap.png, ninja.png, dj.png
├── friends/        penguin.png, tiger.png, pig.png, cat.png,
│                   frog.png, shark.png, bear.png
├── contextual/     default.png, with_books.png, with_open_book.png, with_trophy.png
└── moods/          hard.png, tricky.png, okay.png, good.png, great.png
```

Rename the PNGs to lowercase snake_case as you drop them in.

## B2. `lib/theme/lumi_tokens.dart`

```dart
import 'package:flutter/material.dart';

/// Lumi design tokens — single source of truth for the brand.
/// Never hard-code colours, spacing, or radii in widgets — pull from here.
class LumiTokens {
  LumiTokens._();

  // ─── Primary palette — section theme colours ─────────────────────
  /// Class (teacher) / Home (parent). Also the mascot's default colour.
  static const Color red    = Color(0xFFEC4544);
  /// Library section, achievements, rest-day indicators.
  static const Color yellow = Color(0xFFFFCB05);
  /// Settings section, confirmation states.
  static const Color green  = Color(0xFF51BA65);
  /// Dashboard (teacher only), data viz and analytics.
  static const Color blue   = Color(0xFF56C8E6);

  // ─── Extended palette — mascot colour variants only ───────────────
  // Never used for product UI chrome.
  static const Color orange = Color(0xFFFAA51A);
  static const Color indigo = Color(0xFF1989CA);
  static const Color purple = Color(0xFFA571B0);
  static const Color pink   = Color(0xFFF5A1C5);

  // ─── Tints — lightest acceptable use of brand colour ──────────────
  // Used for soft backgrounds, badge fills, selected-state highlights.
  static const Color tintRed    = Color(0xFFF4B5B7);
  static const Color tintYellow = Color(0xFFFBE89F);
  static const Color tintGreen  = Color(0xFFB5DAB8);
  static const Color tintBlue   = Color(0xFFC8E8F1);
  static const Color tintOrange = Color(0xFFFED8A8);

  // ─── Neutrals ─────────────────────────────────────────────────────
  /// Primary background. Warm, paperback-page feel.
  static const Color cream    = Color(0xFFF7F5F0);
  /// Card and surface fill on cream.
  static const Color paper    = Color(0xFFFFFFFF);
  /// Primary text. Never pure black.
  static const Color ink      = Color(0xFF1A1A1A);
  /// Slightly lighter than ink, for dark surfaces.
  static const Color charcoal = Color(0xFF2A2A2A);
  /// Secondary text, captions, metadata.
  static const Color muted    = Color(0xFF6B6B6B);
  /// Borders and dividers. Warm grey, not cool.
  static const Color rule     = Color(0xFFE5E2DC);

  // ─── Spacing (4pt baseline) ───────────────────────────────────────
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;
  static const double space8 = 64;

  // ─── Corner radii ─────────────────────────────────────────────────
  static const double radiusSmall  = 8;
  static const double radiusMedium = 14;
  static const double radiusLarge  = 18;
  static const double radiusXL     = 24;
  static const double radiusPill   = 999;

  // ─── Elevation shadows ────────────────────────────────────────────
  static List<BoxShadow> get shadowCard => const [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static List<BoxShadow> get shadowFloat => const [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}
```

## B3. `lib/theme/lumi_typography.dart`

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'lumi_tokens.dart';

/// Lumi typography — Nunito ExtraBold for display, Inter (or Helvetica Neue
/// if licensed and bundled) for body. Always use these styles; never
/// construct ad-hoc TextStyles in screens.
class LumiType {
  LumiType._();

  // ─── Display & headings — Nunito ExtraBold (800) ──────────────────
  static TextStyle get displayXL => GoogleFonts.nunito(
    fontSize: 64, fontWeight: FontWeight.w800,
    letterSpacing: -2.56, height: 1.0, color: LumiTokens.ink,
  );

  static TextStyle get displayL => GoogleFonts.nunito(
    fontSize: 44, fontWeight: FontWeight.w800,
    letterSpacing: -0.88, height: 1.05, color: LumiTokens.ink,
  );

  static TextStyle get heading => GoogleFonts.nunito(
    fontSize: 28, fontWeight: FontWeight.w700,
    letterSpacing: -0.28, height: 1.2, color: LumiTokens.ink,
  );

  static TextStyle get subhead => GoogleFonts.nunito(
    fontSize: 20, fontWeight: FontWeight.w700,
    height: 1.3, color: LumiTokens.ink,
  );

  // ─── Body — Inter Light (300) as cross-platform substitute ────────
  // Swap to Helvetica Neue Thin once licensed and bundled.
  static TextStyle get bodyL => GoogleFonts.inter(
    fontSize: 18, fontWeight: FontWeight.w300,
    height: 1.55, color: LumiTokens.ink,
  );

  static TextStyle get body => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w300,
    height: 1.55, color: LumiTokens.ink,
  );

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w400,
    height: 1.4, color: LumiTokens.muted,
  );

  // ─── Button text — Nunito 700 ─────────────────────────────────────
  static TextStyle get button => GoogleFonts.nunito(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: LumiTokens.paper,
  );

  // ─── Section labels — uppercase mono ──────────────────────────────
  static TextStyle get sectionLabel => GoogleFonts.jetBrainsMono(
    fontSize: 12, fontWeight: FontWeight.w500,
    letterSpacing: 0.96, color: LumiTokens.muted,
  );

  // ─── Big numbers (streak counter, scores) — Nunito 800 ────────────
  static TextStyle get numberLarge => GoogleFonts.nunito(
    fontSize: 42, fontWeight: FontWeight.w800,
    letterSpacing: -0.84, height: 1.0, color: LumiTokens.ink,
  );
}
```

## B4. `lib/theme/section_theme.dart`

```dart
import 'package:flutter/material.dart';
import 'lumi_tokens.dart';

/// Identifies which section of the app a screen belongs to.
enum LumiSection { home, classScreen, library, settings, dashboard }

/// Per-screen theme extension. Each screen wraps itself in `LumiSectionScope`
/// to declare its section; widgets then read the accent colour via
/// `context.sectionTheme` rather than hard-coding any colour.
@immutable
class LumiSectionTheme extends ThemeExtension<LumiSectionTheme> {
  final LumiSection section;
  final Color accent;
  final Color accentTint;
  final Color onAccent;

  const LumiSectionTheme({
    required this.section,
    required this.accent,
    required this.accentTint,
    required this.onAccent,
  });

  // ─── Per-section factories ────────────────────────────────────────
  static const LumiSectionTheme home = LumiSectionTheme(
    section: LumiSection.home,
    accent: LumiTokens.red,
    accentTint: LumiTokens.tintRed,
    onAccent: LumiTokens.paper,
  );

  static const LumiSectionTheme classScreen = LumiSectionTheme(
    section: LumiSection.classScreen,
    accent: LumiTokens.red,
    accentTint: LumiTokens.tintRed,
    onAccent: LumiTokens.paper,
  );

  static const LumiSectionTheme library = LumiSectionTheme(
    section: LumiSection.library,
    accent: LumiTokens.yellow,
    accentTint: LumiTokens.tintYellow,
    onAccent: LumiTokens.ink,
  );

  static const LumiSectionTheme settings = LumiSectionTheme(
    section: LumiSection.settings,
    accent: LumiTokens.green,
    accentTint: LumiTokens.tintGreen,
    onAccent: LumiTokens.paper,
  );

  static const LumiSectionTheme dashboard = LumiSectionTheme(
    section: LumiSection.dashboard,
    accent: LumiTokens.blue,
    accentTint: LumiTokens.tintBlue,
    onAccent: LumiTokens.ink,
  );

  @override
  LumiSectionTheme copyWith({
    LumiSection? section,
    Color? accent,
    Color? accentTint,
    Color? onAccent,
  }) {
    return LumiSectionTheme(
      section: section ?? this.section,
      accent: accent ?? this.accent,
      accentTint: accentTint ?? this.accentTint,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  LumiSectionTheme lerp(LumiSectionTheme? other, double t) {
    if (other is! LumiSectionTheme) return this;
    return LumiSectionTheme(
      section: t < 0.5 ? section : other.section,
      accent: Color.lerp(accent, other.accent, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

/// Convenience accessor: `context.sectionTheme.accent`
extension LumiSectionThemeContext on BuildContext {
  LumiSectionTheme get sectionTheme =>
      Theme.of(this).extension<LumiSectionTheme>() ?? LumiSectionTheme.home;
}

/// Wrap a screen's root widget in this to declare its section theme.
/// Widgets within can then read accent colours from `context.sectionTheme`.
class LumiSectionScope extends StatelessWidget {
  final LumiSectionTheme section;
  final Widget child;

  const LumiSectionScope({
    super.key,
    required this.section,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(extensions: [section]),
      child: child,
    );
  }
}
```

## B5. `lib/theme/lumi_theme.dart`

```dart
import 'package:flutter/material.dart';
import 'lumi_tokens.dart';
import 'lumi_typography.dart';
import 'section_theme.dart';

class LumiTheme {
  LumiTheme._();

  /// The base ThemeData. Apply this at MaterialApp level.
  /// Individual screens override the section via LumiSectionScope.
  static ThemeData base() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: LumiTokens.cream,

      colorScheme: const ColorScheme.light(
        primary: LumiTokens.red,
        onPrimary: LumiTokens.paper,
        secondary: LumiTokens.ink,
        onSecondary: LumiTokens.paper,
        surface: LumiTokens.paper,
        onSurface: LumiTokens.ink,
        surfaceContainerLowest: LumiTokens.cream,
        surfaceContainerLow: LumiTokens.paper,
        error: LumiTokens.red,
        onError: LumiTokens.paper,
        outline: LumiTokens.rule,
        outlineVariant: LumiTokens.rule,
      ),

      textTheme: TextTheme(
        displayLarge: LumiType.displayXL,
        displayMedium: LumiType.displayL,
        headlineLarge: LumiType.heading,
        headlineMedium: LumiType.subhead,
        titleLarge: LumiType.subhead,
        bodyLarge: LumiType.bodyL,
        bodyMedium: LumiType.body,
        labelLarge: LumiType.button,
        labelMedium: LumiType.sectionLabel,
        labelSmall: LumiType.caption,
      ),

      dividerColor: LumiTokens.rule,

      // Default section: Home (red). Screens override with LumiSectionScope.
      extensions: const [LumiSectionTheme.home],
    );
  }
}
```

Wire it up in `main.dart`:

```dart
MaterialApp(
  theme: LumiTheme.base(),
  // ...
)
```

## B6. `lib/design_system/lumi_mascot.dart`

```dart
import 'package:flutter/material.dart';

// ─── Enums — every mascot variation the app can render ─────────────
enum LumiColour { red, orange, yellow, green, lightBlue, darkBlue, purple, pink }
enum LumiCostume { crown, wizard, pirate, astronaut, chef, cap, ninja, dj }
enum LumiFriend { penguin, tiger, pig, cat, frog, shark, bear }
enum LumiContext { defaultPose, withBooks, withOpenBook, withTrophy }
enum LumiMood { hard, tricky, okay, good, great }

/// Unified widget for displaying any Lumi mascot variation.
///
/// Use named constructors:
///   LumiMascot.flame(LumiColour.red)
///   LumiMascot.mood(LumiMood.great)
///   LumiMascot.costume(LumiCostume.crown)
///   LumiMascot.friend(LumiFriend.penguin)
///   LumiMascot.contextual(LumiContext.withBooks)
class LumiMascot extends StatelessWidget {
  final String _asset;
  final double? height;
  final double? width;
  final String? semanticLabel;

  const LumiMascot._({
    required String asset,
    this.height,
    this.width,
    this.semanticLabel,
  }) : _asset = asset;

  LumiMascot.flame(LumiColour colour, {double? size, String? label, super.key})
      : _asset = 'assets/mascot/flames/${_flame(colour)}.png',
        height = size,
        width = null,
        semanticLabel = label ?? 'Lumi mascot';

  LumiMascot.mood(LumiMood mood, {double? size, super.key})
      : _asset = 'assets/mascot/moods/${_mood(mood)}.png',
        height = size,
        width = null,
        semanticLabel = _moodLabel(mood);

  LumiMascot.costume(LumiCostume costume, {double? size, super.key})
      : _asset = 'assets/mascot/costumes/${_costume(costume)}.png',
        height = size,
        width = null,
        semanticLabel = 'Lumi as ${_costumeLabel(costume)}';

  LumiMascot.friend(LumiFriend friend, {double? size, super.key})
      : _asset = 'assets/mascot/friends/${_friend(friend)}.png',
        height = size,
        width = null,
        semanticLabel = 'Lumi as ${_friendLabel(friend)}';

  LumiMascot.contextual(LumiContext context_, {double? size, super.key})
      : _asset = 'assets/mascot/contextual/${_context(context_)}.png',
        height = size,
        width = null,
        semanticLabel = 'Lumi';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      height: height ?? 80,
      width: width,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
    );
  }

  // ─── Filename mappers ───────────────────────────────────────────
  static String _flame(LumiColour c) => switch (c) {
    LumiColour.red       => 'red',
    LumiColour.orange    => 'orange',
    LumiColour.yellow    => 'yellow',
    LumiColour.green     => 'green',
    LumiColour.lightBlue => 'light_blue',
    LumiColour.darkBlue  => 'dark_blue',
    LumiColour.purple    => 'purple',
    LumiColour.pink      => 'pink',
  };

  static String _mood(LumiMood m) => switch (m) {
    LumiMood.hard   => 'hard',
    LumiMood.tricky => 'tricky',
    LumiMood.okay   => 'okay',
    LumiMood.good   => 'good',
    LumiMood.great  => 'great',
  };

  static String _moodLabel(LumiMood m) => switch (m) {
    LumiMood.hard   => 'Hard',
    LumiMood.tricky => 'Tricky',
    LumiMood.okay   => 'OK',
    LumiMood.good   => 'Good',
    LumiMood.great  => 'Great',
  };

  static String _costume(LumiCostume c) => switch (c) {
    LumiCostume.crown     => 'crown',
    LumiCostume.wizard    => 'wizard',
    LumiCostume.pirate    => 'pirate',
    LumiCostume.astronaut => 'astronaut',
    LumiCostume.chef      => 'chef',
    LumiCostume.cap       => 'cap',
    LumiCostume.ninja     => 'ninja',
    LumiCostume.dj        => 'dj',
  };

  static String _costumeLabel(LumiCostume c) => switch (c) {
    LumiCostume.crown     => 'a king',
    LumiCostume.wizard    => 'a wizard',
    LumiCostume.pirate    => 'a pirate',
    LumiCostume.astronaut => 'an astronaut',
    LumiCostume.chef      => 'a chef',
    LumiCostume.cap       => 'wearing a cap',
    LumiCostume.ninja     => 'a ninja',
    LumiCostume.dj        => 'a DJ',
  };

  static String _friend(LumiFriend f) => switch (f) {
    LumiFriend.penguin => 'penguin',
    LumiFriend.tiger   => 'tiger',
    LumiFriend.pig     => 'pig',
    LumiFriend.cat     => 'cat',
    LumiFriend.frog    => 'frog',
    LumiFriend.shark   => 'shark',
    LumiFriend.bear    => 'bear',
  };

  static String _friendLabel(LumiFriend f) => switch (f) {
    LumiFriend.penguin => 'a penguin',
    LumiFriend.tiger   => 'a tiger',
    LumiFriend.pig     => 'a piglet',
    LumiFriend.cat     => 'a kitten',
    LumiFriend.frog    => 'a frog',
    LumiFriend.shark   => 'a shark',
    LumiFriend.bear    => 'a bear',
  };

  static String _context(LumiContext c) => switch (c) {
    LumiContext.defaultPose   => 'default',
    LumiContext.withBooks     => 'with_books',
    LumiContext.withOpenBook  => 'with_open_book',
    LumiContext.withTrophy    => 'with_trophy',
  };
}
```

## B7. `lib/design_system/lumi_mood_selector.dart` — worked example

This is the canonical pattern. New design-system widgets should follow this shape: tokens for styling, section theme for accent, no inline colour literals.

```dart
import 'package:flutter/material.dart';
import '../theme/lumi_tokens.dart';
import '../theme/lumi_typography.dart';
import 'lumi_mascot.dart';

/// Five-option mood selector. Child taps a feeling — no typing.
///
/// Usage:
///   LumiMoodSelector(
///     selected: _mood,
///     onSelect: (m) => setState(() => _mood = m),
///   )
class LumiMoodSelector extends StatelessWidget {
  final LumiMood? selected;
  final ValueChanged<LumiMood> onSelect;
  final String prompt;

  const LumiMoodSelector({
    super.key,
    required this.onSelect,
    this.selected,
    this.prompt = "How was tonight's read?",
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiTokens.space6,
        vertical: LumiTokens.space6 + 4,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prompt, style: LumiType.subhead, textAlign: TextAlign.center),
          const SizedBox(height: LumiTokens.space5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: LumiMood.values
                .map((m) => _MoodOption(
                      mood: m,
                      isSelected: selected == m,
                      onTap: () => onSelect(m),
                    ))
                .toList(),
          ),
          const SizedBox(height: LumiTokens.space2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: LumiMood.values
                .map((m) => SizedBox(
                      width: _optionSize + _optionGap,
                      child: Text(
                        _label(m),
                        textAlign: TextAlign.center,
                        style: LumiType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: LumiTokens.ink,
                          fontSize: 12,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  static const double _optionSize = 76;
  static const double _optionGap = 12;

  static String _label(LumiMood m) => switch (m) {
    LumiMood.hard   => 'Hard',
    LumiMood.tricky => 'Tricky',
    LumiMood.okay   => 'OK',
    LumiMood.good   => 'Good',
    LumiMood.great  => 'Great',
  };

  static Color _tint(LumiMood m) => switch (m) {
    LumiMood.hard   => LumiTokens.tintBlue,
    LumiMood.tricky => LumiTokens.tintGreen,
    LumiMood.okay   => LumiTokens.tintYellow,
    LumiMood.good   => LumiTokens.tintOrange,
    LumiMood.great  => LumiTokens.tintRed,
  };
}

class _MoodOption extends StatelessWidget {
  final LumiMood mood;
  final bool isSelected;
  final VoidCallback onTap;

  const _MoodOption({
    required this.mood,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: isSelected ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Container(
            width: LumiMoodSelector._optionSize,
            height: LumiMoodSelector._optionSize,
            decoration: BoxDecoration(
              color: LumiMoodSelector._tint(mood),
              borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
            ),
            child: Center(
              child: LumiMascot.mood(mood, size: 56),
            ),
          ),
        ),
      ),
    );
  }
}
```

## B8. Folder structure once foundation is in

```
lib/
├── theme/
│   ├── lumi_tokens.dart           ← B2
│   ├── lumi_typography.dart       ← B3
│   ├── section_theme.dart         ← B4
│   └── lumi_theme.dart            ← B5
├── design_system/
│   ├── lumi_mascot.dart           ← B6
│   ├── lumi_mood_selector.dart    ← B7
│   ├── lumi_button.dart           ← add during migration
│   ├── lumi_chip.dart             ← add during migration
│   ├── lumi_book_card.dart        ← add during migration
│   ├── lumi_streak_card.dart      ← add during migration
│   └── lumi_rarity_badge.dart     ← add during migration
└── screens/
    ├── parent/
    │   ├── home/                   ← LumiSectionScope(section: LumiSectionTheme.home)
    │   ├── library/                ← LumiSectionScope(section: LumiSectionTheme.library)
    │   └── settings/               ← LumiSectionScope(section: LumiSectionTheme.settings)
    └── teacher/
        ├── dashboard/              ← LumiSectionScope(section: LumiSectionTheme.dashboard)
        ├── class/                  ← LumiSectionScope(section: LumiSectionTheme.classScreen)
        ├── library/                ← LumiSectionScope(section: LumiSectionTheme.library)
        └── settings/               ← LumiSectionScope(section: LumiSectionTheme.settings)
```

---

# PART C — Migration workflow

Don't redesign the whole app in one sitting. The pattern below is what to do per screen, then repeat. The first screen takes longest because it surfaces every missing widget; subsequent screens get faster.

## C1. Order to tackle screens

1. **Parent Home** — simplest, smallest, exercises the Home theme and the mood selector that's already built. Good first pass.
2. **Parent Library** — exercises the Yellow theme and book card patterns.
3. **Parent Settings** — Green theme, mostly forms and toggles.
4. **Teacher Class** — Red theme, the biggest data-density jump. Save until parent app is feeling solid.
5. **Teacher Library** — Yellow, with the ISBN scanner.
6. **Teacher Dashboard** — Blue, charts and analytics. Last because data viz is the heaviest lift.
7. **Teacher Settings** — Green, same patterns as parent settings.

## C2. Per-screen checklist

For each screen:

1. **Wrap the screen's root in `LumiSectionScope`** with the correct section. This sets the accent for everything inside.
2. **Replace `Scaffold` background** with `LumiTokens.cream` if it isn't already.
3. **Audit every colour literal** (`Color(0xFF...)`, `Colors.X`). Each one either maps to a token, to `context.sectionTheme.accent`, or it's wrong and needs to change.
4. **Audit every `TextStyle`**. Replace with `LumiType.X`.
5. **Replace ad-hoc buttons** with `LumiButton` (or whichever variant). If `LumiButton` doesn't exist yet, build it in `lib/design_system/` first using the same pattern as `LumiMoodSelector`.
6. **Replace mascot `Image.asset` calls** with `LumiMascot.X`.
7. **Run the screen on iOS and Android** — Nunito loads via `google_fonts`, so first run on a new device fetches it. Confirm no font fallback flashing.
8. **Open a PR.** Title: "Lumi UI — refactor [screen name] to design system". One screen per PR.

## C3. When you need a colour that isn't in `LumiTokens`

Stop and surface it. A new colour means either:
- An accent has crept in that doesn't belong (delete it), or
- The palette has a genuine gap (add it to tokens with a clear name and use justification).

Never inline `Color(0xFF...)` to "just get it working". The whole point is that tokens are the boundary.

## C4. When you need a mascot pose that doesn't exist yet

The contextual library is small (default, with_books, with_open_book, with_trophy). If a screen needs a pose that doesn't exist:
- Use `LumiMascot.flame(LumiColour.red)` as a placeholder.
- Add a TODO comment noting which pose is needed.
- Flag it back for design work; don't invent SVG approximations.

## C5. Things the design system intentionally does not do (yet)

- **Dark mode.** The brand is cream-bodied; dark mode hasn't been designed. Don't add `Brightness.dark` until there's a brief.
- **Animation library.** Lumi celebrates, but the specific animations (idle bob, milestone jump, streak ignite) are still in design. Use `AnimatedScale` / `AnimatedContainer` for state transitions; don't bake in mascot animations yet.
- **Theming for kid-facing screens.** Kid screens (if any are built) will likely have their own visual treatment — louder, brighter, possibly mascot-led. Don't extrapolate the parent/teacher patterns onto kids' surfaces.

---

# Quick reference for prompting

When asking Claude Code to do something:

> "Refactor `lib/screens/parent/home/home_screen.dart` to the Lumi design system per CLAUDE.md. Wrap in `LumiSectionScope.home`, replace colour literals with tokens or `context.sectionTheme`, replace text styles with `LumiType`, replace any mascot images with `LumiMascot`. If a design-system widget is missing for something on screen, build it in `lib/design_system/` following the `LumiMoodSelector` pattern before using it. One screen, one PR."

That's enough context for Claude Code to do the right thing without re-explaining the system every time.
