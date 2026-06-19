import 'package:flutter/material.dart';
import '../../../theme/lumi_tokens.dart';

/// Lumi Design System - Teacher Settings Item
///
/// 36x36 soft icon tile + label + trailing (a muted chevron by default, or a
/// supplied widget like a status badge or toggle).
class TeacherSettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color? iconColor;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const TeacherSettingsItem({
    super.key,
    required this.icon,
    required this.iconBgColor,
    this.iconColor,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBgColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
              ),
              child: Icon(
                icon,
                size: 22,
                color: iconColor ?? iconBgColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: LumiTokens.ink,
                ),
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: LumiTokens.muted,
                ),
          ],
        ),
      ),
    );
  }
}
