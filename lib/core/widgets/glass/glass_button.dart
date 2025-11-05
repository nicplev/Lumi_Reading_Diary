import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../theme/app_colors.dart';

/// Pressable button with glass effect and smooth animations
class GlassButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final IconData? icon;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;

  const GlassButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isPrimary = false,
    this.icon,
    this.width,
    this.padding,
    this.gradient,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
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
      onTapDown: widget.onPressed != null ? (_) => _controller.forward() : null,
      onTapUp: widget.onPressed != null
          ? (_) {
              _controller.reverse();
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 - (_controller.value * 0.05),
            child: child,
          );
        },
        child: _buildButton(),
      ),
    );
  }

  Widget _buildButton() {
    if (widget.isPrimary) {
      // Primary button with gradient
      return Container(
        width: widget.width,
        padding: widget.padding ??
            const EdgeInsets.symmetric(
              horizontal: LiquidGlassTheme.spacingLg,
              vertical: LiquidGlassTheme.spacingMd,
            ),
        decoration: LiquidGlassTheme.gradientDecoration(
          gradient: widget.gradient ?? LiquidGlassTheme.coolGradient,
          borderRadius: LiquidGlassTheme.radiusCapsule,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, color: Colors.white, size: 20),
              const SizedBox(width: LiquidGlassTheme.spacingSm),
            ],
            Text(
              widget.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else {
      // Secondary button with glass
      return ClipRRect(
        borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusCapsule),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: LiquidGlassTheme.glassBlur,
            sigmaY: LiquidGlassTheme.glassBlur,
          ),
          child: Container(
            width: widget.width,
            padding: widget.padding ??
                const EdgeInsets.symmetric(
                  horizontal: LiquidGlassTheme.spacingLg,
                  vertical: LiquidGlassTheme.spacingMd,
                ),
            decoration: LiquidGlassTheme.glassDecoration(
              borderRadius: LiquidGlassTheme.radiusCapsule,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: AppColors.darkGray, size: 20),
                  const SizedBox(width: LiquidGlassTheme.spacingSm),
                ],
                Text(
                  widget.text,
                  style: const TextStyle(
                    color: AppColors.darkGray,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}

/// Icon button with glass effect
class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final Gradient? gradient;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.size = 48,
    this.gradient,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton>
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
      onTapDown: widget.onPressed != null ? (_) => _controller.forward() : null,
      onTapUp: widget.onPressed != null
          ? (_) {
              _controller.reverse();
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 - (_controller.value * 0.05),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: LiquidGlassTheme.glassBlur,
              sigmaY: LiquidGlassTheme.glassBlur,
            ),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: widget.gradient != null
                  ? LiquidGlassTheme.gradientDecoration(
                      gradient: widget.gradient!,
                      borderRadius: widget.size / 2,
                    )
                  : LiquidGlassTheme.glassDecoration(
                      borderRadius: widget.size / 2,
                    ),
              child: Icon(
                widget.icon,
                color: widget.gradient != null
                    ? Colors.white
                    : (widget.color ?? AppColors.primaryBlue),
                size: widget.size * 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
