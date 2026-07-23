import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/student_avatar.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../data/models/user_model.dart';
import 'dashboard_student_nav.dart';

/// Mini leaderboard showing the top 5 students by total minutes read this week.
class DashboardTopReadersCard extends StatelessWidget {
  final List<ReadingLogModel> weeklyLogs;
  final List<StudentModel> students;
  final UserModel teacher;
  final ClassModel classModel;

  const DashboardTopReadersCard({
    super.key,
    required this.weeklyLogs,
    required this.students,
    required this.teacher,
    required this.classModel,
  });

  @override
  Widget build(BuildContext context) {
    final studentMap = {for (final student in students) student.id: student};

    // Aggregate minutes by student
    final minutesByStudent = <String, int>{};
    for (final log in weeklyLogs) {
      // Historical/legacy cleanup can leave a log behind after its student is
      // no longer resolvable. It must not take a leaderboard place away from a
      // current roster member.
      if (!studentMap.containsKey(log.studentId)) continue;
      minutesByStudent.update(
        log.studentId,
        (v) => v + log.minutesRead,
        ifAbsent: () => log.minutesRead,
      );
    }

    final sorted = minutesByStudent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();

    final maxMinutes = top.isNotEmpty ? top.first.value : 1;

    return Container(
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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flexible so a longer title degrades gracefully instead of the
              // Row overflowing (two unconstrained Texts can't wrap).
              Flexible(
                child: Text('Top Readers', style: LumiType.subhead),
              ),
              const SizedBox(width: 8),
              Text('This week',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted)),
            ],
          ),
          const SizedBox(height: 2),
          Text('Ranked by minutes read',
              style: LumiType.caption.copyWith(color: LumiTokens.muted)),
          const SizedBox(height: 16),

          if (top.isEmpty)
            _buildEmptyState()
          else
            ...List.generate(top.length, (i) {
              final entry = top[i];
              final student = studentMap[entry.key];
              return _buildRow(
                context: context,
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
    required BuildContext context,
    required int rank,
    required StudentModel? student,
    required int minutes,
    required double fraction,
  }) {
    final rankColor = switch (rank) {
      1 => LumiTokens.yellow, // gold
      2 => LumiTokens.muted,
      3 => LumiTokens.muted,
      _ => LumiTokens.muted.withValues(alpha: 0.45),
    };
    final isTopThree = rank <= 3;
    final name = student?.firstNameWithLastInitial ?? 'Student unavailable';

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          // Rank as plain bold text — no circle, no clutter
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: LumiType.caption.copyWith(
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
                  initial: '–',
                  avatarColor: LumiTokens.tintBlue,
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
                        style: LumiType.body.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$minutes min',
                      style: LumiType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: LumiTokens.ink,
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
                    backgroundColor: LumiTokens.rule,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isTopThree
                          ? LumiTokens.blue
                          : LumiTokens.blue.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const DashboardRowChevron(),
        ],
      ),
    );

    // Null-student rows (a legacy log with no resolvable student) stay inert,
    // matching Recent Reading.
    if (student == null) return row;
    final resolved = student;
    return InkWell(
      onTap: () => pushStudentDetail(
        context,
        teacher: teacher,
        student: resolved,
        classModel: classModel,
      ),
      borderRadius: BorderRadius.circular(12),
      child: row,
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.emoji_events_rounded,
                size: 32, color: LumiTokens.muted.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              'No reading logged yet this week',
              style: LumiType.caption,
            ),
          ],
        ),
      ),
    );
  }
}
