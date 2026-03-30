import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/book_model.dart';

void main() {
  group('BookModel', () {
    test('fromFirestore handles legacy docs with missing optional fields',
        () async {
      final firestore = FakeFirebaseFirestore();

      await firestore.collection('books').doc('legacy_book').set({
        'title': 'Legacy Book',
        'isbn': '9780123456786',
      });

      final doc = await firestore.collection('books').doc('legacy_book').get();
      final book = BookModel.fromFirestore(doc);

      expect(book.id, 'legacy_book');
      expect(book.title, 'Legacy Book');
      expect(book.isbn, '9780123456786');
      expect(book.author, isNull);
      expect(book.genres, isEmpty);
      expect(book.tags, isEmpty);
      expect(book.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(book.metadata, isNull);
      expect(book.scannedByTeacherIds, isEmpty);
      expect(book.timesAssignedSchoolWide, 0);
    });

    test('fromFirestore coerces common legacy scalar shapes safely', () async {
      final firestore = FakeFirebaseFirestore();

      await firestore.collection('books').doc('mixed_book').set({
        'title': 'Mixed Book',
        'genres': ['Fantasy', 42, null],
        'tags': ['tag-a', true],
        'pageCount': '120',
        'averageRating': 4,
        'ratingCount': '7',
        'timesRead': '3',
        'createdAt': '2026-01-02T03:04:05.000Z',
        'metadata': {
          'source': 'legacy_import',
        },
      });

      final doc = await firestore.collection('books').doc('mixed_book').get();
      final book = BookModel.fromFirestore(doc);

      expect(book.genres, ['Fantasy', '42']);
      expect(book.tags, ['tag-a', 'true']);
      expect(book.pageCount, 120);
      expect(book.averageRating, 4.0);
      expect(book.ratingCount, 7);
      expect(book.timesRead, 3);
      expect(book.createdAt, DateTime.parse('2026-01-02T03:04:05.000Z'));
      expect(book.metadata?['source'], 'legacy_import');
    });
  });
}
