import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// Lumi Design System - Week Progress Bar
///
/// 7 circles (M T W T F S S) showing daily reading completion.
/// States:
/// - Completed: Lumi Mint fill with checkmark
/// - Today (not done): 2px coral border outline only
/// - Today (done): Coral fill with checkmark
/// - Future: divider gray fill
/// - Missed: unfilled with gray outline
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final dayNumber = index + 1;
        final isCompleted = completedDays.contains(dayNumber);
        final isToday = dayNumber == currentDay;
        final isFuture = dayNumber > currentDay;

        return _DayCircle(
          label: dayLabels[index],
          isCompleted: isCompleted,
          isToday: isToday,
          isFuture: isFuture,
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

  const _DayCircle({
    required this.label,
    required this.isCompleted,
    required this.isToday,
    required this.isFuture,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color? borderColor;
    double borderWidth = 0;
    Widget child;

    if (isCompleted && isToday) {
      // Today completed: coral fill with checkmark
      backgroundColor = AppColors.rosePink;
      child = const Icon(Icons.check, color: AppColors.white, size: 18);
    } else if (isCompleted) {
      // Past completed: mint fill with checkmark
      backgroundColor = AppColors.mintGreen;
      child = Icon(Icons.check,
          color: AppColors.charcoal.withValues(alpha: 0.7), size: 18);
    } else if (isToday) {
      // Today not done: outline only
      backgroundColor = Colors.transparent;
      borderColor = AppColors.rosePink;
      borderWidth = 2;
      child = Text(
        label,
        style: LumiTextStyles.label(color: AppColors.rosePink),
      );
    } else if (isFuture) {
      // Future: divider gray
      backgroundColor = AppColors.divider;
      child = Text(
        label,
        style: LumiTextStyles.label(
          color: AppColors.charcoal.withValues(alpha: 0.4),
        ),
      );
    } else {
      // Past missed: gray outline
      backgroundColor = Colors.transparent;
      borderColor = AppColors.divider;
      borderWidth = 1.5;
      child = Text(
        label,
        style: LumiTextStyles.label(
          color: AppColors.charcoal.withValues(alpha: 0.4),
        ),
      );
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
