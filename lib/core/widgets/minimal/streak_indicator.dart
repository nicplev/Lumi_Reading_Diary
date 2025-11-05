import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';
import 'rounded_card.dart';

/// Streak indicator widget
class StreakIndicator extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;
  final int totalMinutes;

  const StreakIndicator({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      padding: const EdgeInsets.all(MinimalTheme.spaceL),
      child: Row(
        children: [
          Expanded(
            child: _StreakStat(
              icon: Icons.local_fire_department,
              color: MinimalTheme.orange,
              value: currentStreak.toString(),
              label: 'Current Streak',
            ),
          ),
          Container(
            width: 1,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  MinimalTheme.textSecondary.withValues(alpha: 0.2),
                  MinimalTheme.textSecondary,
                  MinimalTheme.textSecondary.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          Expanded(
            child: _StreakStat(
              icon: Icons.emoji_events,
              color: MinimalTheme.gold,
              value: longestStreak.toString(),
              label: 'Best Streak',
            ),
          ),
          Container(
            width: 1,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  MinimalTheme.textSecondary.withValues(alpha: 0.2),
                  MinimalTheme.textSecondary,
                  MinimalTheme.textSecondary.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          Expanded(
            child: _StreakStat(
              icon: Icons.timer,
              color: MinimalTheme.blue,
              value: '${totalMinutes ~/ 60}h',
              label: 'Total Time',
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StreakStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: MinimalTheme.spaceS),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: MinimalTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: MinimalTheme.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Week view with day indicators
class WeekStreakView extends StatelessWidget {
  final DateTime startOfWeek;
  final List<DateTime> completedDates;

  const WeekStreakView({
    super.key,
    required this.startOfWeek,
    required this.completedDates,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final date = startOfWeek.add(Duration(days: index));
        final isCompleted = completedDates.any(
          (d) => DateUtils.isSameDay(d, date),
        );
        final isToday = DateUtils.isSameDay(date, DateTime.now());

        return _DayIndicator(
          day: _getWeekdayShort(date.weekday),
          isCompleted: isCompleted,
          isToday: isToday,
        );
      }),
    );
  }

  String _getWeekdayShort(int weekday) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[weekday - 1];
  }
}

class _DayIndicator extends StatelessWidget {
  final String day;
  final bool isCompleted;
  final bool isToday;

  const _DayIndicator({
    required this.day,
    required this.isCompleted,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: isCompleted ? MinimalTheme.successGradient : null,
        color: !isCompleted
            ? (isToday
                ? MinimalTheme.blue.withValues(alpha: 0.2)
                : MinimalTheme.lightPurple.withValues(alpha: 0.3))
            : null,
        shape: BoxShape.circle,
        border: isToday && !isCompleted
            ? Border.all(color: MinimalTheme.blue, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          day,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
            color: isCompleted
                ? MinimalTheme.white
                : (isToday ? MinimalTheme.blue : MinimalTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}
