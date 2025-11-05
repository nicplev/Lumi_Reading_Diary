import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/minimal_theme.dart';

/// Horizontal scrolling date selector
class DateSelector extends StatelessWidget {
  final List<DateTime> dates;
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const DateSelector({
    super.key,
    required this.dates,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        padding: const EdgeInsets.symmetric(horizontal: MinimalTheme.spaceM),
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = DateUtils.isSameDay(date, selectedDate);

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => onDateSelected(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 70,
                decoration: BoxDecoration(
                  color: isSelected ? MinimalTheme.primaryPurple : MinimalTheme.white,
                  borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
                  boxShadow: MinimalTheme.cardShadow(),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _getWeekday(date.weekday),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? MinimalTheme.white
                            : MinimalTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date.day.toString(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? MinimalTheme.white
                            : MinimalTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _getWeekday(int weekday) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[weekday - 1];
  }
}

/// Compact week view selector
class WeekSelector extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const WeekSelector({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final dates = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: dates.map((date) {
        final isSelected = DateUtils.isSameDay(date, selectedDate);
        final isToday = DateUtils.isSameDay(date, now);

        return GestureDetector(
          onTap: () => onDateSelected(date),
          child: Container(
            width: 44,
            height: 60,
            decoration: BoxDecoration(
              color: isSelected
                  ? MinimalTheme.primaryPurple
                  : MinimalTheme.white,
              borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
              border: isToday && !isSelected
                  ? Border.all(color: MinimalTheme.primaryPurple, width: 2)
                  : null,
              boxShadow: MinimalTheme.cardShadow(),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('E').format(date).substring(0, 1),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? MinimalTheme.white
                        : MinimalTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date.day.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? MinimalTheme.white
                        : MinimalTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
