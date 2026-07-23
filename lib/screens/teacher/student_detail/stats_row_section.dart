import 'package:flutter/material.dart';

import '../../../data/models/student_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// "Reading Snapshot" bento on the teacher student-detail screen. Pure display —
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reading Snapshot', style: LumiType.subhead),
              Text(
                'ALL TIME',
                style: LumiType.sectionLabel.copyWith(
                  color: LumiTokens.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 6,
                child: _SnapshotHeroTile(totalNights: totalNights),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _SnapshotMiniTile(
                      value: '$totalBooks',
                      label: 'Total books',
                      icon: Icons.menu_book_rounded,
                      color: LumiTokens.green,
                      background: LumiTokens.tintGreen,
                    ),
                    const SizedBox(height: 10),
                    _SnapshotMiniTile(
                      value: '$streak',
                      label: streak == 0 ? 'Start today' : 'Day streak',
                      icon: Icons.local_fire_department_outlined,
                      color: LumiTokens.orange,
                      background: LumiTokens.tintOrange,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotHeroTile extends StatelessWidget {
  final int totalNights;

  const _SnapshotHeroTile({required this.totalNights});

  @override
  Widget build(BuildContext context) {
    final surface = Color.lerp(LumiTokens.tintBlue, LumiTokens.paper, 0.42)!;
    return Container(
      height: 154,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: LumiTokens.paper.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.nights_stay_outlined,
              size: 18,
              color: LumiTokens.ink,
            ),
          ),
          const Spacer(),
          Text(
            '$totalNights',
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: LumiTokens.ink,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Total nights',
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotMiniTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  const _SnapshotMiniTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Color.lerp(background, LumiTokens.paper, 0.42)!;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: LumiType.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: LumiTokens.ink,
                  ),
                ),
                const SizedBox(height: 1),
                // Degrade gracefully on narrow phones / large text: allow a
                // second line and scale down rather than truncating the label
                // (e.g. the empty-state streak label used to clip to "Ready
                // to re…").
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 2,
                      style:
                          LumiType.caption.copyWith(color: LumiTokens.muted),
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
}
