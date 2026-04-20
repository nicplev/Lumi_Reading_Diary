import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Progressive-pill step indicator.
///
/// Renders a row of dots where completed steps fill in and connect into a
/// stadium-shaped pill as [currentStep] advances. The active step is shown as
/// a ring with a hollow centre; upcoming steps are small inactive dots.
class LumiStepIndicator extends StatelessWidget {
  final int stepCount;
  final int currentStep;
  final Color? activeColor;
  final Color? inactiveColor;
  final double dotSize;
  final double activeDotSize;
  final double spacing;
  final Duration duration;

  const LumiStepIndicator({
    super.key,
    required this.stepCount,
    required this.currentStep,
    this.activeColor,
    this.inactiveColor,
    this.dotSize = 10,
    this.activeDotSize = 16,
    this.spacing = 18,
    this.duration = const Duration(milliseconds: 320),
  }) : assert(stepCount > 0),
       assert(currentStep >= 0);

  @override
  Widget build(BuildContext context) {
    final active = activeColor ?? AppColors.rosePink;
    final inactive =
        inactiveColor ?? AppColors.charcoal.withValues(alpha: 0.18);

    final clamped = currentStep.clamp(0, stepCount - 1);
    final trackHeight = activeDotSize + 6;
    final cellWidth = activeDotSize + spacing;
    final totalWidth = cellWidth * stepCount;

    // Pill grows to cover from the first dot centre through the current dot
    // centre, inset by half the active dot on each end so it hugs the outer
    // edge cleanly.
    final fillWidth = activeDotSize + (cellWidth * clamped);

    return SizedBox(
      width: totalWidth,
      height: trackHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Connecting pill (grows as current step advances)
          Positioned(
            left: (cellWidth - activeDotSize) / 2,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: fillWidth,
              height: activeDotSize,
              decoration: BoxDecoration(
                color: active,
                borderRadius: BorderRadius.circular(activeDotSize / 2),
              ),
            ),
          ),
          // Dots
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(stepCount, (index) {
              final isCompleted = index < clamped;
              final isCurrent = index == clamped;

              return SizedBox(
                width: cellWidth,
                height: trackHeight,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: _buildDot(
                      key: ValueKey(
                        '$index-${isCurrent ? 'current' : isCompleted ? 'done' : 'todo'}',
                      ),
                      isCompleted: isCompleted,
                      isCurrent: isCurrent,
                      active: active,
                      inactive: inactive,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDot({
    required Key key,
    required bool isCompleted,
    required bool isCurrent,
    required Color active,
    required Color inactive,
  }) {
    if (isCurrent) {
      return Container(
        key: key,
        width: activeDotSize,
        height: activeDotSize,
        decoration: BoxDecoration(
          color: active,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: activeDotSize * 0.35,
            height: activeDotSize * 0.35,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    if (isCompleted) {
      return Container(
        key: key,
        width: activeDotSize * 0.55,
        height: activeDotSize * 0.55,
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      key: key,
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: inactive,
        shape: BoxShape.circle,
      ),
    );
  }
}
