import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/class_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/teacher/teacher_classroom_screen.dart';
import 'package:lumi_reading_tracker/services/reading_level_service.dart';
import 'package:lumi_reading_tracker/services/student_reading_level_service.dart';

void main() {
  group('TeacherClassroomScreen', () {
    late FakeFirebaseFirestore firestore;
    late UserModel teacher;
    late ClassModel classModel;
    late ReadingLevelService readingLevelService;
    late StudentReadingLevelService studentReadingLevelService;

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
        studentIds: const ['student_1', 'student_2', 'student_3'],
        createdAt: DateTime(2026, 1, 1),
        createdBy: teacher.id,
      );
      readingLevelService = ReadingLevelService(firestore: firestore);
      studentReadingLevelService = StudentReadingLevelService(
        firestore: firestore,
        readingLevelService: readingLevelService,
      );

      await _seedSchool(firestore, teacher.schoolId!);
    });

    testWidgets('sort sheet includes needs books option', (tester) async {
      await _setLargeSurface(tester);
      await _seedDemoStudents(firestore, classModel);

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: classModel,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      await _openSortSheet(tester);

      expect(find.text('Needs Books'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('classroom_sort_option_needsBooks')),
        findsOneWidget,
      );
    });

    testWidgets(
        'needs books sort pushes unassigned students first with alphabetical ties',
        (tester) async {
      await _setLargeSurface(tester);
      await _seedDemoStudents(firestore, classModel);
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'allocation_emma',
        type: 'byTitle',
        studentIds: const ['student_2'],
      );
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'allocation_liam',
        type: 'byTitle',
        studentIds: const ['student_3'],
      );

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: classModel,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      await _openSortSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('classroom_sort_option_needsBooks')),
      );
      await tester.pumpAndSettle();

      final danielY = tester.getTopLeft(find.text('Daniel Platt')).dy;
      final emmaY = tester.getTopLeft(find.text('Emma Wilson')).dy;
      final liamY = tester.getTopLeft(find.text('Liam Chen')).dy;

      expect(danielY, lessThan(emmaY));
      expect(emmaY, lessThan(liamY));
      expect(find.text('Needs Books'), findsOneWidget);
    });

    testWidgets('student card book icon shows assigned and unassigned states',
        (tester) async {
      await _setLargeSurface(tester);
      await _seedDemoStudents(firestore, classModel);
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'allocation_emma',
        type: 'byTitle',
        studentIds: const ['student_2'],
      );

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: classModel,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      final emmaIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('student_book_status_student_2')),
      );
      final danielIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('student_book_status_student_1')),
      );

      expect(emmaIcon.icon, Icons.menu_book_rounded);
      expect(emmaIcon.semanticLabel, 'Books assigned');
      expect(danielIcon.icon, Icons.menu_book_outlined);
      expect(danielIcon.semanticLabel, 'Needs books');
    });

    testWidgets('whole-class by title allocation marks all students assigned',
        (tester) async {
      await _setLargeSurface(tester);
      await _seedDemoStudents(firestore, classModel);
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'allocation_all',
        type: 'byTitle',
        studentIds: const <String>[],
      );

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: classModel,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      for (final studentId in classModel.studentIds) {
        final icon = tester.widget<Icon>(
          find.byKey(ValueKey('student_book_status_$studentId')),
        );
        expect(icon.icon, Icons.menu_book_rounded);
        expect(icon.semanticLabel, 'Books assigned');
      }
    });

    testWidgets(
        'student override removing all items leaves that student unassigned',
        (tester) async {
      await _setLargeSurface(tester);
      await _seedDemoStudents(firestore, classModel);
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'allocation_override',
        type: 'byTitle',
        studentIds: const <String>[],
        studentOverrides: {
          'student_2': {
            'removedItemIds': ['book_hp'],
            'addedItems': const <Map<String, dynamic>>[],
          },
        },
      );

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: classModel,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      final danielIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('student_book_status_student_1')),
      );
      final emmaIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('student_book_status_student_2')),
      );

      expect(danielIcon.semanticLabel, 'Books assigned');
      expect(emmaIcon.semanticLabel, 'Needs books');
    });

    testWidgets(
        'expired future and non-title allocations do not mark students assigned',
        (tester) async {
      await _setLargeSurface(tester);
      await _seedDemoStudents(firestore, classModel);
      final now = DateTime.now();
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'expired_title',
        type: 'byTitle',
        studentIds: const ['student_1'],
        startDate: now.subtract(const Duration(days: 14)),
        endDate: now.subtract(const Duration(days: 7)),
      );
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'future_title',
        type: 'byTitle',
        studentIds: const ['student_2'],
        startDate: now.add(const Duration(days: 7)),
        endDate: now.add(const Duration(days: 14)),
      );
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'active_level',
        type: 'byLevel',
        studentIds: const ['student_3'],
      );
      await _seedAllocation(
        firestore,
        classModel: classModel,
        id: 'free_choice',
        type: 'freeChoice',
        studentIds: const ['student_1'],
      );

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: classModel,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      for (final studentId in classModel.studentIds) {
        final icon = tester.widget<Icon>(
          find.byKey(ValueKey('student_book_status_$studentId')),
        );
        expect(icon.icon, Icons.menu_book_outlined);
        expect(icon.semanticLabel, 'Needs books');
      }
    });

    testWidgets('shows search empty state and clears search', (tester) async {
      await _setLargeSurface(tester);
      await _seedDemoStudents(firestore, classModel);

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: classModel,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'zoe');
      await tester.pumpAndSettle();

      expect(find.text('No students found'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      await tester.tap(find.text('Clear Search'));
      await tester.pumpAndSettle();

      expect(find.text('Daniel Platt'), findsOneWidget);
      expect(find.text('No students found'), findsNothing);
    });

    testWidgets('shows empty state when class has no students', (tester) async {
      await _setLargeSurface(tester);
      final emptyClass = classModel.copyWith(studentIds: const []);

      await tester.pumpWidget(
        _wrapClassroom(
          teacher: teacher,
          classModel: emptyClass,
          firestore: firestore,
          readingLevelService: readingLevelService,
          studentReadingLevelService: studentReadingLevelService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No students in this class yet'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });
  });
}

Future<void> _setLargeSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _openSortSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('classroom_sort_button')));
  await tester.pumpAndSettle();
}

Widget _wrapClassroom({
  required UserModel teacher,
  required ClassModel classModel,
  required FakeFirebaseFirestore firestore,
  required ReadingLevelService readingLevelService,
  required StudentReadingLevelService studentReadingLevelService,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TeacherClassroomScreen(
        teacher: teacher,
        selectedClass: classModel,
        classes: [classModel],
        firestore: firestore,
        readingLevelService: readingLevelService,
        studentReadingLevelService: studentReadingLevelService,
      ),
    ),
  );
}

Future<void> _seedSchool(
  FakeFirebaseFirestore firestore,
  String schoolId,
) async {
  await firestore.collection('schools').doc(schoolId).set({
    'name': 'Test School',
    'levelSchema': 'aToZ',
    'termDates': <String, Timestamp>{},
    'quietHours': {
      'start': '20:00',
      'end': '07:00',
    },
    'timezone': 'UTC',
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'createdBy': 'teacher_1',
  });
}

Future<void> _seedDemoStudents(
  FakeFirebaseFirestore firestore,
  ClassModel classModel,
) async {
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  final olderThanWeek = now.subtract(const Duration(days: 10));

  await _seedStudent(
    firestore,
    classModel: classModel,
    id: 'student_1',
    firstName: 'Daniel',
    lastName: 'Platt',
    currentReadingLevel: null,
    currentStreak: 1,
    lastReadingDate: yesterday,
    totalBooksRead: 0,
  );
  await _seedStudent(
    firestore,
    classModel: classModel,
    id: 'student_2',
    firstName: 'Emma',
    lastName: 'Wilson',
    currentReadingLevel: 'B',
    currentStreak: 2,
    lastReadingDate: now,
    totalBooksRead: 4,
  );
  await _seedStudent(
    firestore,
    classModel: classModel,
    id: 'student_3',
    firstName: 'Liam',
    lastName: 'Chen',
    currentReadingLevel: 'C',
    currentStreak: 2,
    lastReadingDate: olderThanWeek,
    totalBooksRead: 2,
  );
}

Future<void> _seedStudent(
  FakeFirebaseFirestore firestore, {
  required ClassModel classModel,
  required String id,
  required String firstName,
  required String lastName,
  required String? currentReadingLevel,
  required int currentStreak,
  required DateTime lastReadingDate,
  required int totalBooksRead,
}) async {
  await firestore
      .collection('schools')
      .doc(classModel.schoolId)
      .collection('students')
      .doc(id)
      .set({
    'firstName': firstName,
    'lastName': lastName,
    'schoolId': classModel.schoolId,
    'classId': classModel.id,
    'currentReadingLevel': currentReadingLevel,
    'isActive': true,
    'parentIds': const <String>[],
    'levelHistory': const <Map<String, dynamic>>[],
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'stats': {
      'totalMinutesRead': 30,
      'totalBooksRead': totalBooksRead,
      'currentStreak': currentStreak,
      'longestStreak': currentStreak,
      'lastReadingDate': Timestamp.fromDate(lastReadingDate),
      'averageMinutesPerDay': 10.0,
      'totalReadingDays': totalBooksRead,
    },
  });
}

Future<void> _seedAllocation(
  FakeFirebaseFirestore firestore, {
  required ClassModel classModel,
  required String id,
  required String type,
  required List<String> studentIds,
  DateTime? startDate,
  DateTime? endDate,
  bool isActive = true,
  Map<String, dynamic>? studentOverrides,
}) async {
  final now = DateTime.now();
  await firestore
      .collection('schools')
      .doc(classModel.schoolId)
      .collection('allocations')
      .doc(id)
      .set({
    'schoolId': classModel.schoolId,
    'classId': classModel.id,
    'teacherId': 'teacher_1',
    'studentIds': studentIds,
    'type': type,
    'cadence': 'weekly',
    'targetMinutes': 20,
    'startDate': Timestamp.fromDate(
      startDate ?? now.subtract(const Duration(days: 1)),
    ),
    'endDate': Timestamp.fromDate(
      endDate ?? now.add(const Duration(days: 6)),
    ),
    'assignmentItems': const [
      {
        'id': 'book_hp',
        'title': 'Harry Potter',
      },
    ],
    'schemaVersion': 2,
    'isRecurring': false,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'createdBy': 'teacher_1',
    if (studentOverrides != null) 'studentOverrides': studentOverrides,
  });
}
