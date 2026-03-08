import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../../theme/lumi_spacing.dart';
import '../../theme/lumi_borders.dart';

/// Lumi Design System - Primary Button
///
/// Default: Rose pink background, white text, pill shape (28pt radius)
/// Pass [color] for teacher/admin indigo variant.
/// Pass [borderRadius] to override pill shape (e.g. 14px for teacher buttons).
class LumiPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final Color? color;
  final BorderRadius? borderRadius;

  const LumiPrimaryButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = color ?? AppColors.rosePink;
    final shape = borderRadius != null
        ? RoundedRectangleBorder(borderRadius: borderRadius!)
        : LumiBorders.shapePill;

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: primaryColor.withValues(alpha: 0.4),
          padding: LumiPadding.button,
          shape: shape,
          elevation: 2,
          shadowColor: primaryColor.withValues(alpha: 0.3),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: LumiSpacing.xs),
                  ],
                  Text(
                    text,
                    style: LumiTextStyles.button(),
                  ),
                ],
              ),
      ),
    ).animate(
      target: onPressed != null && !isLoading ? 1 : 0,
    ).scale(
      duration: 150.ms,
      begin: const Offset(1, 1),
      end: const Offset(0.98, 0.98),
      curve: Curves.easeOut,
    );
  }
}

/// Lumi Design System - Secondary Button
///
/// Default: White background with rose pink border and text, pill shape
/// Pass [color] for teacher/admin indigo variant.
/// Pass [borderRadius] to override pill shape.
class LumiSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final Color? color;
  final BorderRadius? borderRadius;

  const LumiSecondaryButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = color ?? AppColors.rosePink;
    final br = borderRadius ?? LumiBorders.pill;
    final shape = RoundedRectangleBorder(
      borderRadius: br,
      side: BorderSide(color: accentColor, width: 2.0),
    );

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: accentColor,
          disabledForegroundColor: AppColors.charcoal.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 22,
          ),
          shape: shape,
          side: BorderSide(color: accentColor, width: 2.0),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: LumiSpacing.xs),
                  ],
                  Text(
                    text,
                    style: LumiTextStyles.button(color: accentColor),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Lumi Design System - Text Button
///
/// Transparent background with rose pink text.
/// Pass [color] for teacher/admin indigo variant.
class LumiTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool isLoading;
  final Color? color;

  const LumiTextButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.isLoading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final foregroundColor = color ?? AppColors.rosePink;

    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor,
        disabledForegroundColor: AppColors.charcoal.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(
          vertical: 8,
          horizontal: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: LumiBorders.small,
        ),
      ),
      child: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: LumiSpacing.xxs),
                ],
                Text(
                  text,
                  style: LumiTextStyles.button(color: foregroundColor),
                ),
              ],
            ),
    );
  }
}

/// Lumi Design System - Icon Button
///
/// Circular button with icon only.
class LumiIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? iconColor;
  final Color? backgroundColor;
  final double size;

  const LumiIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.iconColor,
    this.backgroundColor,
    this.size = 44.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: iconColor ?? AppColors.charcoal,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor ?? Colors.transparent,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// Lumi Design System - Floating Action Button
///
/// Default: Rose pink background. Pass [color] for teacher/admin variant.
class LumiFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? label;
  final bool isExtended;
  final Color? color;

  const LumiFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.isExtended = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? AppColors.rosePink;

    if (isExtended && label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          label!,
          style: LumiTextStyles.button(),
        ),
        backgroundColor: bgColor,
        foregroundColor: AppColors.white,
        elevation: 4,
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: bgColor,
      foregroundColor: AppColors.white,
      elevation: 4,
      child: Icon(icon),
    );
  }
}
