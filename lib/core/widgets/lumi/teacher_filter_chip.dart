import 'package:flutter/material.dart';
import '../../../theme/lumi_tokens.dart';

/// Lumi Design System - Teacher Filter Chip
///
/// Toggle chip with active (primary filled) and inactive (white) states.
/// Per spec: 20px radius, 16px horizontal / 8px vertical padding.
class TeacherFilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? activeColor;

  const TeacherFilterChip({
    super.key,
    required this.label,
    required this.isActive,
    this.onTap,
    this.icon,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = activeColor ?? LumiTokens.blue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? effectiveColor : LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            border: Border.all(
              color:
                  isActive ? effectiveColor : LumiTokens.rule,
              width: 1.2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: effectiveColor.withValues(alpha: 0.18),
                      blurRadius: 18,
                      spreadRadius: -8,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: isActive
                        ? LumiTokens.paper
                        : LumiTokens.muted,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isActive ? LumiTokens.paper : LumiTokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
