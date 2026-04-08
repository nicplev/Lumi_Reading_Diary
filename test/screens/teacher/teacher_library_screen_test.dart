import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumi_reading_tracker/data/models/book_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/teacher/teacher_library_screen.dart';
import 'package:lumi_reading_tracker/services/school_library_assignment_service.dart';
import 'package:lumi_reading_tracker/services/school_library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TeacherLibraryScreen', () {
    late UserModel teacher;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      teacher = UserModel(
        id: 'teacher_1',
        email: 'teacher@example.com',
        fullName: 'Test Teacher',
        role: UserRole.teacher,
        schoolId: 'school_1',
        createdAt: DateTime(2026, 1, 1),
      );
    });

    testWidgets('Add Book pushes scanner route with teacher extra',
        (tester) async {
      Object? capturedExtra;

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TeacherLibraryScreen(
                teacher: teacher,
                libraryService: _FakeSchoolLibraryService(const []),
                assignmentService: _FakeSchoolLibraryAssignmentService(),
              ),
            ),
          ),
          GoRoute(
            path: '/teacher/community-scanner',
            builder: (context, state) {
              capturedExtra = state.extra;
              return const Scaffold(
                body: Center(child: Text('Community Scanner')),
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Add Book'), findsWidgets);

      await tester.tap(find.text('Add Book').first);
      await tester.pumpAndSettle();

      expect(find.text('Community Scanner'), findsOneWidget);
      expect(capturedExtra, same(teacher));
    });

    testWidgets('renders library books and count-aware filter chips',
        (tester) async {
      await tester.pumpWidget(_wrapLibrary(
        teacher: teacher,
        books: [
          _book(
            id: 'book_1',
            title: 'A Nap',
            author: 'Lumi',
            isbn: '111',
          ),
          _book(
            id: 'book_2',
            title: 'Fish and Chips',
            author: 'LLLL',
            isbn: '222',
            readingLevel: 'Stage 1',
            isDecodable: true,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Book Library'), findsOneWidget);
      expect(find.text('2 books in your school library'), findsOneWidget);
      expect(find.text('All 2'), findsOneWidget);
      expect(find.text('Decodable 1'), findsOneWidget);
      expect(find.text('Library 1'), findsOneWidget);
      expect(find.text('Fish and Chips'), findsOneWidget);

      await tester.tap(find.text('Library 1'));
      await tester.pumpAndSettle();

      expect(find.text('A Nap'), findsOneWidget);
    });

    testWidgets('filters to decodable books', (tester) async {
      await tester.pumpWidget(_wrapLibrary(
        teacher: teacher,
        books: [
          _book(id: 'book_1', title: 'Library Book'),
          _book(
            id: 'book_2',
            title: 'Stage Book',
            readingLevel: 'Stage 2',
            isDecodable: true,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decodable 1'));
      await tester.pumpAndSettle();

      expect(find.text('Stage Book'), findsOneWidget);
      expect(find.text('Library Book'), findsNothing);
    });

    testWidgets('shows no-results state and clears search', (tester) async {
      await tester.pumpWidget(_wrapLibrary(
        teacher: teacher,
        books: [
          _book(id: 'book_1', title: 'Library Book'),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pumpAndSettle();

      expect(find.text('No matches found'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      await tester.tap(find.text('Clear Search'));
      await tester.pumpAndSettle();

      expect(find.text('Library Book'), findsOneWidget);
      expect(find.text('No matches found'), findsNothing);
    });

    testWidgets('unfocuses search when tapping outside', (tester) async {
      await tester.pumpWidget(_wrapLibrary(
        teacher: teacher,
        books: [
          _book(id: 'book_1', title: 'Library Book'),
          _book(
            id: 'book_2',
            title: 'Stage Book',
            readingLevel: 'Stage 2',
            isDecodable: true,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      final editableText = find.byType(EditableText);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'library');
      await tester.pumpAndSettle();

      expect(
          tester.widget<EditableText>(editableText).focusNode.hasFocus, isTrue);

      await tester.tap(find.text('All 2'));
      await tester.pumpAndSettle();

      expect(tester.widget<EditableText>(editableText).focusNode.hasFocus,
          isFalse);
    });

    testWidgets('animates search focus fill on focus changes', (tester) async {
      await tester.pumpWidget(_wrapLibrary(
        teacher: teacher,
        books: [
          _book(id: 'book_1', title: 'Library Book'),
          _book(
            id: 'book_2',
            title: 'Stage Book',
            readingLevel: 'Stage 2',
            isDecodable: true,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      final fill = find.byKey(const ValueKey('library_search_focus_fill'));
      expect(tester.widget<FractionallySizedBox>(fill).widthFactor, 0);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 280));

      expect(
        tester.widget<FractionallySizedBox>(fill).widthFactor,
        closeTo(1, 0.001),
      );

      await tester.tap(find.text('All 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(
        tester.widget<FractionallySizedBox>(fill).widthFactor,
        closeTo(0, 0.001),
      );
    });

    testWidgets('empty state includes add book action', (tester) async {
      await tester.pumpWidget(_wrapLibrary(
        teacher: teacher,
        books: const [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('No books yet'), findsOneWidget);
      expect(find.text('Add Book'), findsWidgets);
    });
  });
}

Widget _wrapLibrary({
  required UserModel teacher,
  required List<BookModel> books,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TeacherLibraryScreen(
        teacher: teacher,
        libraryService: _FakeSchoolLibraryService(books),
        assignmentService: _FakeSchoolLibraryAssignmentService(),
      ),
    ),
  );
}

BookModel _book({
  required String id,
  required String title,
  String? author,
  String? isbn,
  String? readingLevel,
  bool isDecodable = false,
}) {
  return BookModel(
    id: id,
    title: title,
    author: author,
    isbn: isbn,
    readingLevel: readingLevel,
    createdAt: DateTime(2026, 1, 1),
    metadata: isDecodable ? {'source': 'llll_local_db'} : null,
  );
}

class _FakeSchoolLibraryService extends SchoolLibraryService {
  _FakeSchoolLibraryService(this._books)
      : super(firestore: FakeFirebaseFirestore());

  final List<BookModel> _books;

  @override
  Stream<List<BookModel>> booksStream(String schoolId) {
    return Stream.value(_books);
  }
}

class _FakeSchoolLibraryAssignmentService
    extends SchoolLibraryAssignmentService {
  _FakeSchoolLibraryAssignmentService()
      : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<LibraryAssignmentSnapshot> summaryStream(String schoolId) {
    return Stream.value(const LibraryAssignmentSnapshot());
  }
}
