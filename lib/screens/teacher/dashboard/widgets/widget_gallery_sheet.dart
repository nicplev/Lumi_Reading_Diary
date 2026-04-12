import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
import '../models/widget_registry.dart';

/// Modal bottom sheet that lists inactive (available-to-add) dashboard widgets.
class WidgetGallerySheet extends StatelessWidget {
  final List<DashboardWidgetDefinition> availableWidgets;
  final ValueChanged<String> onAddWidget;

  const WidgetGallerySheet({
    super.key,
    required this.availableWidgets,
    required this.onAddWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.teacherBorder,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 20),
          Text('Add Widget', style: TeacherTypography.h3),
          const SizedBox(height: 18),
          if (availableWidgets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.widgets_rounded,
                      size: 40,
                      color: AppColors.textSecondary.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(
                    'All widgets are active',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ...availableWidgets.map((def) => _GalleryItem(
                  definition: def,
                  onAdd: () => onAddWidget(def.id),
                )),
        ],
      ),
    );
  }
}

class _GalleryItem extends StatelessWidget {
  final DashboardWidgetDefinition definition;
  final VoidCallback onAdd;

  const _GalleryItem({required this.definition, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.teacherBackground,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onAdd();
          },
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.teacherSurfaceTint,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  child: Icon(definition.icon,
                      size: 20, color: AppColors.teacherPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(definition.displayName,
                          style: TeacherTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(definition.description,
                          style: TeacherTypography.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.teacherPrimary,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 18, color: AppColors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
