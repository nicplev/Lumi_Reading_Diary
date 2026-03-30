import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/book_model.dart';
import '../data/models/student_model.dart';
import 'reading_level_service.dart';

/// Service for generating personalized book recommendations
/// Uses reading level, history, and popularity to suggest appropriate books
class BookRecommendationService {
  final FirebaseFirestore _firestore;
  final ReadingLevelService _readingLevelService;

  BookRecommendationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _readingLevelService = ReadingLevelService(
            firestore: firestore ?? FirebaseFirestore.instance);

  CollectionReference<Map<String, dynamic>> _schoolBooks(String schoolId) {
    return _firestore.collection('schools').doc(schoolId).collection('books');
  }

  /// Get personalized recommendations for a student
  ///
  /// Algorithm considers:
  /// 1. Student's reading level
  /// 2. Previously read books (to avoid duplicates)
  /// 3. Popular books at that level
  /// 4. Genre diversity
  Future<List<BookModel>> getRecommendationsForStudent(
    StudentModel student, {
    int limit = 10,
  }) async {
    try {
      // Get books the student has already read
      final readBooksSnapshot = await _firestore
          .collection('bookReadingHistory')
          .where('studentId', isEqualTo: student.id)
          .get();

      final readBookIds = readBooksSnapshot.docs
          .map((doc) => (doc.data())['bookId'] as String)
          .toSet();

      // Build query for recommendations
      Query query = _schoolBooks(student.schoolId);
      final normalizedStudentLevel = await _normalizeReadingLevel(
        schoolId: student.schoolId,
        value: student.currentReadingLevel,
      );

      // Filter by reading level if available
      if (normalizedStudentLevel != null) {
        query = query.where('readingLevel', isEqualTo: normalizedStudentLevel);
      }

      // Get popular books first
      query = query.orderBy('isPopular', descending: true);
      query = query.orderBy('timesRead', descending: true);
      query = query.limit(limit * 3); // Get more than needed to filter

      final snapshot = await query.get();

      // Convert to BookModel and filter out already read books
      final allBooks = snapshot.docs
          .map((doc) => BookModel.fromFirestore(doc))
          .where((book) => !readBookIds.contains(book.id))
          .toList();

      // Diversify by genre
      final recommendations = _diversifyByGenre(allBooks, limit);

      return recommendations;
    } catch (e) {
      debugPrint('Error getting recommendations: $e');
      return [];
    }
  }

  /// Get popular books by reading level
  Future<List<BookModel>> getPopularBooksByLevel(
    String readingLevel, {
    required String schoolId,
    int limit = 20,
  }) async {
    try {
      final normalizedReadingLevel = await _normalizeReadingLevel(
        schoolId: schoolId,
        value: readingLevel,
      );
      if (normalizedReadingLevel == null) return [];

      final snapshot = await _schoolBooks(schoolId)
          .where('readingLevel', isEqualTo: normalizedReadingLevel)
          .orderBy('timesRead', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => BookModel.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error getting popular books: $e');
      return [];
    }
  }

  /// Get books by genre
  Future<List<BookModel>> getBooksByGenre(
    String genre, {
    required String schoolId,
    int limit = 20,
    String? readingLevel,
  }) async {
    try {
      final normalizedReadingLevel = await _normalizeReadingLevel(
        schoolId: schoolId,
        value: readingLevel,
      );
      Query query =
          _schoolBooks(schoolId).where('genres', arrayContains: genre);

      if (normalizedReadingLevel != null) {
        query = query.where('readingLevel', isEqualTo: normalizedReadingLevel);
      }

      query = query.orderBy('timesRead', descending: true).limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) => BookModel.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error getting books by genre: $e');
      return [];
    }
  }

  /// Search books by title or author
  Future<List<BookModel>> searchBooks(
    String searchTerm, {
    required String schoolId,
    String? readingLevel,
    int limit = 20,
  }) async {
    try {
      final normalizedReadingLevel = await _normalizeReadingLevel(
        schoolId: schoolId,
        value: readingLevel,
      );
      // This is a simple implementation
      // For production, consider using Algolia or ElasticSearch
      final titleSnapshot = await _schoolBooks(schoolId)
          .orderBy('title')
          .startAt([searchTerm])
          .endAt(['$searchTerm\uf8ff'])
          .limit(limit)
          .get();

      final authorSnapshot = await _schoolBooks(schoolId)
          .orderBy('author')
          .startAt([searchTerm])
          .endAt(['$searchTerm\uf8ff'])
          .limit(limit)
          .get();

      final allDocs = <DocumentSnapshot>{
        ...titleSnapshot.docs,
        ...authorSnapshot.docs,
      };

      var books = allDocs.map((doc) => BookModel.fromFirestore(doc)).toList();

      // Filter by reading level if specified
      if (normalizedReadingLevel != null) {
        books = books
            .where((book) => book.readingLevel == normalizedReadingLevel)
            .toList();
      }

      // Sort by relevance (simple: exact matches first, then by popularity)
      books.sort((a, b) {
        final aExact = a.title.toLowerCase() == searchTerm.toLowerCase() ||
            a.author?.toLowerCase() == searchTerm.toLowerCase();
        final bExact = b.title.toLowerCase() == searchTerm.toLowerCase() ||
            b.author?.toLowerCase() == searchTerm.toLowerCase();

        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;

        return b.timesRead.compareTo(a.timesRead);
      });

      return books.take(limit).toList();
    } catch (e) {
      debugPrint('Error searching books: $e');
      return [];
    }
  }

  /// Get similar books based on a book
  Future<List<BookModel>> getSimilarBooks(
    BookModel book, {
    required String schoolId,
    int limit = 10,
  }) async {
    try {
      // Find books with similar genres and reading level
      if (book.genres.isEmpty) {
        // If no genres, just get books at same level
        return getPopularBooksByLevel(
          book.readingLevel ?? '',
          schoolId: schoolId,
          limit: limit,
        );
      }

      // Get books sharing at least one genre
      final snapshot = await _schoolBooks(schoolId)
          .where('genres', arrayContainsAny: book.genres.take(10).toList())
          .where('readingLevel', isEqualTo: book.readingLevel)
          .orderBy('timesRead', descending: true)
          .limit(limit + 1) // Get one extra to exclude current book
          .get();

      final books = snapshot.docs
          .map((doc) => BookModel.fromFirestore(doc))
          .where((b) => b.id != book.id) // Exclude the current book
          .take(limit)
          .toList();

      return books;
    } catch (e) {
      debugPrint('Error getting similar books: $e');
      return [];
    }
  }

  /// Get new/recently added books
  Future<List<BookModel>> getRecentlyAddedBooks({
    required String schoolId,
    String? readingLevel,
    int limit = 20,
  }) async {
    try {
      final normalizedReadingLevel = await _normalizeReadingLevel(
        schoolId: schoolId,
        value: readingLevel,
      );
      Query query =
          _schoolBooks(schoolId).orderBy('createdAt', descending: true);

      if (normalizedReadingLevel != null) {
        query = query.where('readingLevel', isEqualTo: normalizedReadingLevel);
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) => BookModel.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error getting recently added books: $e');
      return [];
    }
  }

  /// Get books a student is currently reading
  Future<List<BookModel>> getCurrentlyReading(
    String studentId, {
    required String schoolId,
  }) async {
    try {
      // Get reading history where book is not completed
      final historySnapshot = await _firestore
          .collection('bookReadingHistory')
          .where('studentId', isEqualTo: studentId)
          .where('isCompleted', isEqualTo: false)
          .get();

      final bookIds = historySnapshot.docs
          .map((doc) => (doc.data())['bookId'] as String)
          .toList();

      if (bookIds.isEmpty) return [];

      // Firestore 'in' queries limited to 10 items
      final books = <BookModel>[];
      for (final bookId in bookIds.take(10)) {
        final doc = await _schoolBooks(schoolId).doc(bookId).get();
        if (doc.exists) {
          books.add(BookModel.fromFirestore(doc));
        }
      }

      return books;
    } catch (e) {
      debugPrint('Error getting currently reading books: $e');
      return [];
    }
  }

  /// Get books a student has completed
  Future<List<BookModel>> getCompletedBooks(
    String studentId, {
    required String schoolId,
  }) async {
    try {
      final historySnapshot = await _firestore
          .collection('bookReadingHistory')
          .where('studentId', isEqualTo: studentId)
          .where('isCompleted', isEqualTo: true)
          .orderBy('completedAt', descending: true)
          .get();

      final bookIds = historySnapshot.docs
          .map((doc) => (doc.data())['bookId'] as String)
          .toList();

      if (bookIds.isEmpty) return [];

      final books = <BookModel>[];
      for (final bookId in bookIds.take(20)) {
        final doc = await _schoolBooks(schoolId).doc(bookId).get();
        if (doc.exists) {
          books.add(BookModel.fromFirestore(doc));
        }
      }

      return books;
    } catch (e) {
      debugPrint('Error getting completed books: $e');
      return [];
    }
  }

  /// Record that a student started reading a book
  Future<void> recordBookStart(
    String studentId,
    String bookId, {
    required String schoolId,
  }) async {
    try {
      // Check if already started
      final existing = await _firestore
          .collection('bookReadingHistory')
          .where('studentId', isEqualTo: studentId)
          .where('bookId', isEqualTo: bookId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        // Already started, don't create duplicate
        return;
      }

      // Create new reading history entry
      await _firestore.collection('bookReadingHistory').add({
        'studentId': studentId,
        'bookId': bookId,
        'startedAt': FieldValue.serverTimestamp(),
        'minutesSpent': 0,
        'isCompleted': false,
      });

      // Increment timesRead for the book
      await _schoolBooks(schoolId).doc(bookId).update({
        'timesRead': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('Error recording book start: $e');
      rethrow;
    }
  }

  /// Record that a student completed a book
  Future<void> recordBookCompletion(
    String studentId,
    String bookId, {
    required String schoolId,
    double? rating,
    String? review,
  }) async {
    try {
      // Find the reading history entry
      final historySnapshot = await _firestore
          .collection('bookReadingHistory')
          .where('studentId', isEqualTo: studentId)
          .where('bookId', isEqualTo: bookId)
          .limit(1)
          .get();

      if (historySnapshot.docs.isEmpty) {
        // Create new entry if doesn't exist
        await _firestore.collection('bookReadingHistory').add({
          'studentId': studentId,
          'bookId': bookId,
          'startedAt': FieldValue.serverTimestamp(),
          'completedAt': FieldValue.serverTimestamp(),
          'isCompleted': true,
          'rating': rating,
          'review': review,
        });
      } else {
        // Update existing entry
        await _firestore
            .collection('bookReadingHistory')
            .doc(historySnapshot.docs.first.id)
            .update({
          'completedAt': FieldValue.serverTimestamp(),
          'isCompleted': true,
          if (rating != null) 'rating': rating,
          if (review != null) 'review': review,
        });
      }

      // Update book's average rating if rating provided
      if (rating != null) {
        await _updateBookRating(
          bookId,
          rating,
          schoolId: schoolId,
        );
      }
    } catch (e) {
      debugPrint('Error recording book completion: $e');
      rethrow;
    }
  }

  /// Update a book's average rating
  Future<void> _updateBookRating(
    String bookId,
    double newRating, {
    required String schoolId,
  }) async {
    try {
      final bookDoc = await _schoolBooks(schoolId).doc(bookId).get();
      if (!bookDoc.exists) return;

      final data = bookDoc.data()!;
      final currentRating = (data['averageRating'] as num?)?.toDouble() ?? 0.0;
      final currentCount = data['ratingCount'] as int? ?? 0;

      final newCount = currentCount + 1;
      final newAverage =
          ((currentRating * currentCount) + newRating) / newCount;

      await _schoolBooks(schoolId).doc(bookId).update({
        'averageRating': newAverage,
        'ratingCount': newCount,
      });
    } catch (e) {
      debugPrint('Error updating book rating: $e');
    }
  }

  /// Diversify book list by genre to provide variety
  List<BookModel> _diversifyByGenre(List<BookModel> books, int limit) {
    if (books.length <= limit) return books;

    final diversified = <BookModel>[];
    final seenGenres = <String>{};

    // First pass: Add books with unique genres
    for (final book in books) {
      if (diversified.length >= limit) break;

      final hasNewGenre =
          book.genres.any((genre) => !seenGenres.contains(genre));

      if (hasNewGenre || diversified.isEmpty) {
        diversified.add(book);
        seenGenres.addAll(book.genres);
      }
    }

    // Second pass: Fill remaining slots with most popular
    if (diversified.length < limit) {
      for (final book in books) {
        if (diversified.length >= limit) break;
        if (!diversified.contains(book)) {
          diversified.add(book);
        }
      }
    }

    return diversified;
  }

  /// Get all available genres
  Future<List<String>> getAllGenres({required String schoolId}) async {
    try {
      // This is a simplified version
      // In production, you might want to maintain a separate genres collection
      final snapshot = await _schoolBooks(schoolId).limit(100).get();

      final genresSet = <String>{};
      for (final doc in snapshot.docs) {
        final genres = List<String>.from(doc.data()['genres'] ?? []);
        genresSet.addAll(genres);
      }

      final genresList = genresSet.toList()..sort();
      return genresList;
    } catch (e) {
      debugPrint('Error getting genres: $e');
      return [];
    }
  }

  /// Get reading levels available in the system
  Future<List<String>> getAllReadingLevels({required String schoolId}) async {
    try {
      final options = await _readingLevelService.loadSchoolLevels(schoolId);
      return options.map((option) => option.value).toList(growable: false);
    } catch (e) {
      debugPrint('Error getting reading levels: $e');
      return [];
    }
  }

  Future<String?> _normalizeReadingLevel({
    required String schoolId,
    required String? value,
  }) async {
    if (value == null || value.trim().isEmpty) return null;
    final options = await _readingLevelService.loadSchoolLevels(schoolId);
    return _readingLevelService.normalizeLevel(value, options: options);
  }
}
