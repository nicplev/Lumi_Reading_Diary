import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Lumi Design System - Teacher Book Type Badge
///
/// "Decodable" (blue bg) or "Library" (green bg) pill badge.
/// Per spec: 12px radius, 10px horizontal / 4px vertical padding.
class TeacherBookTypeBadge extends StatelessWidget {
  final String type; // 'decodable' or 'library'

  const TeacherBookTypeBadge({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isDecodable = type.toLowerCase() == 'decodable';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDecodable
            ? LumiTokens.tintBlue.withValues(alpha: 0.58)
            : LumiTokens.tintGreen.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
      child: Text(
        isDecodable ? 'Decodable' : 'Library',
        style: LumiType.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: isDecodable ? LumiTokens.blue : LumiTokens.green,
        ),
      ),
    );
  }
}
