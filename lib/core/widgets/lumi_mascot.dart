import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';

enum LumiMood {
  happy,
  celebrating,
  encouraging,
  thinking,
  waving,
  reading,
  sleeping,
}

class LumiMascot extends StatelessWidget {
  final LumiMood mood;
  final double size;
  final String? message;
  final bool animate;

  const LumiMascot({
    super.key,
    this.mood = LumiMood.happy,
    this.size = 120,
    this.message,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget mascot = _buildMascot();

    if (animate) {
      mascot = _addAnimation(mascot);
    }

    if (message != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mascot,
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gray.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      );
    }

    return mascot;
  }

  Widget _buildMascot() {
    // For now, we'll use a custom painted mascot
    // In production, you'd use SVG files or Lottie animations
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: LumiPainter(mood: mood),
      ),
    );
  }

  Widget _addAnimation(Widget child) {
    switch (mood) {
      case LumiMood.happy:
        return child
            .animate(onPlay: (controller) => controller.repeat())
            .scale(
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.05, 1.05),
              duration: 2.seconds,
              curve: Curves.easeInOut,
            )
            .then()
            .scale(
              begin: const Offset(1.05, 1.05),
              end: const Offset(1.0, 1.0),
              duration: 2.seconds,
              curve: Curves.easeInOut,
            );

      case LumiMood.celebrating:
        return child
            .animate()
            .shake(duration: 500.ms, hz: 3)
            .then()
            .scale(
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.2, 1.2),
              duration: 300.ms,
            )
            .then()
            .scale(
              begin: const Offset(1.2, 1.2),
              end: const Offset(1.0, 1.0),
              duration: 300.ms,
            );

      case LumiMood.encouraging:
        return child
            .animate(onPlay: (controller) => controller.repeat())
            .moveY(
              begin: 0,
              end: -10,
              duration: 1.seconds,
              curve: Curves.easeInOut,
            )
            .then()
            .moveY(
              begin: -10,
              end: 0,
              duration: 1.seconds,
              curve: Curves.easeInOut,
            );

      case LumiMood.thinking:
        return child
            .animate(onPlay: (controller) => controller.repeat())
            .rotate(
              begin: -0.02,
              end: 0.02,
              duration: 2.seconds,
              curve: Curves.easeInOut,
            )
            .then()
            .rotate(
              begin: 0.02,
              end: -0.02,
              duration: 2.seconds,
              curve: Curves.easeInOut,
            );

      case LumiMood.waving:
        return child
            .animate(onPlay: (controller) => controller.repeat())
            .custom(
              duration: 2.seconds,
              builder: (context, value, child) {
                return Transform.rotate(
                  angle: value * 0.2 - 0.1,
                  alignment: Alignment.bottomCenter,
                  child: child,
                );
              },
            );

      case LumiMood.reading:
        return child.animate().fadeIn(duration: 500.ms).scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1.0, 1.0),
              duration: 500.ms,
              curve: Curves.easeOut,
            );

      case LumiMood.sleeping:
        return child
            .animate(onPlay: (controller) => controller.repeat())
            .scale(
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.02, 0.98),
              duration: 3.seconds,
              curve: Curves.easeInOut,
            )
            .then()
            .scale(
              begin: const Offset(1.02, 0.98),
              end: const Offset(1.0, 1.0),
              duration: 3.seconds,
              curve: Curves.easeInOut,
            );

      default:
        return child;
    }
  }
}

class LumiPainter extends CustomPainter {
  final LumiMood mood;

  LumiPainter({required this.mood});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.5;

    // Body
    final bodyPaint = Paint()
      ..color = AppColors.lumiBody
      ..style = PaintingStyle.fill;

    // Draw rounded body
    final bodyPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: radius * 1.6,
            height: radius * 1.8,
          ),
          Radius.circular(radius * 0.8),
        ),
      );

    canvas.drawPath(bodyPath, bodyPaint);

    // Draw arms (small circles on sides)
    final armPaint = Paint()
      ..color = AppColors.lumiBody
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(center.dx - radius * 0.8, center.dy),
      radius * 0.25,
      armPaint,
    );

    canvas.drawCircle(
      Offset(center.dx + radius * 0.8, center.dy),
      radius * 0.25,
      armPaint,
    );

    // Draw eyes based on mood
    _drawEyes(canvas, center, radius);

    // Draw mouth based on mood
    _drawMouth(canvas, center, radius);

    // Add mood-specific elements
    _drawMoodElements(canvas, center, radius, size);
  }

  void _drawEyes(Canvas canvas, Offset center, double radius) {
    final eyePaint = Paint()
      ..color = AppColors.lumiEyes
      ..style = PaintingStyle.fill;

    final eyeWhitePaint = Paint()
      ..color = AppColors.white
      ..style = PaintingStyle.fill;

    // Eye positions
    final leftEyeCenter =
        Offset(center.dx - radius * 0.25, center.dy - radius * 0.15);
    final rightEyeCenter =
        Offset(center.dx + radius * 0.25, center.dy - radius * 0.15);

    if (mood == LumiMood.sleeping) {
      // Closed eyes (lines)
      final eyeLinePaint = Paint()
        ..color = AppColors.lumiEyes
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(leftEyeCenter.dx - radius * 0.1, leftEyeCenter.dy),
        Offset(leftEyeCenter.dx + radius * 0.1, leftEyeCenter.dy),
        eyeLinePaint,
      );

      canvas.drawLine(
        Offset(rightEyeCenter.dx - radius * 0.1, rightEyeCenter.dy),
        Offset(rightEyeCenter.dx + radius * 0.1, rightEyeCenter.dy),
        eyeLinePaint,
      );
    } else {
      // Open eyes
      // Eye whites
      canvas.drawCircle(leftEyeCenter, radius * 0.12, eyeWhitePaint);
      canvas.drawCircle(rightEyeCenter, radius * 0.12, eyeWhitePaint);

      // Pupils
      canvas.drawCircle(leftEyeCenter, radius * 0.06, eyePaint);
      canvas.drawCircle(rightEyeCenter, radius * 0.06, eyePaint);

      if (mood == LumiMood.celebrating) {
        // Sparkle in eyes
        final sparklePaint = Paint()
          ..color = AppColors.white
          ..style = PaintingStyle.fill;

        canvas.drawCircle(
          Offset(leftEyeCenter.dx + radius * 0.02,
              leftEyeCenter.dy - radius * 0.02),
          radius * 0.02,
          sparklePaint,
        );
        canvas.drawCircle(
          Offset(rightEyeCenter.dx + radius * 0.02,
              rightEyeCenter.dy - radius * 0.02),
          radius * 0.02,
          sparklePaint,
        );
      }
    }
  }

  void _drawMouth(Canvas canvas, Offset center, double radius) {
    final mouthPaint = Paint()
      ..color = AppColors.lumiEyes
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final mouthCenter = Offset(center.dx, center.dy + radius * 0.2);

    switch (mood) {
      case LumiMood.happy:
      case LumiMood.celebrating:
      case LumiMood.encouraging:
        // Big smile
        final path = Path();
        path.moveTo(mouthCenter.dx - radius * 0.2, mouthCenter.dy);
        path.quadraticBezierTo(
          mouthCenter.dx,
          mouthCenter.dy + radius * 0.15,
          mouthCenter.dx + radius * 0.2,
          mouthCenter.dy,
        );
        canvas.drawPath(path, mouthPaint);
        break;

      case LumiMood.thinking:
        // Straight line
        canvas.drawLine(
          Offset(mouthCenter.dx - radius * 0.1, mouthCenter.dy),
          Offset(mouthCenter.dx + radius * 0.1, mouthCenter.dy),
          mouthPaint,
        );
        break;

      case LumiMood.reading:
        // Small 'o' shape
        canvas.drawCircle(mouthCenter, radius * 0.08, mouthPaint);
        break;

      case LumiMood.waving:
        // Small smile
        final path = Path();
        path.moveTo(mouthCenter.dx - radius * 0.15, mouthCenter.dy);
        path.quadraticBezierTo(
          mouthCenter.dx,
          mouthCenter.dy + radius * 0.1,
          mouthCenter.dx + radius * 0.15,
          mouthCenter.dy,
        );
        canvas.drawPath(path, mouthPaint);
        break;

      case LumiMood.sleeping:
        // Small relaxed mouth
        final path = Path();
        path.moveTo(mouthCenter.dx - radius * 0.1, mouthCenter.dy);
        path.quadraticBezierTo(
          mouthCenter.dx,
          mouthCenter.dy + radius * 0.05,
          mouthCenter.dx + radius * 0.1,
          mouthCenter.dy,
        );
        canvas.drawPath(path, mouthPaint);
        break;
    }
  }

  void _drawMoodElements(
      Canvas canvas, Offset center, double radius, Size size) {
    switch (mood) {
      case LumiMood.celebrating:
        // Draw confetti around
        final colors = [
          AppColors.secondaryOrange,
          AppColors.secondaryYellow,
          AppColors.secondaryGreen,
          AppColors.secondaryPurple,
        ];

        for (int i = 0; i < 8; i++) {
          final angle = (i * 45) * 3.14159 / 180;
          final confettiPaint = Paint()
            ..color = colors[i % colors.length]
            ..style = PaintingStyle.fill;

          final offset = Offset(
            center.dx +
                radius *
                    1.5 *
                    (angle.hashCode % 2 == 0 ? 1 : 1.2) *
                    (angle < 0 ? -1 : 1),
            center.dy -
                radius *
                    1.5 *
                    (angle.hashCode % 2 == 0 ? 1 : 1.2) *
                    (angle < 0 ? -1 : 1),
          );

          canvas.drawCircle(offset, 3, confettiPaint);
        }
        break;

      case LumiMood.reading:
        // Draw a small book
        final bookPaint = Paint()
          ..color = AppColors.secondaryPurple
          ..style = PaintingStyle.fill;

        final bookRect = Rect.fromCenter(
          center: Offset(center.dx, center.dy + radius * 0.8),
          width: radius * 0.4,
          height: radius * 0.3,
        );

        canvas.drawRect(bookRect, bookPaint);
        break;

      case LumiMood.sleeping:
        // Draw 'Z's
        final textPainter = TextPainter(
          text: const TextSpan(
            text: 'Z',
            style: TextStyle(
              color: AppColors.primaryBlue,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(center.dx + radius * 0.8, center.dy - radius * 0.8),
        );

        textPainter.paint(
          canvas,
          Offset(center.dx + radius * 0.9, center.dy - radius * 0.6),
        );
        break;

      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is LumiPainter && oldDelegate.mood != mood;
  }
}
