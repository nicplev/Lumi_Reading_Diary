import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/class_daily_reading_service.dart';

void main() {
  test('merges shards by day while preserving per-student metrics', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ClassDailyReadingService(firestore: firestore);
    final summaries = firestore
        .collection('schools')
        .doc('school_1')
        .collection('classDailyReading');
    await summaries.doc('shard_a').set({
      'classId': 'class_1',
      'localDate': '2026-07-17',
      'shard': 0,
      'logCount': 2,
      'totalMinutes': 35,
      'teacherLogCount': 1,
      'students': {
        'student_1': {'logs': 2, 'minutes': 35, 'teacherLogs': 1},
      },
    });
    await summaries.doc('shard_b').set({
      'classId': 'class_1',
      'localDate': '2026-07-17',
      'shard': 1,
      'logCount': 1,
      'totalMinutes': 20,
      'teacherLogCount': 0,
      'students': {
        'student_2': {'logs': 1, 'minutes': 20, 'teacherLogs': 0},
      },
    });
    await summaries.doc('other_class').set({
      'classId': 'class_2',
      'localDate': '2026-07-17',
      'logCount': 99,
      'totalMinutes': 999,
      'students': {},
    });

    final result = await service.fetchRange(
      schoolId: 'school_1',
      classId: 'class_1',
      startInclusive: DateTime(2026, 7, 1),
      endInclusive: DateTime(2026, 7, 31),
    );

    expect(result, hasLength(1));
    expect(result.single.logCount, 3);
    expect(result.single.totalMinutes, 55);
    expect(result.single.teacherLogCount, 1);
    expect(result.single.activeStudentCount, 2);
    expect(result.single.students['student_1']?.minutes, 35);
  });

  test('range query excludes days outside the requested local-date window',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = ClassDailyReadingService(firestore: firestore);
    final summaries = firestore
        .collection('schools')
        .doc('school_1')
        .collection('classDailyReading');
    for (final day in [
      '2026-06-30',
      '2026-07-01',
      '2026-07-07',
      '2026-07-08'
    ]) {
      await summaries.doc(day).set({
        'classId': 'class_1',
        'localDate': day,
        'logCount': 1,
        'totalMinutes': 10,
        'students': {
          'student_1': {'logs': 1, 'minutes': 10, 'teacherLogs': 0},
        },
      });
    }

    final result = await service.fetchRange(
      schoolId: 'school_1',
      classId: 'class_1',
      startInclusive: DateTime(2026, 7, 1),
      endInclusive: DateTime(2026, 7, 7),
    );

    expect(result.map((summary) => summary.localDate), [
      '2026-07-01',
      '2026-07-07',
    ]);
  });
}
