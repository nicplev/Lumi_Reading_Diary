import 'dart:math';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// Lumi Design System - Progress Ring
///
/// Multi-layer concentric ring widget showing reading progress.
/// - Outer ring: total nights progress (coral/peach gradient)
/// - Middle ring: weekly progress (segmented colors)
/// - Inner ring: today's status (mint if complete, gray if pending)
/// - Center: large number with label
class ProgressRing extends StatelessWidget {
  final int totalNights;
  final int totalNightsGoal;
  final int weeklyProgress;
  final bool todayComplete;
  final String? label;

  const ProgressRing({
    super.key,
    required this.totalNights,
    this.totalNightsGoal = 100,
    required this.weeklyProgress,
    required this.todayComplete,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: CustomPaint(
        painter: _ProgressRingPainter(
          totalProgress: (totalNights / totalNightsGoal).clamp(0.0, 1.0),
          weeklyProgress: (weeklyProgress / 7).clamp(0.0, 1.0),
          todayComplete: todayComplete,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                totalNights.toString(),
                style: LumiTextStyles.display(color: AppColors.charcoal)
                    .copyWith(fontSize: 48),
              ),
              Text(
                label ?? 'Nights',
                style: LumiTextStyles.bodySmall(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double totalProgress;
  final double weeklyProgress;
  final bool todayComplete;

  _ProgressRingPainter({
    required this.totalProgress,
    required this.weeklyProgress,
    required this.todayComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer ring - total nights (180px diameter, 12px stroke)
    _drawRing(
      canvas,
      center,
      radius: size.width / 2 - 6,
      strokeWidth: 12,
      progress: totalProgress,
      backgroundAlpha: 0.1,
      colors: [AppColors.rosePink, AppColors.lumiPeach],
    );

    // Middle ring - weekly progress (140px diameter, 10px stroke)
    _drawRing(
      canvas,
      center,
      radius: size.width / 2 - 24,
      strokeWidth: 10,
      progress: weeklyProgress,
      backgroundAlpha: 0.08,
      colors: [AppColors.skyBlue, AppColors.mintGreen],
    );

    // Inner ring - today's status (100px diameter, 8px stroke)
    _drawRing(
      canvas,
      center,
      radius: size.width / 2 - 42,
      strokeWidth: 8,
      progress: todayComplete ? 1.0 : 0.0,
      backgroundAlpha: 0.06,
      colors: todayComplete
          ? [AppColors.mintGreen, AppColors.mintGreen]
          : [AppColors.charcoal, AppColors.charcoal],
    );
  }

  void _drawRing(
    Canvas canvas,
    Offset center, {
    required double radius,
    required double strokeWidth,
    required double progress,
    required double backgroundAlpha,
    required List<Color> colors,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final bgPaint = Paint()
      ..color = AppColors.charcoal.withValues(alpha: backgroundAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, bgPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -pi / 2,
          endAngle: -pi / 2 + 2 * pi * progress,
          colors: colors,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.totalProgress != totalProgress ||
        oldDelegate.weeklyProgress != weeklyProgress ||
        oldDelegate.todayComplete != todayComplete;
  }
}
