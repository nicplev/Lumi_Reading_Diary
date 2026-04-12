import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
import '../../../../data/models/reading_group_model.dart';
import '../../../../data/models/reading_log_model.dart';

/// Compares reading groups' engagement this week side-by-side.
class DashboardGroupComparisonCard extends StatelessWidget {
  final List<ReadingLogModel> weeklyLogs;
  final List<ReadingGroupModel> readingGroups;

  const DashboardGroupComparisonCard({
    super.key,
    required this.weeklyLogs,
    required this.readingGroups,
  });

  @override
  Widget build(BuildContext context) {
    if (readingGroups.isEmpty) return _buildCard(child: _buildEmptyState());

    // Compute stats per group
    final groupStats = <String, _GroupStats>{};
    double maxAvg = 0;

    for (final group in readingGroups) {
      final groupLogs = weeklyLogs
          .where((l) => group.studentIds.contains(l.studentId))
          .toList();

      // Aggregate minutes by student
      final minutesByStudent = <String, int>{};
      for (final log in groupLogs) {
        minutesByStudent.update(
          log.studentId,
          (v) => v + log.minutesRead,
          ifAbsent: () => log.minutesRead,
        );
      }

      final totalStudents = group.studentIds.length;
      final totalMinutes =
          minutesByStudent.values.fold<int>(0, (a, b) => a + b);
      final avgMinutes =
          totalStudents > 0 ? totalMinutes / totalStudents : 0.0;

      // % of students who read at all this week
      final activeCount = minutesByStudent.length;
      final activePercent =
          totalStudents > 0 ? (activeCount / totalStudents * 100).round() : 0;

      if (avgMinutes > maxAvg) maxAvg = avgMinutes;

      groupStats[group.id] = _GroupStats(
        avgMinutes: avgMinutes,
        activePercent: activePercent,
        activeCount: activeCount,
        totalStudents: totalStudents,
      );
    }

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...readingGroups.map((group) {
            final stats = groupStats[group.id];
            if (stats == null) return const SizedBox.shrink();
            return _buildGroupRow(group, stats, maxAvg);
          }),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reading Groups',
                  style: TeacherTypography.sectionHeader
                      .copyWith(color: AppColors.teacherPrimary)),
              Text('This week', style: TeacherTypography.caption),
            ],
          ),
          const SizedBox(height: 16),
          child,
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
            Icon(Icons.groups_rounded,
                size: 32,
                color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              'No reading groups set up yet',
              style: TeacherTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupRow(
      ReadingGroupModel group, _GroupStats stats, double maxAvg) {
    final color = _parseColor(group.color);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group name + dot
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.name,
                  style: TeacherTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${stats.activeCount}/${stats.totalStudents} active',
                style: TeacherTypography.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Avg minutes bar
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text('Avg min',
                    style: TeacherTypography.caption
                        .copyWith(fontSize: 11)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxAvg > 0 ? stats.avgMinutes / maxAvg : 0,
                    minHeight: 8,
                    backgroundColor: color.withValues(alpha: 0.08),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.7)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text(
                  '${stats.avgMinutes.round()}',
                  textAlign: TextAlign.right,
                  style: TeacherTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Active % bar
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text('Active %',
                    style: TeacherTypography.caption
                        .copyWith(fontSize: 11)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stats.activePercent / 100,
                    minHeight: 8,
                    backgroundColor: color.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        color.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text(
                  '${stats.activePercent}%',
                  textAlign: TextAlign.right,
                  style: TeacherTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.teacherPrimary;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.teacherPrimary;
    }
  }
}

class _GroupStats {
  final double avgMinutes;
  final int activePercent;
  final int activeCount;
  final int totalStudents;

  const _GroupStats({
    required this.avgMinutes,
    required this.activePercent,
    required this.activeCount,
    required this.totalStudents,
  });
}
