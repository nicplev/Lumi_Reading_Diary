import 'package:flutter/material.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../theme/section_theme.dart';

/// Lumi Design System - Week Progress Bar
///
/// 7 circles with a weekday label beneath each (M T W T F S S) showing daily
/// reading completion. The label always shows so completed days keep their
/// weekday; the circle carries the state:
/// - Read (incl. today): soft green fill with checkmark (a confirmation state)
/// - Today (not done): section-accent ring — a gentle nudge; label is accent
/// - Future: empty warm-grey ring
/// - Missed: empty warm-grey ring (same as future, but in the past)
class WeekProgressBar extends StatelessWidget {
  /// Set of weekday indices (1=Monday through 7=Sunday) that are completed
  final Set<int> completedDays;

  /// Current day of the week (1=Monday through 7=Sunday)
  final int currentDay;

  const WeekProgressBar({
    super.key,
    required this.completedDays,
    required this.currentDay,
  });

  @override
  Widget build(BuildContext context) {
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final accent = context.sectionTheme.accent;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final dayNumber = index + 1;
        return _DayCircle(
          label: dayLabels[index],
          isCompleted: completedDays.contains(dayNumber),
          isToday: dayNumber == currentDay,
          isFuture: dayNumber > currentDay,
          accent: accent,
        );
      }),
    );
  }
}

class _DayCircle extends StatelessWidget {
  final String label;
  final bool isCompleted;
  final bool isToday;
  final bool isFuture;
  final Color accent;

  const _DayCircle({
    required this.label,
    required this.isCompleted,
    required this.isToday,
    required this.isFuture,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor = Colors.transparent;
    Color? borderColor;
    double borderWidth = 0;
    Widget? child;
    Color labelColor = LumiTokens.muted;

    if (isCompleted) {
      // Read (incl. today): soft green confirmation fill with checkmark.
      backgroundColor = LumiTokens.tintGreen;
      child = Icon(Icons.check,
          color: LumiTokens.ink.withValues(alpha: 0.6), size: 18);
      labelColor = isToday ? accent : LumiTokens.ink;
    } else if (isToday) {
      // Today not done: section-accent ring nudge.
      borderColor = accent;
      borderWidth = 2;
      labelColor = accent;
    } else {
      // Future or missed: empty warm-grey ring.
      borderColor = LumiTokens.rule;
      borderWidth = 1.5;
      labelColor = LumiTokens.muted;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            border: borderWidth > 0
                ? Border.all(color: borderColor!, width: borderWidth)
                : null,
          ),
          child: child == null ? null : Center(child: child),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: LumiType.caption.copyWith(
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}
