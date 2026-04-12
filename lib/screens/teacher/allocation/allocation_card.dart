import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/teacher_constants.dart';
import '../../../core/widgets/lumi/lumi_card.dart';
import '../../../data/models/allocation_model.dart';

class AllocationCard extends StatelessWidget {
  final AllocationModel allocation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String Function(String?, String?) levelRangeFormatter;

  const AllocationCard({
    super.key,
    required this.allocation,
    required this.onEdit,
    required this.onDelete,
    required this.levelRangeFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final daysRemaining = allocation.endDate.difference(DateTime.now()).inDays;
    final isExpiring = daysRemaining <= 2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LumiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge + title
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.teacherPrimaryLight,
                    borderRadius: BorderRadius.circular(
                        TeacherDimensions.radiusRound),
                  ),
                  child: Text(
                    _typeLabel,
                    style: TeacherTypography.caption.copyWith(
                      color: AppColors.teacherPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _title,
                  style: TeacherTypography.h3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${allocation.targetMinutes} min · $_cadenceLabel',
                  style: TeacherTypography.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Date range
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isExpiring
                    ? AppColors.warning.withValues(alpha: 0.08)
                    : AppColors.background,
                borderRadius:
                    BorderRadius.circular(TeacherDimensions.radiusS),
                border: isExpiring
                    ? Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isExpiring
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat('MMM dd').format(allocation.startDate)} – ${DateFormat('MMM dd').format(allocation.endDate)}',
                    style: TeacherTypography.bodySmall.copyWith(
                      color: isExpiring
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      fontWeight:
                          isExpiring ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (isExpiring) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(
                            TeacherDimensions.radiusRound),
                      ),
                      child: Text(
                        'Expires soon',
                        style: TeacherTypography.caption.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Students row
            Row(
              children: [
                Icon(Icons.groups,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  allocation.isForWholeClass
                      ? 'Whole class'
                      : '${allocation.studentIds.length} ${allocation.studentIds.length == 1 ? 'student' : 'students'}',
                  style: TeacherTypography.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.teacherPrimary,
                      side: BorderSide(color: AppColors.teacherBorder),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            TeacherDimensions.radiusM),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _typeLabel {
    switch (allocation.type) {
      case AllocationType.freeChoice:
        return 'Free Choice';
      case AllocationType.byLevel:
        return 'By Level';
      case AllocationType.byTitle:
        return 'Specific Books';
    }
  }

  String get _title {
    switch (allocation.type) {
      case AllocationType.byLevel:
        return levelRangeFormatter(
            allocation.levelStart, allocation.levelEnd);
      case AllocationType.byTitle:
        final items = allocation.activeAssignmentItems;
        if (items.isNotEmpty) {
          return items.length == 1
              ? items.first.title
              : '${items.first.title} +${items.length - 1} more';
        }
        if (allocation.bookTitles != null &&
            allocation.bookTitles!.isNotEmpty) {
          return allocation.bookTitles!.length == 1
              ? allocation.bookTitles!.first
              : '${allocation.bookTitles!.first} +${allocation.bookTitles!.length - 1} more';
        }
        return 'Specific Books';
      case AllocationType.freeChoice:
        return 'Free Choice Reading';
    }
  }

  String get _cadenceLabel {
    switch (allocation.cadence) {
      case AllocationCadence.daily:
        return 'Daily';
      case AllocationCadence.weekly:
        return 'Weekly';
      case AllocationCadence.fortnightly:
        return 'Fortnightly';
      case AllocationCadence.custom:
        return 'Custom';
    }
  }
}
