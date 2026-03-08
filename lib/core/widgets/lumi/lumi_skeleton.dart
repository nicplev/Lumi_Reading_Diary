import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

class LumiSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final bool isCircular;

  const LumiSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = TeacherDimensions.radiusM,
    this.isCircular = false,
  });

  @override
  State<LumiSkeleton> createState() => _LumiSkeletonState();
}

class _LumiSkeletonState extends State<LumiSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.textSecondary.withValues(alpha: _animation.value * 0.3),
            shape: widget.isCircular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircular ? null : BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}
