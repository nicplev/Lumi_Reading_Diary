import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';
import 'teacher_book_type_badge.dart';

/// Lumi Design System - Teacher Book Assignment Card
///
/// Book cover (50x70) + title + subtitle + type badge + status indicator.
/// Per spec: 16px radius, card shadow, 16px padding.
class TeacherBookAssignmentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Color> coverGradient;
  final String bookType; // 'decodable' or 'library'
  final String status; // 'completed', 'in_progress', 'new'

  const TeacherBookAssignmentCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverGradient,
    required this.bookType,
    required this.status,
  });

  Widget _buildStatusIndicator() {
    switch (status) {
      case 'completed':
        return Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFE8F5E9),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            size: 16,
            color: Color(0xFF4CAF50),
          ),
        );
      case 'in_progress':
        return Text(
          'In progress',
          style: TeacherTypography.bodySmall.copyWith(
            color: AppColors.teacherPrimary,
          ),
        );
      default:
        return Text(
          'New',
          style: TeacherTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TeacherDimensions.paddingL),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Row(
        children: [
          // Book cover
          Container(
            width: 50,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: coverGradient,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Icon(Icons.menu_book, color: Colors.white54, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          // Book details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TeacherTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TeacherTypography.bodySmall,
                ),
                const SizedBox(height: 6),
                TeacherBookTypeBadge(type: bookType),
              ],
            ),
          ),
          // Status indicator
          _buildStatusIndicator(),
        ],
      ),
    );
  }
}
