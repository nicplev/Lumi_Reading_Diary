import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../theme/section_theme.dart';

/// Lumi Design System - Rhythm Calendar
///
/// A forgiving "X of the last N nights" mini heatmap. Days are laid out on a
/// weekday-aligned grid (columns Mon–Sun, oldest week on top, today bottom-
/// right) so reading patterns are legible at a glance:
/// - Read (incl. today): soft green fill (a confirmation state)
/// - Today (not yet read): section-accent ring — a gentle nudge
/// - Not read: warm-grey — deliberately NOT red. A missed night is simply a
///   dot that hasn't lit up yet, never a failure. The window slides forward
///   each day, so the count recovers naturally; it never resets to zero.
///
/// Colours mirror [WeekProgressBar] so the two timeline cards read as one
/// language: green = read, section accent = today's nudge, warm grey = empty.
class RhythmCalendar extends StatelessWidget {
  /// Days the student read (any time component is ignored).
  final Set<DateTime> readDays;

  /// Size of the trailing window, ending today. Defaults to 30.
  final int windowDays;

  /// Headline count of nights read in the window. When null it is derived from
  /// [readDays] within the window (the server-provided count is preferred).
  final int? count;

  const RhythmCalendar({
    super.key,
    required this.readDays,
    this.windowDays = 30,
    this.count,
  });

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Widget build(BuildContext context) {
    final accent = context.sectionTheme.accent;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = today.subtract(Duration(days: windowDays - 1));
    final readKeys = readDays.map(_key).toSet();

    final headlineCount = count ??
        List<DateTime>.generate(
                windowDays, (i) => today.subtract(Duration(days: i)))
            .where((d) => readKeys.contains(_key(d)))
            .length;

    // Align to a Mon–Sun grid: start on the Monday on/before the window start.
    final gridStart =
        windowStart.subtract(Duration(days: windowStart.weekday - 1));
    final weeks = (today.difference(gridStart).inDays / 7).floor() + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.nightlight_round,
                color: LumiTokens.blue, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$headlineCount of the last $windowDays nights',
                style: LumiType.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${DateFormat('d MMM').format(windowStart)} – ${DateFormat('d MMM').format(today)}',
              style: LumiType.caption.copyWith(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Weekday header.
        Row(
          children: [
            for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: LumiType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Week rows.
        for (var w = 0; w < weeks; w++) ...[
          Row(
            children: [
              for (var d = 0; d < 7; d++)
                Expanded(
                  child: Center(
                    child: _dot(
                      gridStart.add(Duration(days: w * 7 + d)),
                      windowStart,
                      today,
                      readKeys,
                      accent,
                    ),
                  ),
                ),
            ],
          ),
          if (w < weeks - 1) const SizedBox(height: 6),
        ],
        const SizedBox(height: 12),
        // Legend.
        Row(
          children: [
            _LegendDot(color: LumiTokens.tintGreen, label: 'Read'),
            const SizedBox(width: 16),
            _LegendDot(color: LumiTokens.rule, label: 'No reading'),
          ],
        ),
      ],
    );
  }

  Widget _dot(
    DateTime date,
    DateTime windowStart,
    DateTime today,
    Set<String> readKeys,
    Color accent,
  ) {
    final inWindow = !date.isBefore(windowStart) && !date.isAfter(today);
    if (!inWindow) {
      // Padding cell outside the 30-day window — invisible, keeps the grid.
      return const SizedBox(width: 14, height: 14);
    }

    final isRead = readKeys.contains(_key(date));
    final isToday = date == today;

    Color background = LumiTokens.rule;
    Color? border;
    double borderWidth = 0;
    if (isRead) {
      background = LumiTokens.tintGreen;
    } else if (isToday) {
      background = Colors.transparent;
      border = accent;
      borderWidth = 2;
    }

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border:
            borderWidth > 0 ? Border.all(color: border!, width: borderWidth) : null,
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: LumiType.caption.copyWith(fontSize: 12)),
      ],
    );
  }
}
