import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/dashboard_student_roster_service.dart';

void main() {
  const schoolId = 'school_1';
  const classId = 'class_1';

  late FakeFirebaseFirestore firestore;
  late DashboardStudentRosterService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = DashboardStudentRosterService(firestore: firestore);
  });

  Future<void> seedStudent(
    String id, {
    String studentSchoolId = schoolId,
    String studentClassId = classId,
    Object? characterId = 'mt_blue',
    List<dynamic> achievements = const [],
  }) {
    return firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(id)
        .set({
      'firstName': id,
      'lastName': 'Reader',
      'schoolId': studentSchoolId,
      'classId': studentClassId,
      'characterId': characterId,
      'isActive': true,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'achievements': achievements,
    });
  }

  test('dangling roster id does not hide valid classmates', () async {
    await seedStudent(
      'student_b',
      achievements: const [
        {'id': 'first_log'}
      ],
    );
    await seedStudent('student_a');
    await seedStudent('not_on_roster');

    final result = await service.fetch(
      schoolId: schoolId,
      classId: classId,
      rosterStudentIds: const [
        'student_a',
        'missing_student',
        'student_b',
      ],
    );

    expect(
      result.entries.map((entry) => entry.student.id),
      ['student_a', 'student_b'],
    );
    expect(result.unresolvedStudentIds, {'missing_student'});
    expect(result.malformedStudentIds, isEmpty);
    expect(result.warningCount, 1);
    expect(result.entries.last.achievementData, hasLength(1));
  });

  test('wrong-class roster id stays unresolved and cannot cross class scope',
      () async {
    await seedStudent('student_a');
    await seedStudent('other_student', studentClassId: 'class_2');

    final result = await service.fetch(
      schoolId: schoolId,
      classId: classId,
      rosterStudentIds: const ['student_a', 'other_student'],
    );

    expect(result.entries.single.student.id, 'student_a');
    expect(result.unresolvedStudentIds, {'other_student'});
  });

  test('one malformed student does not poison valid roster entries', () async {
    await seedStudent('student_a');
    await seedStudent('malformed_student', characterId: 42);

    final result = await service.fetch(
      schoolId: schoolId,
      classId: classId,
      rosterStudentIds: const ['malformed_student', 'student_a'],
    );

    expect(result.entries.single.student.id, 'student_a');
    expect(result.unresolvedStudentIds, isEmpty);
    expect(result.malformedStudentIds, {'malformed_student'});
    expect(result.warningCount, 1);
  });

  test('deduplicates and trims roster ids while preserving roster order',
      () async {
    await seedStudent('student_a');
    await seedStudent('student_b');

    final result = await service.fetch(
      schoolId: schoolId,
      classId: classId,
      rosterStudentIds: const [
        ' student_b ',
        '',
        'student_a',
        'student_b',
      ],
    );

    expect(
      result.entries.map((entry) => entry.student.id),
      ['student_b', 'student_a'],
    );
    expect(result.warningCount, 0);
  });
}
