/// Lumi Design System - Spacing
///
/// All spacing values follow an 8pt grid system for visual consistency
/// Use these constants for all margins, padding, and layout spacing
///
/// Grid Units:
/// XXS (0.5): 4pt  - Minimal spacing, tight layouts
/// XS  (1):   8pt  - Small spacing, compact elements
/// S   (2):   16pt - Standard spacing, most common
/// M   (3):   24pt - Medium spacing, section spacing
/// L   (4):   32pt - Large spacing, page sections
/// XL  (6):   48pt - Extra large, major sections
/// XXL (8):   64pt - Maximum spacing, page margins
class LumiSpacing {
  // ============================================
  // BASE SPACING VALUES (8pt Grid)
  // ============================================

  /// XXS - 4pt (0.5 grid units)
  /// Usage: Minimal spacing, tight layouts, icon padding
  static const double xxs = 4.0;

  /// XS - 8pt (1 grid unit)
  /// Usage: Small spacing, compact elements, list item padding
  static const double xs = 8.0;

  /// S - 16pt (2 grid units)
  /// Usage: Standard spacing, most common, card padding
  static const double s = 16.0;

  /// M - 24pt (3 grid units)
  /// Usage: Medium spacing, section spacing, component gaps
  static const double m = 24.0;

  /// L - 32pt (4 grid units)
  /// Usage: Large spacing, page sections, major gaps
  static const double l = 32.0;

  /// XL - 48pt (6 grid units)
  /// Usage: Extra large spacing, major sections
  static const double xl = 48.0;

  /// XXL - 64pt (8 grid units)
  /// Usage: Maximum spacing, page margins, hero sections
  static const double xxl = 64.0;

  // ============================================
  // SEMANTIC SPACING (Common Use Cases)
  // ============================================

  /// Default padding for screens
  /// Value: 16pt (s)
  static const double screenPadding = s;

  /// Default padding for screens (horizontal only)
  /// Value: 16pt (s)
  static const double screenPaddingHorizontal = s;

  /// Default padding for screens (vertical only)
  /// Value: 16pt (s)
  static const double screenPaddingVertical = s;

  /// Default padding for cards
  /// Value: 20pt (between s and m)
  static const double cardPadding = 20.0;

  /// Default padding for buttons (vertical)
  /// Value: 16pt (s)
  static const double buttonPaddingVertical = s;

  /// Default padding for buttons (horizontal)
  /// Value: 24pt (m)
  static const double buttonPaddingHorizontal = m;

  /// Default padding for input fields (vertical)
  /// Value: 12pt (between xs and s)
  static const double inputPaddingVertical = 12.0;

  /// Default padding for input fields (horizontal)
  /// Value: 16pt (s)
  static const double inputPaddingHorizontal = s;

  /// Spacing between related elements (e.g., label and input)
  /// Value: 8pt (xs)
  static const double elementSpacing = xs;

  /// Spacing between sections
  /// Value: 32pt (l)
  static const double sectionSpacing = l;

  /// Spacing between cards in a list
  /// Value: 16pt (s)
  static const double cardSpacing = s;

  /// Spacing between list items
  /// Value: 12pt
  static const double listItemSpacing = 12.0;

  // ============================================
  // COMPONENT-SPECIFIC SPACING
  // ============================================

  /// Icon and text spacing (buttons, list items)
  /// Value: 8pt (xs)
  static const double iconTextSpacing = xs;

  /// Bottom navigation bar height
  /// Value: 64pt (xxl / 8 grid units)
  static const double bottomNavHeight = 64.0;

  /// App bar height
  /// Value: 56pt
  static const double appBarHeight = 56.0;

  /// Safe area padding (minimum screen edge padding)
  /// Value: 16pt (s)
  static const double safeAreaPadding = s;

  /// Minimum touch target size (accessibility)
  /// Value: 44pt (iOS standard)
  static const double minTouchTarget = 44.0;

  /// Minimum touch target size (Material Design)
  /// Value: 48pt
  static const double minTouchTargetMaterial = 48.0;

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Returns a multiple of the base grid unit (8pt)
  /// Example: gridUnits(3) returns 24pt
  static double gridUnits(double units) => units * xs;

  /// Returns responsive spacing based on screen width
  /// Returns larger spacing on tablets/desktop
  static double responsive(double phoneValue, double tabletValue, double width) {
    const tabletBreakpoint = 600.0;
    return width >= tabletBreakpoint ? tabletValue : phoneValue;
  }
}

/// EdgeInsets presets using Lumi spacing values
class LumiPadding {
  // ============================================
  // SYMMETRIC PADDING
  // ============================================

  /// All sides - XXS (4pt)
  static const EdgeInsets allXXS = EdgeInsets.all(LumiSpacing.xxs);

  /// All sides - XS (8pt)
  static const EdgeInsets allXS = EdgeInsets.all(LumiSpacing.xs);

  /// All sides - S (16pt)
  static const EdgeInsets allS = EdgeInsets.all(LumiSpacing.s);

  /// All sides - M (24pt)
  static const EdgeInsets allM = EdgeInsets.all(LumiSpacing.m);

  /// All sides - L (32pt)
  static const EdgeInsets allL = EdgeInsets.all(LumiSpacing.l);

  /// All sides - XL (48pt)
  static const EdgeInsets allXL = EdgeInsets.all(LumiSpacing.xl);

  // ============================================
  // HORIZONTAL PADDING
  // ============================================

  /// Horizontal - S (16pt)
  static const EdgeInsets horizontalS = EdgeInsets.symmetric(horizontal: LumiSpacing.s);

  /// Horizontal - M (24pt)
  static const EdgeInsets horizontalM = EdgeInsets.symmetric(horizontal: LumiSpacing.m);

  /// Horizontal - L (32pt)
  static const EdgeInsets horizontalL = EdgeInsets.symmetric(horizontal: LumiSpacing.l);

  // ============================================
  // VERTICAL PADDING
  // ============================================

  /// Vertical - XS (8pt)
  static const EdgeInsets verticalXS = EdgeInsets.symmetric(vertical: LumiSpacing.xs);

  /// Vertical - S (16pt)
  static const EdgeInsets verticalS = EdgeInsets.symmetric(vertical: LumiSpacing.s);

  /// Vertical - M (24pt)
  static const EdgeInsets verticalM = EdgeInsets.symmetric(vertical: LumiSpacing.m);

  // ============================================
  // COMPONENT-SPECIFIC PADDING
  // ============================================

  /// Standard screen padding (16pt all sides)
  static const EdgeInsets screen = EdgeInsets.all(LumiSpacing.screenPadding);

  /// Card padding (20pt all sides)
  static const EdgeInsets card = EdgeInsets.all(LumiSpacing.cardPadding);

  /// Button padding (16pt vertical, 24pt horizontal)
  static const EdgeInsets button = EdgeInsets.symmetric(
    vertical: LumiSpacing.buttonPaddingVertical,
    horizontal: LumiSpacing.buttonPaddingHorizontal,
  );

  /// Input field padding (12pt vertical, 16pt horizontal)
  static const EdgeInsets input = EdgeInsets.symmetric(
    vertical: LumiSpacing.inputPaddingVertical,
    horizontal: LumiSpacing.inputPaddingHorizontal,
  );

  /// List item padding (12pt vertical, 16pt horizontal)
  static const EdgeInsets listItem = EdgeInsets.symmetric(
    vertical: LumiSpacing.listItemSpacing,
    horizontal: LumiSpacing.s,
  );
}

/// SizedBox presets using Lumi spacing values
class LumiGap {
  /// Vertical gap - XXS (4pt)
  static const Widget xxs = SizedBox(height: LumiSpacing.xxs);

  /// Vertical gap - XS (8pt)
  static const Widget xs = SizedBox(height: LumiSpacing.xs);

  /// Vertical gap - S (16pt)
  static const Widget s = SizedBox(height: LumiSpacing.s);

  /// Vertical gap - M (24pt)
  static const Widget m = SizedBox(height: LumiSpacing.m);

  /// Vertical gap - L (32pt)
  static const Widget l = SizedBox(height: LumiSpacing.l);

  /// Vertical gap - XL (48pt)
  static const Widget xl = SizedBox(height: LumiSpacing.xl);

  /// Vertical gap - XXL (64pt)
  static const Widget xxl = SizedBox(height: LumiSpacing.xxl);

  /// Horizontal gap - XXS (4pt)
  static const Widget horizontalXXS = SizedBox(width: LumiSpacing.xxs);

  /// Horizontal gap - XS (8pt)
  static const Widget horizontalXS = SizedBox(width: LumiSpacing.xs);

  /// Horizontal gap - S (16pt)
  static const Widget horizontalS = SizedBox(width: LumiSpacing.s);

  /// Horizontal gap - M (24pt)
  static const Widget horizontalM = SizedBox(width: LumiSpacing.m);

  /// Horizontal gap - L (32pt)
  static const Widget horizontalL = SizedBox(width: LumiSpacing.l);
}
