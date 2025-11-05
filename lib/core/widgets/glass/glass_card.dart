import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';

/// Basic glass container with backdrop blur effect
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = LiquidGlassTheme.radiusLg,
    this.padding,
    this.color,
    this.width,
    this.height,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlur,
          sigmaY: LiquidGlassTheme.glassBlur,
        ),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(LiquidGlassTheme.spacingMd),
          decoration: LiquidGlassTheme.glassDecoration(
            borderRadius: borderRadius,
            color: color,
            border: border,
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}

/// Animated glass card with scale animation on tap
class AnimatedGlassCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const AnimatedGlassCard({
    super.key,
    required this.child,
    this.borderRadius = LiquidGlassTheme.radiusLg,
    this.padding,
    this.color,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  State<AnimatedGlassCard> createState() => _AnimatedGlassCardState();
}

class _AnimatedGlassCardState extends State<AnimatedGlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 - (_controller.value * 0.05),
            child: child,
          );
        },
        child: GlassCard(
          borderRadius: widget.borderRadius,
          padding: widget.padding,
          color: widget.color,
          width: widget.width,
          height: widget.height,
          child: widget.child,
        ),
      ),
    );
  }
}
