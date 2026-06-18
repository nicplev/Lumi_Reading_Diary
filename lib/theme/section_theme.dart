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
    accent: LumiTokens.green,
    accentTint: LumiTokens.tintGreen,
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
    accent: LumiTokens.red,
    accentTint: LumiTokens.tintRed,
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
