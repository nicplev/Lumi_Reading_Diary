import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/feelings/feelings_tracker_card.dart';
import 'package:lumi_reading_tracker/data/providers/active_child_provider.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/teacher_book_assignment_card.dart';
import 'package:lumi_reading_tracker/data/models/class_model.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/teacher/student_detail/first_read_bento.dart';
import 'package:lumi_reading_tracker/screens/teacher/student_detail_screen.dart';

/// Characterization tests capturing StudentDetailScreen's current behaviour
/// ahead of the performance decomposition (perf plan C1). They pin section
/// rendering and the two in-screen gates (`_levelsEnabled`,
/// `_canMutateAssignment`) so the extraction in C2 cannot silently change
/// behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Core mocks let the two FirebaseAuth.instance.currentUser reads in the
    // history/comment sections resolve to null (uid '') instead of throwing.
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late UserModel teacher;
  late ClassModel classModel;
  late StudentModel student;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    teacher = UserModel(
      id: 'teacher_1',
      email: 'teacher@example.com',
      fullName: 'Ms Beta',
      role: UserRole.teacher,
      schoolId: 'school_1',
      createdAt: DateTime(2026, 1, 1),
    );
    classModel = ClassModel(
      id: 'class_3a',
      schoolId: 'school_1',
      name: '3A',
      teacherId: teacher.id,
      teacherIds: [teacher.id],
      studentIds: const ['student_1'],
      createdAt: DateTime(2026, 1, 1),
      createdBy: teacher.id,
    );
    student = StudentModel(
      id: 'student_1',
      firstName: 'Daniel',
      lastName: 'Platt',
      schoolId: 'school_1',
      classId: 'class_3a',
      currentReadingLevel: 'C',
      parentIds: const ['parent_1'],
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      stats: StudentStats(
        totalMinutesRead: 120,
        totalBooksRead: 4,
        currentStreak: 3,
        longestStreak: 5,
        lastReadingDate: DateTime.now(),
        averageMinutesPerDay: 15.0,
        totalReadingDays: 7,
      ),
    );

    await _seedSchool(firestore, levelSchema: 'aToZ');
    await _seedStudentDoc(firestore);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
        child: MaterialApp(
          home: StudentDetailScreen(
            teacher: teacher,
            student: student,
            classModel: classModel,
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('StudentDetailScreen sections', () {
    testWidgets('keeps first-read actions usable on a narrow phone screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: StudentDetailFirstReadBento(
                studentName: 'Daniel Platt',
                onAssignBooks: () => actions.add('assign'),
                onScanIsbn: () => actions.add('scan'),
                onLogReading: () => actions.add('log'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Assign a book'));
      await tester.tap(find.text('Scan a book'));
      await tester.tap(find.text('Log a read'));

      expect(actions, ['assign', 'scan', 'log']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'shows the first-read bento only when there are no books or logs',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Ready for Daniel Platt\u2019s first read?'),
          findsOneWidget);
      expect(find.text('Assign a book'), findsOneWidget);
      expect(find.text('Scan a book'), findsOneWidget);
      expect(find.text('Log a read'), findsOneWidget);
      expect(find.text('WHAT GROWS NEXT'), findsOneWidget);
      expect(find.text('Assigned Books'), findsNothing);
      expect(find.text('Recent Reading'), findsNothing);
      expect(find.text('No achievements yet'), findsNothing);
    });

    testWidgets('renders stats row values from student stats', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Reading Snapshot'), findsOneWidget);
      expect(find.text('Total nights'), findsOneWidget);
      expect(find.text('7'), findsWidgets); // totalReadingDays
      expect(find.text('Day streak'), findsOneWidget);
      expect(find.text('3'), findsWidgets); // active streak (read today)
      expect(find.text('Total books'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
    });

    testWidgets('shows reading level card when the school has a level schema',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Reading Level'), findsOneWidget);
    });

    testWidgets('hides reading level card when levelSchema is none',
        (tester) async {
      await _seedSchool(firestore, levelSchema: 'none');
      await pumpScreen(tester);

      expect(find.text('Reading Level'), findsNothing);
    });

    testWidgets(
        'byTitle allocation renders a mutable book card; freeChoice renders '
        'a synthesized non-mutable card', (tester) async {
      await _seedAllocation(
        firestore,
        id: 'alloc_title',
        type: 'byTitle',
        assignmentItems: const [
          {'id': 'book_hp', 'title': 'Harry Potter'},
        ],
      );
      await _seedAllocation(
        firestore,
        id: 'alloc_free',
        type: 'freeChoice',
        assignmentItems: const [],
      );
      await pumpScreen(tester);

      expect(find.text('Assigned Books'), findsOneWidget);
      expect(find.text('Harry Potter'), findsOneWidget);

      final cards = tester
          .widgetList<TeacherBookAssignmentCard>(
            find.byType(TeacherBookAssignmentCard),
          )
          .toList();
      expect(cards, hasLength(2));

      final titleCard = cards.singleWhere((c) => c.title == 'Harry Potter');
      // Real assignment item → _canMutateAssignment true → actions offered.
      expect(titleCard.onTap, isNotNull);
      expect(titleCard.onActionSelected, isNotNull);

      final freeChoiceCard =
          cards.singleWhere((c) => c.title != 'Harry Potter');
      // Synthesized (no assignment item) → _canMutateAssignment false.
      expect(freeChoiceCard.onTap, isNull);
      expect(freeChoiceCard.onActionSelected, isNull);
    });

    testWidgets('renders recent reading rows and feelings tracker from logs',
        (tester) async {
      await _seedLog(
        firestore,
        id: 'log_1',
        date: DateTime.now().subtract(const Duration(days: 1)),
        minutesRead: 25,
        bookTitles: const ['The Gruffalo'],
        childFeeling: 'good',
      );
      await pumpScreen(tester);

      expect(find.text('Recent Reading'), findsOneWidget);
      expect(find.textContaining('The Gruffalo'), findsWidgets);
      expect(find.byType(FeelingsTrackerCard), findsOneWidget);
    });

    testWidgets(
        'uses compact next-read states when history exists but this week is quiet',
        (tester) async {
      await _seedLog(
        firestore,
        id: 'last_week_log',
        date: DateTime.now().subtract(const Duration(days: 8)),
        minutesRead: 25,
        bookTitles: const ['The Gruffalo'],
      );
      await pumpScreen(tester);

      expect(find.text('Reading Snapshot'), findsOneWidget);
      expect(find.text('Choose the next read'), findsOneWidget);
      expect(find.text('No book currently assigned'), findsNothing);
      expect(find.text('No reading feelings this week'), findsOneWidget);
      expect(find.text('No parent comments yet'), findsOneWidget);
      expect(find.text('NEXT MILESTONE'), findsOneWidget);
      expect(find.text('Recent Reading'), findsOneWidget);
    });

    testWidgets('renders latest parent comment with chips and parent name',
        (tester) async {
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('parents')
          .doc('parent_1')
          .set({'fullName': 'Sarah Nguyen'});
      await _seedLog(
        firestore,
        id: 'log_commented',
        date: DateTime.now(),
        minutesRead: 20,
        bookTitles: const ['The Gruffalo'],
        childFeeling: 'good',
        parentCommentSelections: const ['Loved hearing you read!'],
        parentCommentFreeText: 'Retold the story',
      );
      await pumpScreen(tester);

      expect(find.text('Latest Parent Comment'), findsOneWidget);
      expect(find.text('Loved hearing you read!'), findsOneWidget);
      expect(find.text('Retold the story'), findsOneWidget);
      expect(find.textContaining('Sarah Nguyen'), findsOneWidget);
    });

    testWidgets(
        'renders latest parent comment from the server aggregate without '
        'any logs', (tester) async {
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .update({
        'latestParentComment': {
          'logId': 'log_agg',
          'date': Timestamp.fromDate(DateTime.now()),
          'feeling': 'good',
          'presetChips': ['Loved hearing you read!'],
          'freeText': 'Retold the story',
          'parentId': 'parent_1',
          'parentName': 'Sarah Nguyen',
          'lastCommentAt': null,
          'lastCommentByRole': null,
          'commentsViewedAt': <String, dynamic>{},
        },
        'feelingsByDay': {
          _dayKey(DateTime.now()): {'good': 2, 'great': 1},
        },
      });
      await _seedLog(
        firestore,
        id: 'log_for_normal_detail',
        date: DateTime.now(),
        minutesRead: 10,
        bookTitles: const ['A first read'],
      );
      await pumpScreen(tester);

      expect(find.text('Latest Parent Comment'), findsOneWidget);
      expect(find.text('Loved hearing you read!'), findsOneWidget);
      expect(find.text('Retold the story'), findsOneWidget);
      expect(find.textContaining('Sarah Nguyen'), findsOneWidget);
      expect(find.byType(FeelingsTrackerCard), findsOneWidget);
    });

    testWidgets(
        'aggregate null latestParentComment renders the empty state '
        '(authoritative, no log scan)', (tester) async {
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .update({
        'latestParentComment': null,
        'feelingsByDay': <String, dynamic>{},
      });
      // A commented log exists, but the aggregate says "no comments" — the
      // aggregate wins (it is server-authoritative once the field exists).
      await _seedLog(
        firestore,
        id: 'log_ignored',
        date: DateTime.now(),
        minutesRead: 10,
        bookTitles: const ['Ignored'],
        parentCommentFreeText: 'Should not appear',
      );
      await pumpScreen(tester);

      expect(find.text('No parent comments yet'), findsOneWidget);
      expect(find.text('Should not appear'), findsNothing);
    });

    testWidgets('shows achievements empty state when none earned',
        (tester) async {
      await _seedLog(
        firestore,
        id: 'log_for_normal_detail',
        date: DateTime.now(),
        minutesRead: 10,
        bookTitles: const ['A first read'],
      );
      await pumpScreen(tester);

      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('NEXT MILESTONE'), findsOneWidget);
      // 'View all' only appears once achievements exist.
      final achievementsHeader = find.ancestor(
        of: find.text('Achievements'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(
            of: achievementsHeader, matching: find.text('View all')),
        findsNothing,
      );
    });
  });
}

String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Future<void> _seedSchool(
  FakeFirebaseFirestore firestore, {
  required String levelSchema,
}) async {
  await firestore.collection('schools').doc('school_1').set({
    'name': 'Test School',
    'levelSchema': levelSchema,
    'termDates': <String, Timestamp>{},
    'timezone': 'UTC',
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'createdBy': 'teacher_1',
  });
}

Future<void> _seedStudentDoc(FakeFirebaseFirestore firestore) async {
  await firestore
      .collection('schools')
      .doc('school_1')
      .collection('students')
      .doc('student_1')
      .set({
    'firstName': 'Daniel',
    'lastName': 'Platt',
    'schoolId': 'school_1',
    'classId': 'class_3a',
    'currentReadingLevel': 'C',
    'isActive': true,
    'parentIds': const ['parent_1'],
    'achievements': const <Map<String, dynamic>>[],
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
  });
}

Future<void> _seedAllocation(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String type,
  required List<Map<String, dynamic>> assignmentItems,
}) async {
  final now = DateTime.now();
  await firestore
      .collection('schools')
      .doc('school_1')
      .collection('allocations')
      .doc(id)
      .set({
    'schoolId': 'school_1',
    'classId': 'class_3a',
    'teacherId': 'teacher_1',
    'studentIds': const <String>[],
    'type': type,
    'cadence': 'weekly',
    'targetMinutes': 20,
    'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
    'endDate': Timestamp.fromDate(now.add(const Duration(days: 6))),
    'assignmentItems': assignmentItems,
    'schemaVersion': 2,
    'isRecurring': false,
    'isActive': true,
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'createdBy': 'teacher_1',
  });
}

Future<void> _seedLog(
  FakeFirebaseFirestore firestore, {
  required String id,
  required DateTime date,
  required int minutesRead,
  required List<String> bookTitles,
  String? childFeeling,
  List<String>? parentCommentSelections,
  String? parentCommentFreeText,
}) async {
  await firestore
      .collection('schools')
      .doc('school_1')
      .collection('readingLogs')
      .doc(id)
      .set({
    'studentId': 'student_1',
    'classId': 'class_3a',
    'schoolId': 'school_1',
    'parentId': 'parent_1',
    'date': Timestamp.fromDate(date),
    'createdAt': Timestamp.fromDate(date),
    'minutesRead': minutesRead,
    'targetMinutes': 20,
    'status': 'completed',
    'bookTitles': bookTitles,
    if (childFeeling != null) 'childFeeling': childFeeling,
    if (parentCommentSelections != null)
      'parentCommentSelections': parentCommentSelections,
    if (parentCommentFreeText != null)
      'parentCommentFreeText': parentCommentFreeText,
  });
}
