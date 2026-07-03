import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/school_library_service.dart';

void main() {
  group('SchoolLibraryService.fetchBooksPage', () {
    CollectionReference<Map<String, dynamic>> nestedBooks(
      FakeFirebaseFirestore firestore,
      String schoolId,
    ) =>
        firestore
            .collection('schools')
            .doc(schoolId)
            .collection('books');

    test('reads nested library books and filters non-displayable ones',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = SchoolLibraryService(firestore: firestore);

      await nestedBooks(firestore, 'school_1').doc('isbn_real').set({
        'title': 'Real Library Book',
        'isbn': '9780123456786',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'metadata': {'source': 'nested_source', 'placeholder': false},
      });
      // Placeholder + "Unrecognised Book" rows are dropped by _isDisplayable.
      await nestedBooks(firestore, 'school_1').doc('isbn_placeholder').set({
        'title': 'Pending lookup',
        'isbn': '0000000000000',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 3)),
        'metadata': {'source': 'nested_source', 'placeholder': true},
      });
      await nestedBooks(firestore, 'school_1').doc('isbn_unrecognised').set({
        'title': 'Unrecognised Book',
        'isbn': '0000000000001',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 4)),
        'metadata': {'source': 'nested_source', 'placeholder': false},
      });

      final page = await service.fetchBooksPage('school_1');

      expect(page.books, hasLength(1));
      expect(page.books.first.id, 'isbn_real');
      expect(page.books.first.title, 'Real Library Book');
      expect(page.hasMore, isFalse);
    });

    Future<void> seedThree(FakeFirebaseFirestore firestore) async {
      final seeded = <String, DateTime>{
        'isbn_a': DateTime(2026, 1, 1),
        'isbn_b': DateTime(2026, 1, 2),
        'isbn_c': DateTime(2026, 1, 3),
      };
      for (final entry in seeded.entries) {
        await nestedBooks(firestore, 'school_1').doc(entry.key).set({
          'title': 'Title ${entry.key}',
          'isbn': entry.key,
          'schoolId': 'school_1',
          'createdAt': Timestamp.fromDate(entry.value),
          'metadata': {'source': 'nested_source', 'placeholder': false},
        });
      }
    }

    test('orders books newest-first and reports when more pages remain',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = SchoolLibraryService(firestore: firestore);
      await seedThree(firestore);

      // A full page (limit reached) signals more books remain via hasMore.
      final firstPage = await service.fetchBooksPage('school_1', limit: 2);
      expect(firstPage.books.map((b) => b.id).toList(), ['isbn_c', 'isbn_b']);
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.lastDocId, 'isbn_b');
    });

    test('startAfterDocId cursor skips the given doc and everything newer',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = SchoolLibraryService(firestore: firestore);
      await seedThree(firestore);

      // Continue after the newest book: the remaining two, still newest-first.
      final page =
          await service.fetchBooksPage('school_1', startAfterDocId: 'isbn_c');
      expect(page.books.map((b) => b.id).toList(), ['isbn_b', 'isbn_a']);
      expect(page.hasMore, isFalse);
    });
  });
}
