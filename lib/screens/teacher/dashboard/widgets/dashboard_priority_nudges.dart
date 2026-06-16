import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/student_avatar.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../data/models/user_model.dart';

/// Dashboard Priority Nudges
///
/// Conditional section showing up to 3 actionable items:
/// - Inactivity nudges (students who haven't read in 3+ days)
/// - Milestone celebrations (streaks, book counts)
///
/// Smart suppression: inactivity nudges hidden on Mon/Tue.
class DashboardPriorityNudges extends StatelessWidget {
  final ClassModel classModel;
  final UserModel teacher;
  final List<StudentModel> students;
  final VoidCallback? onSeeAll;

  const DashboardPriorityNudges({
    super.key,
    required this.classModel,
    required this.teacher,
    required this.students,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final weekday = DateTime.now().weekday;
    final suppressInactivity = weekday <= 2; // Mon = 1, Tue = 2

    final nudges = _nudgeItemsFor(students, suppressInactivity);
    final displayNudges = nudges.take(3).toList();
    final remaining = nudges.length - 3;

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
          Text('Needs attention', style: LumiType.subhead),
          const SizedBox(height: 16),
          if (nudges.isEmpty)
            _buildEmptyState()
          else
            ...displayNudges.map((nudge) => _NudgeRow(
                  nudge: nudge,
                  onTap: () => _navigateToStudent(context, nudge.student),
                )),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: onSeeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '+ $remaining more',
                    style: LumiType.caption.copyWith(
                      color: LumiTokens.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 32, color: LumiTokens.green.withValues(alpha: 0.7)),
            const SizedBox(height: 10),
            Text(
              "You're all caught up",
              style: LumiType.body.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'No students need a nudge right now',
              style: LumiType.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static List<_NudgeItem> _nudgeItemsFor(
      List<StudentModel> students, bool suppressInactivity) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<_NudgeItem> nudges = [];

    for (final student in students) {
      final stats = student.stats;

      // Inactivity nudges
      if (!suppressInactivity) {
        if (stats?.lastReadingDate == null) {
          nudges.add(_NudgeItem(
            student: student,
            type: _NudgeType.inactivity,
            message: 'No reading logged yet',
            priority: 0,
            isUrgent: true,
          ));
        } else {
          final lastRead = DateTime(
            stats!.lastReadingDate!.year,
            stats.lastReadingDate!.month,
            stats.lastReadingDate!.day,
          );
          final daysSince = today.difference(lastRead).inDays;
          if (daysSince >= 3) {
            nudges.add(_NudgeItem(
              student: student,
              type: _NudgeType.inactivity,
              message: 'Last read $daysSince days ago',
              priority: daysSince >= 6 ? 0 : 1,
              isUrgent: daysSince >= 6,
            ));
          }
        }
      }

      // Milestone celebrations
      if (stats != null) {
        if (stats.currentStreak == 7 ||
            stats.currentStreak == 14 ||
            stats.currentStreak == 30) {
          nudges.add(_NudgeItem(
            student: student,
            type: _NudgeType.milestone,
            message: '${stats.currentStreak}-day reading streak! 🔥',
            priority: 2,
          ));
        }
        if (stats.totalBooksRead == 10 ||
            stats.totalBooksRead == 25 ||
            stats.totalBooksRead == 50) {
          nudges.add(_NudgeItem(
            student: student,
            type: _NudgeType.milestone,
            message: '${stats.totalBooksRead} books read! 📚',
            priority: 2,
          ));
        }
      }
    }

    // Sort: inactivity (urgent first) then milestones
    nudges.sort((a, b) => a.priority.compareTo(b.priority));
    return nudges;
  }

  void _navigateToStudent(BuildContext context, StudentModel student) {
    context.push(
      '/teacher/student-detail/${student.id}',
      extra: {
        'teacher': teacher,
        'student': student,
        'classModel': classModel,
      },
    );
  }
}

enum _NudgeType { inactivity, milestone }

class _NudgeItem {
  final StudentModel student;
  final _NudgeType type;
  final String message;
  final int priority;
  final bool isUrgent;

  _NudgeItem({
    required this.student,
    required this.type,
    required this.message,
    required this.priority,
    this.isUrgent = false,
  });
}

class _NudgeRow extends StatelessWidget {
  final _NudgeItem nudge;
  final VoidCallback onTap;

  const _NudgeRow({
    required this.nudge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final student = nudge.student;
    final isMilestone = nudge.type == _NudgeType.milestone;

    final avatarColor =
        isMilestone ? LumiTokens.tintYellow : LumiTokens.tintBlue;

    final messageColor = nudge.isUrgent ? LumiTokens.red : LumiTokens.muted;

    final initials =
        '${student.firstName.isNotEmpty ? student.firstName[0] : ''}${student.lastName.isNotEmpty ? student.lastName[0] : ''}'
            .toUpperCase();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            StudentAvatar(
              characterId: student.characterId,
              initial: initials,
              avatarColor: avatarColor,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.firstName,
                    style: LumiType.body.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    nudge.message,
                    style: LumiType.caption.copyWith(
                      color: messageColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: LumiTokens.muted.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
