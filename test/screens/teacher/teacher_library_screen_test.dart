import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumi_reading_tracker/data/models/book_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/teacher/teacher_library_screen.dart';
import 'package:lumi_reading_tracker/services/school_library_assignment_service.dart';
import 'package:lumi_reading_tracker/services/school_library_service.dart';

void main() {
  group('TeacherLibraryScreen', () {
    testWidgets('Add Book pushes scanner route with teacher extra',
        (tester) async {
      final teacher = UserModel(
        id: 'teacher_1',
        email: 'teacher@example.com',
        fullName: 'Test Teacher',
        role: UserRole.teacher,
        schoolId: 'school_1',
        createdAt: DateTime(2026, 1, 1),
      );
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

      expect(find.text('Add Book'), findsOneWidget);

      await tester.tap(find.text('Add Book'));
      await tester.pumpAndSettle();

      expect(find.text('Community Scanner'), findsOneWidget);
      expect(capturedExtra, same(teacher));
    });
  });
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
