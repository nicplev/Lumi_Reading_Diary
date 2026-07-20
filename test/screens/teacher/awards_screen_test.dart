import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/class_model.dart';
import 'package:lumi_reading_tracker/screens/teacher/awards_screen.dart';

ClassModel _class() => ClassModel(
      id: 'c1',
      schoolId: 's1',
      name: '3A',
      teacherId: 't1',
      teacherIds: const ['t1'],
      studentIds: const ['st1', 'st2'],
      createdAt: DateTime(2026, 1, 1),
      createdBy: 't1',
    );

Future<void> _seed(FakeFirebaseFirestore fs) async {
  final students = fs.collection('schools').doc('s1').collection('students');
  await fs.collection('schools').doc('s1').collection('classes').doc('c1').set({
    'schoolId': 's1',
    'name': '3A',
    'teacherId': 't1',
    'teacherIds': ['t1'],
    'studentIds': ['st1', 'st2'],
    'createdBy': 't1',
    'isActive': true,
  });
  await students.doc('st1').set({
    'firstName': 'Amy', 'lastName': 'Ant', 'schoolId': 's1', 'classId': 'c1',
    'characterId': 'lumi_cat', 'isActive': true,
  });
  await students.doc('st2').set({
    'firstName': 'Ben', 'lastName': 'Bee', 'schoolId': 's1', 'classId': 'c1',
    'characterId': 'lumi_frog', 'isActive': true,
  });
}

Future<void> _pump(WidgetTester tester, FakeFirebaseFirestore fs) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
  await tester.pumpWidget(MaterialApp(
    home: AwardsScreen(classModel: _class(), firestore: fs),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders both award sections with default names', (tester) async {
    final fs = FakeFirebaseFirestore();
    await _seed(fs);
    await _pump(tester, fs);

    // Each name shows in the section header and the "Award name" edit row.
    expect(find.text('Reader of the Week'), findsNWidgets(2));
    expect(find.text('Special Award'), findsNWidgets(2));
    expect(find.text('Assign award'), findsOneWidget);
  });

  testWidgets('toggling Top Reader writes settings.awards.topReader.enabled',
      (tester) async {
    final fs = FakeFirebaseFirestore();
    await _seed(fs);
    await _pump(tester, fs);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final cls = await fs
        .collection('schools').doc('s1').collection('classes').doc('c1').get();
    final awards = cls.data()?['settings']?['awards']?['topReader'];
    expect(awards?['enabled'], isTrue);
  });

  testWidgets('assigning the special award writes manualAward on the student',
      (tester) async {
    final fs = FakeFirebaseFirestore();
    await _seed(fs);
    await _pump(tester, fs);

    await tester.tap(find.text('Assign award'));
    await tester.pumpAndSettle();
    // Bottom sheet lists the roster; pick Amy.
    await tester.tap(find.text('Amy Ant').last);
    await tester.pumpAndSettle();

    final st1 = await fs
        .collection('schools').doc('s1').collection('students').doc('st1').get();
    expect(st1.data()?['manualAward']?['characterId'], 'special_lumi');
    expect(st1.data()?['manualAward']?['name'], 'Special Award');

    // Reassigning to Ben clears Amy (single holder per class).
    await tester.tap(find.text('Change holder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ben Bee').last);
    await tester.pumpAndSettle();

    final st1b = await fs
        .collection('schools').doc('s1').collection('students').doc('st1').get();
    final st2b = await fs
        .collection('schools').doc('s1').collection('students').doc('st2').get();
    expect(st1b.data()?.containsKey('manualAward'), isFalse);
    expect(st2b.data()?['manualAward']?['characterId'], 'special_lumi');

    // Each assignment fires a 2s Lumi toast. pumpAndSettle drains animations
    // but not a bare Timer, so without this the test tears down with pending
    // timers and fails despite every assertion above passing.
    await tester.pump(const Duration(seconds: 3));
  });
}
