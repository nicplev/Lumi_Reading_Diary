import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_spacing.dart';
import '../../theme/lumi_borders.dart';

/// Lumi Design System - Card Component
///
/// White background, 16pt radius, subtle shadow
/// Padding: 20pt all sides
///
/// Usage:
/// ```dart
/// LumiCard(
///   child: Text('Card content'),
/// )
/// ```
class LumiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool isHighlighted;
  final bool showShadow;

  const LumiCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.isHighlighted = false,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final container = Container(
      padding: padding ?? LumiPadding.card,
      decoration: BoxDecoration(
        color: isHighlighted ? AppColors.skyBlue : AppColors.white,
        borderRadius: LumiBorders.large,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.charcoal.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: LumiBorders.large,
        child: container,
      ).animate(
        target: 1,
      ).scale(
        duration: 200.ms,
        begin: const Offset(1, 1),
        end: const Offset(1.02, 1.02),
        curve: Curves.easeOut,
      );
    }

    return container;
  }
}

/// Lumi Design System - Compact Card
///
/// Smaller padding for list items
///
/// Usage:
/// ```dart
/// LumiCompactCard(
///   child: ListTile(...),
/// )
/// ```
class LumiCompactCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const LumiCompactCard({
    super.key,
    required this.child,
    this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return LumiCard(
      padding: LumiPadding.allS,
      onTap: onTap,
      isHighlighted: isHighlighted,
      child: child,
    );
  }
}

/// Lumi Design System - Info Card
///
/// Card with colored background for different message types
///
/// Usage:
/// ```dart
/// LumiInfoCard(
///   type: LumiInfoCardType.success,
///   title: 'Success!',
///   message: 'Your action was completed.',
/// )
/// ```
enum LumiInfoCardType {
  success,
  warning,
  error,
  info,
}

class LumiInfoCard extends StatelessWidget {
  final LumiInfoCardType type;
  final String? title;
  final String message;
  final IconData? icon;
  final VoidCallback? onDismiss;

  const LumiInfoCard({
    super.key,
    required this.type,
    required this.message,
    this.title,
    this.icon,
    this.onDismiss,
  });

  Color get _backgroundColor {
    switch (type) {
      case LumiInfoCardType.success:
        return AppColors.mintGreen;
      case LumiInfoCardType.warning:
        return AppColors.softYellow;
      case LumiInfoCardType.error:
        return AppColors.error.withOpacity(0.1);
      case LumiInfoCardType.info:
        return AppColors.skyBlue;
    }
  }

  Color get _iconColor {
    switch (type) {
      case LumiInfoCardType.success:
        return AppColors.success;
      case LumiInfoCardType.warning:
        return AppColors.warning;
      case LumiInfoCardType.error:
        return AppColors.error;
      case LumiInfoCardType.info:
        return AppColors.info;
    }
  }

  IconData get _defaultIcon {
    switch (type) {
      case LumiInfoCardType.success:
        return Icons.check_circle_outline;
      case LumiInfoCardType.warning:
        return Icons.warning_amber_outlined;
      case LumiInfoCardType.error:
        return Icons.error_outline;
      case LumiInfoCardType.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: LumiPadding.allS,
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: LumiBorders.medium,
        border: Border.all(
          color: _iconColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? _defaultIcon,
            color: _iconColor,
            size: 24,
          ),
          const SizedBox(width: LumiSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: LumiSpacing.xxs),
                ],
                Text(
                  message,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.charcoal.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: LumiSpacing.xs),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.charcoal.withOpacity(0.6),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lumi Design System - Empty State Card
///
/// Card showing empty state with illustration, message, and action
///
/// Usage:
/// ```dart
/// LumiEmptyCard(
///   icon: Icons.book_outlined,
///   title: 'No books yet',
///   message: 'Start your reading journey',
///   actionText: 'Add Book',
///   onAction: () => addBook(),
/// )
/// ```
class LumiEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionText;
  final VoidCallback? onAction;

  const LumiEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return LumiCard(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.rosePink.withOpacity(0.1),
                borderRadius: LumiBorders.circular,
              ),
              child: Icon(
                icon,
                size: 40,
                color: AppColors.rosePink,
              ),
            ),
            const SizedBox(height: LumiSpacing.m),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LumiSpacing.xs),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.charcoal.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: LumiSpacing.m),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.rosePink,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: LumiBorders.medium,
                  ),
                ),
                child: Text(
                  actionText!,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
