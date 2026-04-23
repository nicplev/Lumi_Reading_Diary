import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/impersonation_session.dart';

/// Low-opacity diagonal watermark repeating the dev's identity and the
/// session start time. Helps attribute any screenshots taken during
/// impersonation. Intentionally subtle: visible in screenshots at 100%
/// zoom but unobtrusive during actual work.
class ImpersonationWatermark extends StatelessWidget {
  const ImpersonationWatermark({super.key, required this.session});

  final ImpersonationSession session;

  @override
  Widget build(BuildContext context) {
    final label =
        '${session.targetUserLabel} • ${session.schoolName} • ${session.startedAt.toIso8601String()}';
    return IgnorePointer(
      child: CustomPaint(
        painter: _WatermarkPainter(label: label),
        size: Size.infinite,
      ),
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter({required this.label});
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFFB91C1C).withValues(alpha: 0.06),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const stepX = 320.0;
    const stepY = 140.0;
    canvas.save();
    canvas.rotate(-math.pi / 6);
    // Over-draw beyond the visible area to cover the rotated rectangle.
    for (double y = -size.height; y < size.height * 2; y += stepY) {
      for (double x = -size.width; x < size.width * 2; x += stepX) {
        textPainter.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) =>
      oldDelegate.label != label;
}
