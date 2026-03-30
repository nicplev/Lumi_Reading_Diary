import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/school_library_service.dart';

void main() {
  group('SchoolLibraryService', () {
    test('reads legacy top-level books when nested collection is empty',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = SchoolLibraryService(firestore: firestore);

      await firestore.collection('books').doc('isbn_legacy').set({
        'title': 'Legacy Library Book',
        'isbn': '9780123456786',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'metadata': {'source': 'legacy_import', 'placeholder': false},
      });

      final books = await service
          .booksStream('school_1')
          .firstWhere((items) => items.any((book) => book.id == 'isbn_legacy'));

      expect(books, hasLength(1));
      expect(books.first.id, 'isbn_legacy');
      expect(books.first.title, 'Legacy Library Book');
    });

    test('merges nested and legacy books and prefers nested duplicates',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = SchoolLibraryService(firestore: firestore);

      await firestore.collection('books').doc('isbn_shared').set({
        'title': 'Legacy Shared Title',
        'isbn': '9780000000001',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'metadata': {'source': 'legacy_import', 'placeholder': false},
      });
      await firestore.collection('books').doc('isbn_legacy_only').set({
        'title': 'Legacy Only',
        'isbn': '9780000000002',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'metadata': {'source': 'legacy_import', 'placeholder': false},
      });
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('books')
          .doc('isbn_shared')
          .set({
        'title': 'Nested Shared Title',
        'isbn': '9780000000001',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 3)),
        'metadata': {'source': 'nested_source', 'placeholder': false},
      });
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('books')
          .doc('isbn_nested_only')
          .set({
        'title': 'Nested Only',
        'isbn': '9780000000003',
        'schoolId': 'school_1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 4)),
        'metadata': {'source': 'nested_source', 'placeholder': false},
      });

      final books = await service.booksStream('school_1').firstWhere(
            (items) =>
                items.length == 3 &&
                items.any((book) => book.id == 'isbn_shared') &&
                items.any((book) => book.id == 'isbn_legacy_only') &&
                items.any((book) => book.id == 'isbn_nested_only'),
          );

      expect(books, hasLength(3));
      expect(books.first.id, 'isbn_nested_only');
      expect(
        books.firstWhere((book) => book.id == 'isbn_shared').title,
        'Nested Shared Title',
      );
    });
  });
}
