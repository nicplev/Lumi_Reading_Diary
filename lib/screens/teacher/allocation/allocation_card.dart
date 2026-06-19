import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
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
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
          border: Border.all(color: LumiTokens.rule),
          boxShadow: LumiTokens.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type pill
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: LumiTokens.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
              ),
              child: Text(
                _typeLabel,
                style: LumiType.caption.copyWith(
                  color: LumiTokens.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _title,
              style: LumiType.subhead,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${allocation.targetMinutes} min · $_cadenceLabel',
              style: LumiType.caption,
            ),
            const SizedBox(height: 12),

            // Date range
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isExpiring
                    ? LumiTokens.orange.withValues(alpha: 0.08)
                    : LumiTokens.cream,
                borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
                border: Border.all(
                  color: isExpiring
                      ? LumiTokens.orange.withValues(alpha: 0.3)
                      : LumiTokens.rule,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isExpiring ? LumiTokens.orange : LumiTokens.muted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat('MMM dd').format(allocation.startDate)} – ${DateFormat('MMM dd').format(allocation.endDate)}',
                    style: LumiType.caption.copyWith(
                      color: isExpiring ? LumiTokens.orange : LumiTokens.muted,
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
                        color: LumiTokens.orange,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusPill),
                      ),
                      child: Text(
                        'Expires soon',
                        style: LumiType.caption.copyWith(
                          color: LumiTokens.paper,
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
                const Icon(Icons.groups, size: 16, color: LumiTokens.muted),
                const SizedBox(width: 8),
                Text(
                  allocation.isForWholeClass
                      ? 'Whole class'
                      : '${allocation.studentIds.length} ${allocation.studentIds.length == 1 ? 'student' : 'students'}',
                  style: LumiType.caption,
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
                      foregroundColor: LumiTokens.green,
                      side: const BorderSide(color: LumiTokens.rule),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
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
                      foregroundColor: LumiTokens.red,
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
