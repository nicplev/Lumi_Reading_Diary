import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../services/class_daily_reading_service.dart';

/// Dashboard widget: a GitHub-style heatmap of daily reading across the class
/// over the last 12 weeks. Each cell is one day; its green intensity reflects
/// the share of the class that logged reading that day. Tap a cell for detail.
class DashboardReadingCalendarCard extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;
  final List<StudentModel> students;

  const DashboardReadingCalendarCard({
    super.key,
    required this.classModel,
    required this.schoolId,
    required this.students,
  });

  @override
  State<DashboardReadingCalendarCard> createState() =>
      _DashboardReadingCalendarCardState();
}

class _DashboardReadingCalendarCardState
    extends State<DashboardReadingCalendarCard> {
  // Selectable view window. Stored per session (not persisted).
  int _weeks = 12;
  static const List<int> _weekOptions = [4, 8, 12, 16, 24];

  final ClassDailyReadingService _dailyReadingService =
      ClassDailyReadingService();
  late Stream<List<ClassDailyReadingSummary>> _summariesStream;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(DashboardReadingCalendarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
    }
  }

  void _initStream() {
    final today = _dayOnly(DateTime.now());
    final cutoff = today.subtract(Duration(days: _weeks * 7 - 1));
    _summariesStream = _dailyReadingService.watchRange(
      schoolId: widget.schoolId,
      classId: widget.classModel.id,
      startInclusive: cutoff,
      endInclusive: today,
    );
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final classSize = widget.students.length;
    final today = _dayOnly(DateTime.now());
    // A continuous run of the last (_weeks × 7) days, ending today.
    final startDay = today.subtract(Duration(days: _weeks * 7 - 1));

    return StreamBuilder<List<ClassDailyReadingSummary>>(
      stream: _summariesStream,
      builder: (context, snapshot) {
        final byDay = <DateTime, int>{};
        for (final summary in snapshot.data ?? const []) {
          final day = _dayOnly(summary.date);
          if (day.isBefore(startDay)) continue;
          byDay[day] = summary.activeStudentCount;
        }

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reading Calendar', style: LumiType.subhead),
                  _buildRangePicker(),
                ],
              ),
              const SizedBox(height: 16),
              _buildGrid(byDay, startDay, classSize),
              const SizedBox(height: 12),
              _buildSelectionOrLegend(byDay, classSize),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid(
    Map<DateTime, int> byDay,
    DateTime startDay,
    int classSize,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        const targetCell = 18.0;
        // Fixed-size square cells. Days flow left→right, top→bottom and wrap
        // onto as many rows as needed to fill the width. So fewer weeks means
        // fewer rows (a shorter card) rather than bigger cells or empty space.
        final perRow = ((constraints.maxWidth + gap) / (targetCell + gap))
            .floor()
            .clamp(7, 28);
        final cell = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        final totalDays = _weeks * 7;
        final rows = (totalDays / perRow).ceil();

        final rowWidgets = <Widget>[];
        for (var r = 0; r < rows; r++) {
          final cells = <Widget>[];
          for (var c = 0; c < perRow; c++) {
            final i = r * perRow + c;
            if (i >= totalDays) break;
            final day = startDay.add(Duration(days: i));
            final count = byDay[day] ?? 0;
            final selected = _selectedDay == day;
            if (c > 0) cells.add(const SizedBox(width: gap));
            cells.add(GestureDetector(
              onTap: () => setState(() => _selectedDay = day),
              child: Container(
                width: cell,
                height: cell,
                decoration: BoxDecoration(
                  color: _cellColor(count, classSize),
                  borderRadius: BorderRadius.circular(3),
                  border: selected
                      ? Border.all(color: LumiTokens.ink, width: 1.4)
                      : null,
                ),
              ),
            ));
          }
          rowWidgets.add(Padding(
            padding: EdgeInsets.only(top: r == 0 ? 0 : gap),
            child: Row(children: cells),
          ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowWidgets,
        );
      },
    );
  }

  Widget _buildRangePicker() {
    return PopupMenuButton<int>(
      initialValue: _weeks,
      tooltip: 'Change range',
      color: LumiTokens.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        side: const BorderSide(color: LumiTokens.rule),
      ),
      onSelected: (w) => setState(() {
        _weeks = w;
        _selectedDay = null;
        _initStream(); // re-window the query to the newly chosen range
      }),
      itemBuilder: (_) => [
        for (final w in _weekOptions)
          PopupMenuItem<int>(
            value: w,
            child: Text('$w weeks', style: LumiType.body),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: LumiTokens.rule),
          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_weeks weeks',
              style: LumiType.caption.copyWith(
                color: LumiTokens.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                size: 16, color: LumiTokens.muted),
          ],
        ),
      ),
    );
  }

  /// Resting cell colour by the share of the class that read that day.
  ///
  /// A traffic-light scale, so colour matches intuition — red reads as a weak
  /// day, green as a strong one:
  ///   none → grey · few → red · → orange · → yellow · most → green
  Color _cellColor(int count, int classSize) {
    if (count <= 0) return LumiTokens.rule;
    final f = classSize > 0 ? count / classSize : 1.0;
    if (f <= 0.25) return LumiTokens.red;
    if (f <= 0.5) return LumiTokens.orange;
    if (f <= 0.75) return LumiTokens.yellow;
    return LumiTokens.green;
  }

  Widget _buildSelectionOrLegend(
    Map<DateTime, int> byDay,
    int classSize,
  ) {
    if (_selectedDay != null) {
      final count = byDay[_selectedDay] ?? 0;
      final label = DateFormat('EEE d MMM').format(_selectedDay!);
      return Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _cellColor(count, classSize),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 0
                  ? '$label · no reading logged'
                  : '$label · $count of $classSize read',
              style: LumiType.caption.copyWith(color: LumiTokens.ink),
            ),
          ),
        ],
      );
    }

    // Legend — traffic-light scale: few (red) → most (green).
    final swatches = [
      LumiTokens.rule,
      LumiTokens.red,
      LumiTokens.orange,
      LumiTokens.yellow,
      LumiTokens.green,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: LumiType.caption.copyWith(fontSize: 11)),
        const SizedBox(width: 6),
        for (final c in swatches) ...[
          Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Text('More', style: LumiType.caption.copyWith(fontSize: 11)),
      ],
    );
  }
}
