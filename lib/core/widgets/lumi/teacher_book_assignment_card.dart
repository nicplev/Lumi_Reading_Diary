import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';
import 'persistent_cached_image.dart';
import 'teacher_book_type_badge.dart';

enum TeacherBookCardAction {
  edit,
  swap,
  keepNextCycle,
  remove,
}

/// Lumi Design System - Teacher Book Assignment Card
///
/// Book cover (50x70) + title + subtitle + type badge + status indicator.
/// Per spec: 16px radius, card shadow, 16px padding.
class TeacherBookAssignmentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Color> coverGradient;
  final String? coverImageUrl;
  final String bookType; // 'decodable' or 'library'
  final String status; // 'completed', 'in_progress', 'new'
  final ValueChanged<TeacherBookCardAction>? onActionSelected;
  final VoidCallback? onTap;

  const TeacherBookAssignmentCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverGradient,
    this.coverImageUrl,
    required this.bookType,
    required this.status,
    this.onActionSelected,
    this.onTap,
  });

  Widget _buildStatusBadge() {
    switch (status) {
      case 'completed':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            color: Color(0xFFE8F5E9),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check,
                size: 12,
                color: Color(0xFF4CAF50),
              ),
              SizedBox(width: 4),
              Text(
                'Done',
                style: TeacherTypography.caption.copyWith(
                  color: Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
        );
      case 'in_progress':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.teacherPrimaryLight.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'In progress',
            style: TeacherTypography.caption.copyWith(
              color: AppColors.teacherPrimary,
            ),
          ),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'New',
            style: TeacherTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        );
    }
  }


  Widget _buildCover() {
    final hasCover = coverImageUrl != null &&
        coverImageUrl!.isNotEmpty &&
        coverImageUrl!.startsWith('http');

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 50,
        height: 70,
        decoration: BoxDecoration(
          color: coverGradient.isNotEmpty
              ? coverGradient.first
              : AppColors.teacherPrimaryLight,
        ),
        child: hasCover
            ? PersistentCachedImage(
                imageUrl: coverImageUrl!,
                fit: BoxFit.cover,
                fallback: const Center(
                  child: Icon(
                    Icons.menu_book,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              )
            : const Center(
                child: Icon(Icons.menu_book, color: Colors.white54, size: 20),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = onActionSelected != null;
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        border: Border.all(color: AppColors.teacherBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCover(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TeacherTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (canEdit)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.textSecondary.withValues(alpha: 0.4),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TeacherTypography.bodySmall.copyWith(
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TeacherBookTypeBadge(type: bookType),
                    _buildStatusBadge(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
      ),
    );
  }
}
