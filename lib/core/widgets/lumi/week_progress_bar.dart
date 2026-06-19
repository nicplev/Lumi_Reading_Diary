import 'package:flutter/material.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../theme/section_theme.dart';

/// Lumi Design System - Week Progress Bar
///
/// 7 circles (M T W T F S S) showing daily reading completion.
/// States:
/// - Completed (past): soft green fill with checkmark (a confirmation state)
/// - Today (done): section-accent fill with checkmark
/// - Today (not done): 2px section-accent border outline only
/// - Future: warm-grey fill
/// - Missed: unfilled with warm-grey outline
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
    Color backgroundColor;
    Color? borderColor;
    double borderWidth = 0;
    Widget child;

    final labelStyle = LumiType.caption.copyWith(fontWeight: FontWeight.w700);

    if (isCompleted && isToday) {
      // Today completed: section-accent fill with checkmark.
      backgroundColor = accent;
      child = const Icon(Icons.check, color: LumiTokens.paper, size: 18);
    } else if (isCompleted) {
      // Past completed: soft green (confirmation) fill with checkmark.
      backgroundColor = LumiTokens.tintGreen;
      child = Icon(Icons.check,
          color: LumiTokens.ink.withValues(alpha: 0.6), size: 18);
    } else if (isToday) {
      // Today not done: section-accent outline only.
      backgroundColor = Colors.transparent;
      borderColor = accent;
      borderWidth = 2;
      child = Text(label, style: labelStyle.copyWith(color: accent));
    } else if (isFuture) {
      // Future: warm-grey fill.
      backgroundColor = LumiTokens.rule;
      child = Text(label, style: labelStyle.copyWith(color: LumiTokens.muted));
    } else {
      // Past missed: warm-grey outline.
      backgroundColor = Colors.transparent;
      borderColor = LumiTokens.rule;
      borderWidth = 1.5;
      child = Text(label, style: labelStyle.copyWith(color: LumiTokens.muted));
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: borderWidth > 0
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: Center(child: child),
    );
  }
}
