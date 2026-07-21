import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/class_model.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/data/providers/active_child_provider.dart'
    show firestoreProvider;
import 'package:lumi_reading_tracker/screens/teacher/comprehension_recordings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late UserModel teacher;
  late ClassModel classModel;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    teacher = UserModel(
      id: 'teacher_1',
      email: 'teacher@example.com',
      fullName: 'Ms Lumi',
      role: UserRole.teacher,
      schoolId: 'school_1',
      createdAt: DateTime(2026, 1, 1),
    );
    classModel = ClassModel(
      id: 'class_1',
      schoolId: 'school_1',
      name: 'Class 3B',
      teacherId: teacher.id,
      teacherIds: [teacher.id],
      studentIds: const ['student_1'],
      createdAt: DateTime(2026, 1, 1),
      createdBy: teacher.id,
    );
  });

  testWidgets('fails closed and does not build the inbox when audio is off',
      (tester) async {
    await _seedSchool(firestore, audioEnabled: false);
    await _pumpScreen(tester, firestore, teacher, classModel);

    expect(
      find.text('Comprehension recordings are not enabled for this school.'),
      findsOneWidget,
    );
    expect(find.text('To review'), findsNothing);
  });

  testWidgets('shows a recording-first review inbox with no AI language',
      (tester) async {
    await _seedSchool(firestore, audioEnabled: true);
    await _seedRecording(firestore);
    await _pumpScreen(tester, firestore, teacher, classModel);

    expect(find.text('Comprehension recordings'), findsOneWidget);
    expect(find.text('Ava Patel'), findsOneWidget);
    expect(find.text('To review'), findsWidgets);
    expect(find.text('View AI summary'), findsNothing);
  });

  testWidgets('selection mode can select all recordings without opening them',
      (tester) async {
    await _seedSchool(firestore, audioEnabled: true);
    await _seedRecording(firestore);
    await _seedRecording(firestore, logId: 'log_2');
    await _pumpScreen(tester, firestore, teacher, classModel);

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('What was the main problem?'), findsNothing);

    await tester.tap(find.text('Ava Patel').first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('What was the main problem?'), findsNothing);
  });

  testWidgets('detail keeps reply secondary and opens the existing log thread',
      (tester) async {
    await _seedSchool(firestore, audioEnabled: true);
    await _seedRecording(firestore);
    ReadingLogModel? repliedLog;
    String? repliedStudent;
    await _pumpScreen(
      tester,
      firestore,
      teacher,
      classModel,
      onReply: (log, studentName) {
        repliedLog = log;
        repliedStudent = studentName;
      },
    );

    await tester.tap(find.text('Ava Patel'));
    await tester.pumpAndSettle();

    expect(find.text('What was the main problem?'), findsOneWidget);
    expect(find.text('Reply to family'), findsOneWidget);
    expect(find.text('Next recording'), findsOneWidget);

    await tester.tap(find.text('Reply to family'));
    await tester.pumpAndSettle();

    // The inbox passes the original ReadingLogModel to the same comments-sheet
    // opening boundary used by Student detail; no inbox-specific thread id is
    // created.
    expect(repliedLog?.id, 'log_1');
    expect(repliedLog?.schoolId, 'school_1');
    expect(repliedStudent, 'Ava Patel');
  });

  testWidgets('inbox and detail do not overflow at 320px width',
      (tester) async {
    await _seedSchool(firestore, audioEnabled: true);
    await _seedRecording(firestore);
    await _pumpScreen(
      tester,
      firestore,
      teacher,
      classModel,
      surfaceSize: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ava Patel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _seedSchool(
  FakeFirebaseFirestore firestore, {
  required bool audioEnabled,
}) async {
  await firestore
      .collection('platformConfig')
      .doc('comprehensionRecording')
      .set({'enabled': audioEnabled});
  await firestore.collection('schools').doc('school_1').set({
    'name': 'Lumi School',
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'createdBy': 'admin_1',
    'settings': {
      'comprehensionRecording': {
        'enabled': audioEnabled,
        'retentionDays': 90,
      },
      'messaging': {'enabled': true},
    },
  });
  await firestore
      .collection('schools')
      .doc('school_1')
      .collection('students')
      .doc('student_1')
      .set({
    'schoolId': 'school_1',
    'classId': 'class_1',
    'name': 'Ava Patel',
  });
}

Future<void> _seedRecording(
  FakeFirebaseFirestore firestore, {
  String logId = 'log_1',
}) async {
  await firestore
      .collection('schools')
      .doc('school_1')
      .collection('readingLogs')
      .doc(logId)
      .set({
    'schoolId': 'school_1',
    'classId': 'class_1',
    'studentId': 'student_1',
    'parentId': 'parent_1',
    'date': Timestamp.fromDate(DateTime(2026, 7, 20, 19)),
    'createdAt': Timestamp.fromDate(DateTime(2026, 7, 20, 19)),
    'minutesRead': 20,
    'targetMinutes': 20,
    'status': 'completed',
    'bookTitles': ['The Paper Bag Princess'],
    'comprehensionAudioUploaded': true,
    'comprehensionAudioUploadedAt':
        Timestamp.fromDate(DateTime(2026, 7, 20, 19, 30)),
    'comprehensionAudioPath': 'schools/school_1/comprehension_audio/$logId.m4a',
    'comprehensionAudioDurationSec': 42,
    'comprehensionAudioObjectGeneration': 'generation_1',
    'comprehensionAudioReviewStatus': 'pending',
    'comprehensionQuestionText': 'What was the main problem?',
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  FakeFirebaseFirestore firestore,
  UserModel teacher,
  ClassModel classModel, {
  void Function(ReadingLogModel log, String studentName)? onReply,
  Size surfaceSize = const Size(430, 900),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(firestore)],
      child: MaterialApp(
        home: ComprehensionRecordingsScreen(
          teacher: teacher,
          classModel: classModel,
          onReplyForTesting: onReply,
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}
