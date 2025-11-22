import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../../theme/lumi_spacing.dart';
import '../../theme/lumi_borders.dart';

/// Lumi Design System - Primary Button
///
/// Rose pink background, white text, 16pt padding vertical, 24pt horizontal
/// Border radius: 12pt, with shadow
///
/// Usage:
/// ```dart
/// LumiPrimaryButton(
///   onPressed: () => doSomething(),
///   text: 'Submit',
/// )
/// ```
class LumiPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;

  const LumiPrimaryButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.rosePink,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.rosePink.withOpacity(0.4),
          padding: LumiPadding.button,
          shape: LumiBorders.shapeMedium,
          elevation: 2,
          shadowColor: AppColors.rosePink.withOpacity(0.3),
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
      // Subtle scale animation on tap
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
/// White background with rose pink border and text
/// Border radius: 12pt
///
/// Usage:
/// ```dart
/// LumiSecondaryButton(
///   onPressed: () => doSomething(),
///   text: 'Cancel',
/// )
/// ```
class LumiSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;

  const LumiSecondaryButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.rosePink,
          disabledForegroundColor: AppColors.charcoal.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(
            vertical: 14, // Adjusted for 2pt border
            horizontal: 22,
          ),
          shape: LumiBorders.shapePrimaryBorder,
          side: const BorderSide(
            color: AppColors.rosePink,
            width: 2.0,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.rosePink),
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
                    style: LumiTextStyles.button(color: AppColors.rosePink),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Lumi Design System - Text Button
///
/// Transparent background with rose pink text
/// Shows background tint on hover
///
/// Usage:
/// ```dart
/// LumiTextButton(
///   onPressed: () => doSomething(),
///   text: 'Learn More',
/// )
/// ```
class LumiTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool isLoading;

  const LumiTextButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.rosePink,
        disabledForegroundColor: AppColors.charcoal.withOpacity(0.4),
        padding: const EdgeInsets.symmetric(
          vertical: 8,
          horizontal: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: LumiBorders.small,
        ),
      ),
      child: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.rosePink),
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
                  style: LumiTextStyles.button(color: AppColors.rosePink),
                ),
              ],
            ),
    );
  }
}

/// Lumi Design System - Icon Button
///
/// Circular button with icon only
/// Used for actions like close, back, etc.
///
/// Usage:
/// ```dart
/// LumiIconButton(
///   onPressed: () => Navigator.pop(context),
///   icon: Icons.close,
/// )
/// ```
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
/// Circular FAB with rose pink background
///
/// Usage:
/// ```dart
/// LumiFab(
///   onPressed: () => addItem(),
///   icon: Icons.add,
/// )
/// ```
class LumiFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? label;
  final bool isExtended;

  const LumiFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.isExtended = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isExtended && label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          label!,
          style: LumiTextStyles.button(),
        ),
        backgroundColor: AppColors.rosePink,
        foregroundColor: AppColors.white,
        elevation: 4,
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: AppColors.rosePink,
      foregroundColor: AppColors.white,
      elevation: 4,
      child: Icon(icon),
    );
  }
}
