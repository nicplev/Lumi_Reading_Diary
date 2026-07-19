import 'package:flutter/material.dart';

import '../../../data/models/student_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// "Reading Stats" card on the teacher student-detail screen. Pure display —
/// rebuilds only when the parent passes a different [student].
class StatsRowSection extends StatelessWidget {
  final StudentModel student;

  const StatsRowSection({super.key, required this.student});

  /// Streak display rule: the stored streak only counts as "active" if the
  /// student read today or yesterday; otherwise show 0 without waiting for the
  /// server to recompute.
  static int activeStreak(StudentStats? stats) {
    if (stats == null) return 0;
    final stored = stats.currentStreak;
    if (stored <= 0) return 0;
    final lastRead = stats.lastReadingDate;
    if (lastRead == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastDay = DateTime(lastRead.year, lastRead.month, lastRead.day);
    if (lastDay.isAtSameMomentAs(today) ||
        lastDay.isAtSameMomentAs(yesterday)) {
      return stored;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final streak = activeStreak(student.stats);
    final totalNights = student.stats?.totalReadingDays ?? 0;
    final totalBooks = student.stats?.totalBooksRead ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reading Stats', style: LumiType.subhead),
          const SizedBox(height: 16),
          Row(
            children: [
              // Total nights (cumulative) is the hero metric — shown first.
              _CompactStat(
                value: '$totalNights',
                label: 'Total nights',
                icon: Icons.nights_stay_outlined,
                iconColor: LumiTokens.blue,
                circleColor: LumiTokens.tintBlue,
              ),
              const _CompactDivider(),
              // Streak is a gentle, secondary signal.
              _CompactStat(
                value: '$streak',
                label: 'Day streak',
                icon: Icons.local_fire_department_outlined,
                iconSize: 20,
                iconColor: LumiTokens.orange,
                circleColor: LumiTokens.tintOrange,
              ),
              const _CompactDivider(),
              _CompactStat(
                value: '$totalBooks',
                label: 'Total books',
                icon: Icons.menu_book_outlined,
                iconSize: 16,
                iconColor: LumiTokens.green,
                circleColor: LumiTokens.tintGreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final Color? circleColor;

  const _CompactStat({
    required this.value,
    required this.label,
    required this.icon,
    this.iconSize = 18,
    this.iconColor = LumiTokens.ink,
    this.circleColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = circleColor ?? LumiTokens.muted.withValues(alpha: 0.08);
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: LumiTokens.ink,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: LumiType.caption.copyWith(
              color: LumiTokens.muted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CompactDivider extends StatelessWidget {
  const _CompactDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: LumiTokens.rule,
    );
  }
}
