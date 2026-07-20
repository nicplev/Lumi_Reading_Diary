import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/feelings/feelings_tracker_card.dart';
import 'package:lumi_reading_tracker/core/widgets/feelings/feelings_glance_row.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';

ReadingLogModel _log(DateTime date, {ReadingFeeling? feeling}) => ReadingLogModel(
      id: 'id-${date.microsecondsSinceEpoch}',
      studentId: 's1',
      parentId: 'p1',
      schoolId: 'sch1',
      classId: 'c1',
      date: date,
      minutesRead: 10,
      targetMinutes: 10,
      status: LogStatus.completed,
      bookTitles: const ['Book'],
      createdAt: date,
      childFeeling: feeling,
    );

Future<void> _pump(WidgetTester tester, List<ReadingLogModel> logs) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: FeelingsTrackerCard(logs: logs, now: DateTime(2025, 6, 11)),
      ),
    ),
  ));
}

void main() {
  testWidgets('shows empty state when no feelings recorded', (tester) async {
    await _pump(tester, [
      _log(DateTime(2025, 6, 9)), // quick log, no feeling
    ]);
    expect(find.text('No reading feelings recorded yet'), findsOneWidget);
    expect(find.byType(FeelingsGlanceRow), findsNothing);
  });

  testWidgets('shows chart + glance row when feelings exist in week view',
      (tester) async {
    await _pump(tester, [
      _log(DateTime(2025, 6, 9), feeling: ReadingFeeling.good),
      _log(DateTime(2025, 6, 11), feeling: ReadingFeeling.great),
    ]);
    expect(find.text('Reading Feelings'), findsOneWidget);
    // The separate 'This Week at a Glance' sub-heading went away when the two
    // cards were merged into one (8d666cc); the glance row now sits under a
    // plain divider inside the Reading Feelings card.
    expect(find.byType(FeelingsGlanceRow), findsOneWidget);
  });
}
