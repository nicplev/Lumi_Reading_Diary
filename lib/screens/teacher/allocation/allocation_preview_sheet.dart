import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/teacher_constants.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_card.dart';
import '../../../data/models/allocation_model.dart';

/// Bottom sheet shown before saving an allocation. Displays a summary
/// of the allocation for teacher confirmation.
class AllocationPreviewSheet extends StatelessWidget {
  const AllocationPreviewSheet({
    super.key,
    required this.type,
    required this.cadence,
    required this.targetMinutes,
    required this.startDate,
    required this.endDate,
    required this.bookTitles,
    required this.levelStart,
    required this.levelEnd,
    required this.studentCount,
    required this.isWholeClass,
    required this.isEditing,
    required this.formatLevelRange,
    required this.onConfirm,
  });

  final AllocationType type;
  final AllocationCadence cadence;
  final int targetMinutes;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> bookTitles;
  final String? levelStart;
  final String? levelEnd;
  final int studentCount;
  final bool isWholeClass;
  final bool isEditing;
  final String Function(String?, String?) formatLevelRange;
  final VoidCallback onConfirm;

  String get _typeLabel {
    switch (type) {
      case AllocationType.freeChoice:
        return 'Free Choice';
      case AllocationType.byLevel:
        return 'By Reading Level';
      case AllocationType.byTitle:
        return 'Specific Books';
    }
  }

  String get _cadenceLabel {
    switch (cadence) {
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(TeacherDimensions.radiusXL)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEditing ? 'Update Allocation' : 'Confirm Allocation',
              style: TeacherTypography.h2,
            ),
            const SizedBox(height: 4),
            Text(
              'Review the details before saving.',
              style: TeacherTypography.bodySmall,
            ),
            const SizedBox(height: 16),

            // Summary card
            LumiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow(Icons.book, 'Type', _typeLabel),
                  if (type == AllocationType.byTitle && bookTitles.isNotEmpty)
                    _summaryRow(
                      Icons.menu_book,
                      'Books',
                      bookTitles.length == 1
                          ? bookTitles.first
                          : '${bookTitles.first} +${bookTitles.length - 1} more',
                    ),
                  if (type == AllocationType.byLevel)
                    _summaryRow(
                      Icons.trending_up,
                      'Level Range',
                      formatLevelRange(levelStart, levelEnd),
                    ),
                  const Divider(height: 20),
                  _summaryRow(
                    Icons.schedule,
                    'Schedule',
                    '$_cadenceLabel · $targetMinutes min',
                  ),
                  _summaryRow(
                    Icons.calendar_today,
                    'Dates',
                    '${DateFormat('MMM dd').format(startDate)} – ${DateFormat('MMM dd').format(endDate)}',
                  ),
                  const Divider(height: 20),
                  _summaryRow(
                    Icons.groups,
                    'Students',
                    isWholeClass
                        ? 'Whole class ($studentCount)'
                        : '$studentCount selected',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Buttons
            LumiPrimaryButton(
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
              text: isEditing ? 'Update Allocation' : 'Create Allocation',
              isFullWidth: true,
              color: AppColors.teacherPrimary,
            ),
            const SizedBox(height: 8),
            Center(
              child: LumiTextButton(
                onPressed: () => Navigator.of(context).pop(),
                text: 'Back to Edit',
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.teacherPrimary),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TeacherTypography.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TeacherTypography.bodyMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
