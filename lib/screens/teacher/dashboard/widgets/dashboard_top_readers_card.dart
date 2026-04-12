import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
import '../../../../core/widgets/lumi/student_avatar.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../data/models/student_model.dart';

/// Mini leaderboard showing the top 5 students by total minutes read this week.
class DashboardTopReadersCard extends StatelessWidget {
  final List<ReadingLogModel> weeklyLogs;
  final List<StudentModel> students;

  const DashboardTopReadersCard({
    super.key,
    required this.weeklyLogs,
    required this.students,
  });

  @override
  Widget build(BuildContext context) {
    // Aggregate minutes by student
    final minutesByStudent = <String, int>{};
    for (final log in weeklyLogs) {
      minutesByStudent.update(
        log.studentId,
        (v) => v + log.minutesRead,
        ifAbsent: () => log.minutesRead,
      );
    }

    final sorted = minutesByStudent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();

    final studentMap = {for (final s in students) s.id: s};
    final maxMinutes = top.isNotEmpty ? top.first.value : 1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.04),
            blurRadius: 16,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Top Readers',
                  style: TeacherTypography.sectionHeader
                      .copyWith(color: AppColors.teacherPrimary)),
              Text('This week', style: TeacherTypography.caption),
            ],
          ),
          const SizedBox(height: 16),

          if (top.isEmpty)
            _buildEmptyState()
          else
            ...List.generate(top.length, (i) {
              final entry = top[i];
              final student = studentMap[entry.key];
              return _buildRow(
                rank: i + 1,
                student: student,
                minutes: entry.value,
                fraction: entry.value / maxMinutes,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRow({
    required int rank,
    required StudentModel? student,
    required int minutes,
    required double fraction,
  }) {
    final rankColor = switch (rank) {
      1 => const Color(0xFFFFB300), // deep amber-gold — readable
      2 => const Color(0xFF9E9E9E), // medium grey
      3 => const Color(0xFFBF7E45), // warm bronze
      _ => AppColors.textSecondary.withValues(alpha: 0.45),
    };
    final isTopThree = rank <= 3;
    final name = student?.firstName ?? 'Unknown';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          // Rank as plain bold text — no circle, no clutter
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TeacherTypography.caption.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Avatar — hash-derived color per student via fromStudent
          student != null
              ? StudentAvatar.fromStudent(student, size: 32)
              : StudentAvatar(
                  characterId: null,
                  initial: '?',
                  avatarColor: AppColors.teacherSurfaceTint,
                  size: 32,
                ),
          const SizedBox(width: 10),
          // Name + minutes + bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TeacherTypography.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${minutes}m',
                      style: TeacherTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.teacherPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 7,
                    backgroundColor:
                        AppColors.teacherBorder.withValues(alpha: 0.4),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isTopThree
                          ? AppColors.teacherPrimary
                          : AppColors.teacherAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.emoji_events_rounded,
                size: 32,
                color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              'No reading logged yet this week',
              style: TeacherTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
