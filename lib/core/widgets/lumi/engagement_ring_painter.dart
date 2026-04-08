import 'dart:math';
import 'package:flutter/material.dart';

/// Lumi Design System - Engagement Ring Painter
///
/// Single-layer arc ring with gradient fill for showing engagement percentage.
/// Used on the teacher dashboard engagement card.
class EngagementRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final List<Color> gradientColors;
  final double strokeWidth;

  EngagementRingPainter({
    required this.progress,
    this.trackColor = const Color(0xFFF0F4F8),
    this.gradientColors = const [Color(0xFF64B5F6), Color(0xFF90CAF9)],
    this.strokeWidth = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, trackPaint);

    // Progress arc
    if (progress > 0) {
      final clampedProgress = progress.clamp(0.0, 1.0);
      final sweepAngle = 2 * pi * clampedProgress;

      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -pi / 2,
          endAngle: -pi / 2 + sweepAngle,
          colors: gradientColors,
          tileMode: TileMode.clamp,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, -pi / 2, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EngagementRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gradientColors != gradientColors;
  }
}
