import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';
import '../../../data/models/reading_level_event.dart';
import '../../../data/models/reading_level_option.dart';
import '../../../services/reading_level_service.dart';
import 'teacher_reading_level_pill.dart';

class ReadingLevelHistorySheet extends StatelessWidget {
  const ReadingLevelHistorySheet({
    super.key,
    required this.studentName,
    required this.eventsStream,
    required this.levelOptions,
    required this.readingLevelService,
  });

  final String studentName;
  final Stream<List<ReadingLevelEvent>> eventsStream;
  final List<ReadingLevelOption> levelOptions;
  final ReadingLevelService readingLevelService;

  static Future<void> show(
    BuildContext context, {
    required String studentName,
    required Stream<List<ReadingLevelEvent>> eventsStream,
    required List<ReadingLevelOption> levelOptions,
    required ReadingLevelService readingLevelService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReadingLevelHistorySheet(
        studentName: studentName,
        eventsStream: eventsStream,
        levelOptions: levelOptions,
        readingLevelService: readingLevelService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Reading Level History', style: TeacherTypography.h3),
          const SizedBox(height: 6),
          Text(
            studentName,
            style: TeacherTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<ReadingLevelEvent>>(
              stream: eventsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final events = snapshot.data!;
                if (events.isEmpty) {
                  return Center(
                    child: Text(
                      'No level changes recorded yet.',
                      style: TeacherTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final fromLabel = event.fromLevel != null
                        ? readingLevelService.formatCompactLabel(
                            event.fromLevel,
                            options: levelOptions,
                            unknownLabel: event.fromLevel!,
                          )
                        : 'None';
                    final toLabel = event.toLevel != null
                        ? readingLevelService.formatCompactLabel(
                            event.toLevel,
                            options: levelOptions,
                            unknownLabel: event.toLevel!,
                          )
                        : 'Cleared';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.teacherBackground,
                        borderRadius: BorderRadius.circular(
                          TeacherDimensions.radiusL,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              TeacherReadingLevelPill(label: fromLabel),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              TeacherReadingLevelPill(
                                label: toLabel,
                                isUnset: event.toLevel == null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            event.changedByName.isNotEmpty
                                ? event.changedByName
                                : event.changedByUserId,
                            style: TeacherTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTimestamp(event.createdAt),
                            style: TeacherTypography.bodySmall,
                          ),
                          if (event.reason != null &&
                              event.reason!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              event.reason!,
                              style: TeacherTypography.bodySmall.copyWith(
                                color: AppColors.charcoal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime value) {
    final month = _monthName(value.month);
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month ${value.day}, ${value.year} at ${value.hour}:$minute';
  }

  String _monthName(int month) {
    const names = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }
}
