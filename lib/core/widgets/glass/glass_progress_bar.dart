import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../theme/app_colors.dart';

/// Glass progress bar with smooth animations
class GlassProgressBar extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final double height;
  final Gradient? gradient;
  final Color? backgroundColor;

  const GlassProgressBar({
    super.key,
    required this.progress,
    this.height = 12,
    this.gradient,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlur,
          sigmaY: LiquidGlassTheme.glassBlur,
        ),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: gradient ?? LiquidGlassTheme.successGradient,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass circular progress indicator
class GlassProgressCircle extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final String? label;
  final String? sublabel;
  final double size;
  final Gradient? gradient;
  final double strokeWidth;

  const GlassProgressCircle({
    super.key,
    required this.progress,
    this.label,
    this.sublabel,
    this.size = 120,
    this.gradient,
    this.strokeWidth = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlur,
          sigmaY: LiquidGlassTheme.glassBlur,
        ),
        child: Container(
          width: size,
          height: size,
          decoration: LiquidGlassTheme.glassDecoration(
            borderRadius: size / 2,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Progress circle
              SizedBox(
                width: size - (strokeWidth * 2),
                height: size - (strokeWidth * 2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: progress.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _CircleProgressPainter(
                        progress: value,
                        gradient: gradient ?? LiquidGlassTheme.coolGradient,
                        strokeWidth: strokeWidth,
                      ),
                    );
                  },
                ),
              ),
              // Center content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (label != null)
                    Text(
                      label!,
                      style: TextStyle(
                        fontSize: size * 0.25,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkGray,
                      ),
                    ),
                  if (sublabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      sublabel!,
                      style: TextStyle(
                        fontSize: size * 0.1,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final Gradient gradient;
  final double strokeWidth;

  _CircleProgressPainter({
    required this.progress,
    required this.gradient,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2);

    // Background circle
    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -90 * 3.14159 / 180; // Start from top
    final sweepAngle = 2 * 3.14159 * progress;

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
