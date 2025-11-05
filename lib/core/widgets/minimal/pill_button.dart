import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Pill-shaped button with rounded corners
class PillButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isOutlined;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final bool isSmall;
  final bool fullWidth;

  const PillButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isOutlined = false,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.isSmall = false,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? MinimalTheme.primaryPurple;
    final fgColor = textColor ?? MinimalTheme.white;

    Widget buttonChild = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: isSmall ? 16 : 20),
          SizedBox(width: isSmall ? MinimalTheme.spaceS : MinimalTheme.spaceM),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: isSmall ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: isOutlined ? bgColor : fgColor,
          ),
        ),
      ],
    );

    if (fullWidth) {
      buttonChild = SizedBox(
        width: double.infinity,
        child: buttonChild,
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isOutlined ? Colors.transparent : bgColor,
        foregroundColor: fgColor,
        elevation: 0,
        padding: EdgeInsets.symmetric(
          vertical: isSmall ? 12 : 16,
          horizontal: fullWidth ? 0 : (isSmall ? 20 : 32),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
          side: isOutlined ? BorderSide(color: bgColor, width: 2) : BorderSide.none,
        ),
      ),
      child: buttonChild,
    );
  }
}

/// Small circular icon button
class IconPillButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;

  const IconPillButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? MinimalTheme.white,
        shape: BoxShape.circle,
        boxShadow: MinimalTheme.cardShadow(),
      ),
      child: IconButton(
        icon: Icon(icon),
        color: iconColor ?? MinimalTheme.textPrimary,
        iconSize: size * 0.5,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
