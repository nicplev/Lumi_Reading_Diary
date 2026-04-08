import 'package:flutter/material.dart';

/// Lumi Design System - Animated Count Text
///
/// Reusable widget that animates a number from 0 to the target value.
/// Supports an optional suffix (e.g., "%" for percentages).
class AnimatedCountText extends StatelessWidget {
  final int value;
  final String suffix;
  final TextStyle style;
  final Duration duration;
  final Curve curve;

  const AnimatedCountText({
    super.key,
    required this.value,
    this.suffix = '',
    required this.style,
    this.duration = const Duration(milliseconds: 1200),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: curve,
      builder: (context, val, child) {
        return Text(
          '$val$suffix',
          style: style,
        );
      },
    );
  }
}
