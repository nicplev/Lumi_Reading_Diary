import 'package:flutter/material.dart';

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
        color: isDecodable ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isDecodable ? 'Decodable' : 'Library',
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDecodable ? const Color(0xFF1976D2) : const Color(0xFF388E3C),
        ),
      ),
    );
  }
}
