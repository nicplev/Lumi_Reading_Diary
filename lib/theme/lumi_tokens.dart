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
