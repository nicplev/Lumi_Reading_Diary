import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// Lumi Design System - Rhythm Calendar
///
/// A forgiving "X of the last N nights" dot grid. Each dot is one calendar day
/// in the trailing window, oldest (top-left) to today (bottom-right):
/// - Read: Lumi Mint fill
/// - Today (read): coral fill
/// - Today (not yet read): coral outline
/// - Not read: neutral gray — deliberately NOT red. A missed night is simply a
///   dot that hasn't lit up yet, never a failure. The window slides forward
///   each day, so the count recovers naturally; it never resets to zero.
class RhythmCalendar extends StatelessWidget {
  /// Days the student read (any time component is ignored).
  final Set<DateTime> readDays;

  /// Size of the trailing window, ending today. Defaults to 30.
  final int windowDays;

  /// Headline count of nights read in the window. When null it is derived from
  /// [readDays] within the window (the server-provided count is preferred).
  final int? count;

  const RhythmCalendar({
    super.key,
    required this.readDays,
    this.windowDays = 30,
    this.count,
  });

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final readKeys = readDays.map(_key).toSet();

    // Oldest day first so the grid reads as a left-to-right timeline ending today.
    final days = List<DateTime>.generate(
      windowDays,
      (i) => today.subtract(Duration(days: windowDays - 1 - i)),
    );

    final headlineCount =
        count ?? days.where((d) => readKeys.contains(_key(d))).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.nightlight_round,
                color: AppColors.lumiPeach, size: 18),
            const SizedBox(width: 8),
            Text(
              '$headlineCount of the last $windowDays nights',
              style: LumiTextStyles.bodyMedium(color: AppColors.charcoal)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final day in days)
              _RhythmDot(
                isRead: readKeys.contains(_key(day)),
                isToday: day == today,
              ),
          ],
        ),
      ],
    );
  }
}

class _RhythmDot extends StatelessWidget {
  final bool isRead;
  final bool isToday;

  const _RhythmDot({required this.isRead, required this.isToday});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color? borderColor;
    double borderWidth = 0;

    if (isRead && isToday) {
      backgroundColor = AppColors.rosePink;
    } else if (isRead) {
      backgroundColor = AppColors.mintGreen;
    } else if (isToday) {
      backgroundColor = Colors.transparent;
      borderColor = AppColors.rosePink;
      borderWidth = 2;
    } else {
      // Not read — neutral, never a "missed" red.
      backgroundColor = AppColors.divider;
    }

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: borderWidth > 0
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
    );
  }
}
