import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../theme/section_theme.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi/stats_card.dart';
import '../../core/widgets/lumi/week_progress_bar.dart';
import '../../core/widgets/lumi/rhythm_calendar.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';

/// Detailed progress for one child — the calm momentum card on Home links
/// here. Houses everything that used to clutter Home: full stats, the weekly
/// breakdown, the 30-night rhythm grid, and a link into achievements.
class ProgressScreen extends StatelessWidget {
  final StudentModel student;

  const ProgressScreen({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final windowStart =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));

    return LumiSectionScope(
      section: LumiSectionTheme.home,
      child: Scaffold(
        backgroundColor: LumiTokens.cream,
        appBar: AppBar(
          backgroundColor: LumiTokens.cream,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: LumiTokens.ink),
          title: Text("${student.firstName}'s progress", style: LumiType.subhead),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Headline stats: total nights, current streak, best streak.
            StreamBuilder<DocumentSnapshot>(
              stream: firestore
                  .collection('schools')
                  .doc(student.schoolId)
                  .collection('students')
                  .doc(student.id)
                  .snapshots(),
              builder: (context, snap) {
                StudentStats? stats;
                if (snap.hasData && snap.data!.exists) {
                  stats = StudentModel.fromFirestore(snap.data!).stats;
                }
                return StatsCard(
                  totalNights: stats?.totalReadingDays ?? 0,
                  currentStreak: stats?.currentStreak ?? 0,
                  totalMinutes: stats?.totalMinutesRead ?? 0,
                  restDaysRemaining: stats?.restDaysRemaining,
                );
              },
            ),
            const SizedBox(height: 16),
            // This week + 30-night rhythm both derive from the last-30-days
            // window, so one stream feeds both.
            StreamBuilder<QuerySnapshot>(
              stream: firestore
                  .collection('schools')
                  .doc(student.schoolId)
                  .collection('readingLogs')
                  .where('studentId', isEqualTo: student.id)
                  .where('date',
                      isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
                  .snapshots(),
              builder: (context, snap) {
                final completedDays = <int>{};
                final readDays = <DateTime>{};
                if (snap.hasData) {
                  for (final doc in snap.data!.docs) {
                    final log = ReadingLogModel.fromFirestore(doc);
                    final day = DateTime(log.date.year, log.date.month, log.date.day);
                    readDays.add(day);
                    if (!day.isBefore(startOfWeek)) {
                      completedDays.add(log.date.weekday);
                    }
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LumiCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('This week', style: LumiType.subhead),
                          const SizedBox(height: 16),
                          WeekProgressBar(
                            completedDays: completedDays,
                            currentDay: now.weekday,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            completedDays.isEmpty
                                ? 'No reading logged yet this week'
                                : '${completedDays.length} ${completedDays.length == 1 ? 'night' : 'nights'} read this week',
                            style: LumiType.caption,
                          ),
                        ],
                      ),
                    ),
                    if (readDays.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      LumiCard(
                        child: RhythmCalendar(readDays: readDays, windowDays: 30),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Achievements live on their own screen; surface them here.
            LumiCard(
              onTap: () => context.push(
                '/parent/achievements',
                extra: {'student': student},
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_outlined,
                      color: LumiTokens.yellow),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Achievements',
                      style: LumiType.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: LumiTokens.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
