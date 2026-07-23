import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../theme/lumi_tokens.dart';
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
  final Color? foregroundColor;
  final BorderRadius? borderRadius;
  final double elevation;

  /// Determinate progress, 0..1. When set alongside [isLoading] the button
  /// becomes a progress bar — a light tint of [color] that fills left to
  /// right with the solid colour — instead of a spinner. Use it when the
  /// wait is long enough that a spinner reads as "stuck" (a large audio
  /// upload), and leave it null when the work is quick.
  final double? progress;

  /// Replaces [text] while loading, e.g. "Uploading audio". Ignored when not
  /// loading. Deliberately a phase name rather than a percentage: the last
  /// stretch of a submit is a server round-trip with no measurable progress,
  /// so a number there would be invented.
  final String? loadingLabel;

  const LumiPrimaryButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.color,
    this.foregroundColor,
    this.borderRadius,
    this.elevation = 2,
    this.progress,
    this.loadingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = color ?? LumiTokens.red;
    final resolvedForegroundColor = foregroundColor ?? LumiTokens.paper;
    final shape = borderRadius != null
        ? RoundedRectangleBorder(borderRadius: borderRadius!)
        : LumiBorders.shapePill;

    if (isLoading && progress != null) {
      return _buildProgressBar(primaryColor, resolvedForegroundColor);
    }

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: resolvedForegroundColor,
          disabledBackgroundColor: primaryColor.withValues(alpha: 0.4),
          disabledForegroundColor:
              resolvedForegroundColor.withValues(alpha: 0.55),
          padding: LumiPadding.button,
          shape: shape,
          elevation: elevation,
          shadowColor: primaryColor.withValues(alpha: 0.3),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(resolvedForegroundColor),
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
                    style: LumiTextStyles.button(
                      color: resolvedForegroundColor,
                    ),
                  ),
                ],
              ),
      ),
    )
        .animate(
          target: onPressed != null && !isLoading ? 1 : 0,
        )
        .scale(
          duration: 150.ms,
          begin: const Offset(1, 1),
          end: const Offset(0.98, 0.98),
          curve: Curves.easeOut,
        );
  }

  /// Same footprint as the normal button so swapping in mid-press doesn't
  /// shift the layout. The track is a light tint of the button colour and
  /// the fill is the solid colour, so the bar reads as the button filling
  /// up rather than as a separate widget appearing.
  Widget _buildProgressBar(Color primaryColor, Color foreground) {
    // Clamped because a caller mapping phases onto a range can overshoot,
    // and a widthFactor above 1 throws.
    final value = progress!.clamp(0.0, 1.0);
    final radius = borderRadius ?? LumiBorders.pill;

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          // Deliberately stronger than the 0.4 disabled tint: the label sits
          // on the track before the fill reaches it, and white on a 0.4 tint
          // over cream is too faint to read.
          color: primaryColor.withValues(alpha: 0.45),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Animated so byte-level jumps from Storage arrive as a smooth
              // sweep rather than a stutter.
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                widthFactor: value,
                heightFactor: 1,
                child: ColoredBox(color: primaryColor),
              ),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    loadingLabel ?? text,
                    key: ValueKey(loadingLabel ?? text),
                    style: LumiTextStyles.button(color: foreground),
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
    final accentColor = color ?? LumiTokens.red;
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
          backgroundColor: LumiTokens.paper,
          foregroundColor: accentColor,
          disabledForegroundColor: LumiTokens.ink.withValues(alpha: 0.4),
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
    final foregroundColor = color ?? LumiTokens.red;

    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor,
        disabledForegroundColor: LumiTokens.ink.withValues(alpha: 0.4),
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

/// Variant for a dialog action button.
enum LumiDialogActionVariant {
  /// Neutral dismiss (Cancel / Not now). Muted foreground.
  cancel,

  /// Affirmative, non-destructive action (Save / Continue). Green foreground.
  confirm,

  /// Destructive action (Delete / Remove / Sign out). Red foreground.
  destructive,
}

/// Lumi Design System - Dialog Action
///
/// Bordered pill for use in `AlertDialog.actions` (and confirmation dialogs).
/// Dialogs across the app hand-rolled bare Material `TextButton`s with no border,
/// which read inconsistently and — via [LumiTextButton]'s red default — could
/// render a Cancel button in red. This gives every dialog the same outlined
/// treatment, with the foreground driven by an explicit [variant] rather than an
/// inherited default.
class LumiDialogAction extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final LumiDialogActionVariant variant;

  const LumiDialogAction({
    super.key,
    required this.onPressed,
    required this.label,
    this.variant = LumiDialogActionVariant.confirm,
  });

  Color get _foreground {
    switch (variant) {
      case LumiDialogActionVariant.cancel:
        return LumiTokens.muted;
      case LumiDialogActionVariant.confirm:
        return LumiTokens.green;
      case LumiDialogActionVariant.destructive:
        return LumiTokens.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _foreground;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: const BorderSide(color: LumiTokens.rule),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        ),
      ),
      child: Text(label, style: LumiTextStyles.button(color: foreground)),
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
        color: iconColor ?? LumiTokens.ink,
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
    // Rec 10: default to the AA-accessible variant so white-on-pink FABs
    // meet contrast. `rosePink` is preserved for decorative fills only.
    final bgColor = color ?? LumiTokens.red;

    if (isExtended && label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          label!,
          style: LumiTextStyles.button(),
        ),
        backgroundColor: bgColor,
        foregroundColor: LumiTokens.paper,
        elevation: 4,
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: bgColor,
      foregroundColor: LumiTokens.paper,
      elevation: 4,
      child: Icon(icon),
    );
  }
}
