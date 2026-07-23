import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/class_model.dart';
import 'package:lumi_reading_tracker/screens/teacher/dashboard/widgets/dashboard_top_readers_card.dart';

import '../../helpers/test_data_factory.dart';

void main() {
  testWidgets('leaderboard excludes logs whose student is no longer resolvable',
      (tester) async {
    final student = TestDataFactory.student(
      id: 'student_a',
      firstName: 'Ari',
      lastName: 'Reader',
    );
    final validLog = TestDataFactory.readingLog(
      id: 'valid_log',
      studentId: student.id,
      minutesRead: 20,
    );
    final ghostLog = TestDataFactory.readingLog(
      id: 'ghost_log',
      studentId: 'deleted_student',
      minutesRead: 100,
    );

    final classModel = ClassModel(
      id: 'class_a',
      schoolId: 'school_a',
      name: '3A',
      teacherId: 'teacher-1',
      studentIds: [student.id],
      createdAt: DateTime(2026, 1, 1),
      createdBy: 'teacher-1',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardTopReadersCard(
          weeklyLogs: [ghostLog, validLog],
          students: [student],
          teacher: TestDataFactory.teacherUser(),
          classModel: classModel,
        ),
      ),
    ));

    expect(find.text('Ari R.'), findsOneWidget);
    expect(find.text('20 min'), findsOneWidget);
    expect(find.text('100 min'), findsNothing);
    expect(find.text('Student unavailable'), findsNothing);
  });
}
