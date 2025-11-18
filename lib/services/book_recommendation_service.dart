import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/book_model.dart';
import '../data/models/student_model.dart';

/// Service for generating personalized book recommendations
/// Uses reading level, history, and popularity to suggest appropriate books
class BookRecommendationService {
  final FirebaseFirestore _firestore;

  BookRecommendationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

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
      Query query = _firestore.collection('books');

      // Filter by reading level if available
      if (student.currentReadingLevel != null) {
        query = query.where('readingLevel',
            isEqualTo: student.currentReadingLevel);
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
      print('Error getting recommendations: $e');
      return [];
    }
  }

  /// Get popular books by reading level
  Future<List<BookModel>> getPopularBooksByLevel(
    String readingLevel, {
    int limit = 20,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('books')
          .where('readingLevel', isEqualTo: readingLevel)
          .orderBy('timesRead', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => BookModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error getting popular books: $e');
      return [];
    }
  }

  /// Get books by genre
  Future<List<BookModel>> getBooksByGenre(
    String genre, {
    int limit = 20,
    String? readingLevel,
  }) async {
    try {
      Query query = _firestore
          .collection('books')
          .where('genres', arrayContains: genre);

      if (readingLevel != null) {
        query = query.where('readingLevel', isEqualTo: readingLevel);
      }

      query = query.orderBy('timesRead', descending: true).limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) => BookModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error getting books by genre: $e');
      return [];
    }
  }

  /// Search books by title or author
  Future<List<BookModel>> searchBooks(
    String searchTerm, {
    String? readingLevel,
    int limit = 20,
  }) async {
    try {
      // This is a simple implementation
      // For production, consider using Algolia or ElasticSearch
      final titleSnapshot = await _firestore
          .collection('books')
          .orderBy('title')
          .startAt([searchTerm])
          .endAt(['$searchTerm\uf8ff'])
          .limit(limit)
          .get();

      final authorSnapshot = await _firestore
          .collection('books')
          .orderBy('author')
          .startAt([searchTerm])
          .endAt(['$searchTerm\uf8ff'])
          .limit(limit)
          .get();

      final allDocs = <DocumentSnapshot>{
        ...titleSnapshot.docs,
        ...authorSnapshot.docs,
      };

      var books =
          allDocs.map((doc) => BookModel.fromFirestore(doc)).toList();

      // Filter by reading level if specified
      if (readingLevel != null) {
        books = books
            .where((book) => book.readingLevel == readingLevel)
            .toList();
      }

      // Sort by relevance (simple: exact matches first, then by popularity)
      books.sort((a, b) {
        final aExact = a.title.toLowerCase() == searchTerm.toLowerCase() ||
            (a.author?.toLowerCase() == searchTerm.toLowerCase() ?? false);
        final bExact = b.title.toLowerCase() == searchTerm.toLowerCase() ||
            (b.author?.toLowerCase() == searchTerm.toLowerCase() ?? false);

        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;

        return b.timesRead.compareTo(a.timesRead);
      });

      return books.take(limit).toList();
    } catch (e) {
      print('Error searching books: $e');
      return [];
    }
  }

  /// Get similar books based on a book
  Future<List<BookModel>> getSimilarBooks(
    BookModel book, {
    int limit = 10,
  }) async {
    try {
      // Find books with similar genres and reading level
      if (book.genres.isEmpty) {
        // If no genres, just get books at same level
        return getPopularBooksByLevel(
          book.readingLevel ?? '',
          limit: limit,
        );
      }

      // Get books sharing at least one genre
      final snapshot = await _firestore
          .collection('books')
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
      print('Error getting similar books: $e');
      return [];
    }
  }

  /// Get new/recently added books
  Future<List<BookModel>> getRecentlyAddedBooks({
    String? readingLevel,
    int limit = 20,
  }) async {
    try {
      Query query = _firestore.collection('books').orderBy('createdAt', descending: true);

      if (readingLevel != null) {
        query = query.where('readingLevel', isEqualTo: readingLevel);
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) => BookModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error getting recently added books: $e');
      return [];
    }
  }

  /// Get books a student is currently reading
  Future<List<BookModel>> getCurrentlyReading(String studentId) async {
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
        final doc = await _firestore.collection('books').doc(bookId).get();
        if (doc.exists) {
          books.add(BookModel.fromFirestore(doc));
        }
      }

      return books;
    } catch (e) {
      print('Error getting currently reading books: $e');
      return [];
    }
  }

  /// Get books a student has completed
  Future<List<BookModel>> getCompletedBooks(String studentId) async {
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
        final doc = await _firestore.collection('books').doc(bookId).get();
        if (doc.exists) {
          books.add(BookModel.fromFirestore(doc));
        }
      }

      return books;
    } catch (e) {
      print('Error getting completed books: $e');
      return [];
    }
  }

  /// Record that a student started reading a book
  Future<void> recordBookStart(String studentId, String bookId) async {
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
      await _firestore.collection('books').doc(bookId).update({
        'timesRead': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error recording book start: $e');
      rethrow;
    }
  }

  /// Record that a student completed a book
  Future<void> recordBookCompletion(
    String studentId,
    String bookId, {
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
        await _updateBookRating(bookId, rating);
      }
    } catch (e) {
      print('Error recording book completion: $e');
      rethrow;
    }
  }

  /// Update a book's average rating
  Future<void> _updateBookRating(String bookId, double newRating) async {
    try {
      final bookDoc = await _firestore.collection('books').doc(bookId).get();
      if (!bookDoc.exists) return;

      final data = bookDoc.data()!;
      final currentRating = (data['averageRating'] as num?)?.toDouble() ?? 0.0;
      final currentCount = data['ratingCount'] as int? ?? 0;

      final newCount = currentCount + 1;
      final newAverage =
          ((currentRating * currentCount) + newRating) / newCount;

      await _firestore.collection('books').doc(bookId).update({
        'averageRating': newAverage,
        'ratingCount': newCount,
      });
    } catch (e) {
      print('Error updating book rating: $e');
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
  Future<List<String>> getAllGenres() async {
    try {
      // This is a simplified version
      // In production, you might want to maintain a separate genres collection
      final snapshot = await _firestore
          .collection('books')
          .limit(100) // Sample books
          .get();

      final genresSet = <String>{};
      for (final doc in snapshot.docs) {
        final genres = List<String>.from(doc.data()['genres'] ?? []);
        genresSet.addAll(genres);
      }

      final genresList = genresSet.toList()..sort();
      return genresList;
    } catch (e) {
      print('Error getting genres: $e');
      return [];
    }
  }

  /// Get reading levels available in the system
  Future<List<String>> getAllReadingLevels() async {
    try {
      // Sample books to find levels
      final snapshot = await _firestore
          .collection('books')
          .limit(100)
          .get();

      final levelsSet = <String>{};
      for (final doc in snapshot.docs) {
        final level = doc.data()['readingLevel'] as String?;
        if (level != null && level.isNotEmpty) {
          levelsSet.add(level);
        }
      }

      final levelsList = levelsSet.toList()..sort();
      return levelsList;
    } catch (e) {
      print('Error getting reading levels: $e');
      return [];
    }
  }
}
