import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

/// Lumi Design System - Teacher Book Grid Item
///
/// 3-column grid item with gradient book cover and title.
/// Per spec: 12px radius, 80px cover height, 11px title.
class TeacherBookGridItem extends StatelessWidget {
  final String title;
  final List<Color> coverGradient;
  final VoidCallback? onTap;

  const TeacherBookGridItem({
    super.key,
    required this.title,
    required this.coverGradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
          boxShadow: TeacherDimensions.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Book cover gradient
            Container(
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: coverGradient,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.menu_book,
                  color: Colors.white54,
                  size: 28,
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.charcoal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
