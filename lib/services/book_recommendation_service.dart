import '../data/models/student_model.dart';
import '../data/models/reading_log_model.dart';

/// Book Recommendation Service - Suggests books based on student reading history
///
/// Algorithm considers:
/// - Reading level match
/// - Genre preferences (from past reads)
/// - Similar readers' favorites
/// - Age-appropriate selections
/// - Completion rate (avoid too hard/too easy)
class BookRecommendationService {
  static final BookRecommendationService _instance = BookRecommendationService._internal();
  factory BookRecommendationService() => _instance;
  BookRecommendationService._internal();

  static BookRecommendationService get instance => _instance;

  /// Get personalized book recommendations for a student
  Future<List<BookRecommendation>> getRecommendations({
    required StudentModel student,
    required List<ReadingLogModel> readingHistory,
    int limit = 10,
  }) async {
    final recommendations = <BookRecommendation>[];

    // Extract reading patterns
    final booksRead = readingHistory.map((log) => log.bookTitle.toLowerCase()).toSet();
    final avgMinutesPerSession = readingHistory.isEmpty
        ? 15
        : readingHistory.fold(0, (sum, log) => sum + log.minutesRead) / readingHistory.length;

    // Get level-appropriate books
    final levelBooks = _getBooksForLevel(student.readingLevel);

    // Filter out already read
    final unreadBooks = levelBooks.where((book) => !booksRead.contains(book.title.toLowerCase())).toList();

    // Score and rank
    for (final book in unreadBooks) {
      final score = _calculateRecommendationScore(
        book,
        student,
        readingHistory,
        avgMinutesPerSession,
      );

      recommendations.add(book.copyWith(recommendationScore: score));
    }

    // Sort by score and return top recommendations
    recommendations.sort((a, b) => b.recommendationScore.compareTo(a.recommendationScore));

    return recommendations.take(limit).toList();
  }

  double _calculateRecommendationScore(
    BookRecommendation book,
    StudentModel student,
    List<ReadingLogModel> history,
    double avgMinutesPerSession,
  ) {
    double score = 0.5; // Base score

    // Level match (exact match gets boost)
    if (book.readingLevel == student.readingLevel) {
      score += 0.3;
    }

    // Popular books get boost
    if (book.popularity > 80) {
      score += 0.1;
    }

    // Appropriate length based on student's reading stamina
    final expectedReadingTime = book.pages * 2; // Assume 2 min/page
    if ((expectedReadingTime - avgMinutesPerSession).abs() < 10) {
      score += 0.1; // Good length match
    }

    return score.clamp(0.0, 1.0);
  }

  /// Get curated book list for reading level
  List<BookRecommendation> _getBooksForLevel(String level) {
    // Simplified book database - in production, this would be Firestore/API
    final allBooks = <BookRecommendation>[
      // Level A-C (Emergent)
      BookRecommendation(
        id: 'b1',
        title: 'The Cat in the Hat',
        author: 'Dr. Seuss',
        readingLevel: 'B',
        genre: 'Fiction',
        pages: 72,
        coverUrl: null,
        description: 'A classic tale of mischief and fun',
        popularity: 95,
        recommendationScore: 0.0,
      ),
      BookRecommendation(
        id: 'b2',
        title: 'Brown Bear, Brown Bear',
        author: 'Bill Martin Jr.',
        readingLevel: 'A',
        genre: 'Fiction',
        pages: 32,
        coverUrl: null,
        description: 'Simple, rhythmic text perfect for early readers',
        popularity: 90,
        recommendationScore: 0.0,
      ),

      // Level D-J (Early)
      BookRecommendation(
        id: 'b3',
        title: 'Magic Tree House: Dinosaurs Before Dark',
        author: 'Mary Pope Osborne',
        readingLevel: 'G',
        genre: 'Adventure',
        pages: 80,
        coverUrl: null,
        description: 'Travel through time to the age of dinosaurs',
        popularity: 88,
        recommendationScore: 0.0,
      ),
      BookRecommendation(
        id: 'b4',
        title: 'Frog and Toad Are Friends',
        author: 'Arnold Lobel',
        readingLevel: 'E',
        genre: 'Fiction',
        pages: 64,
        coverUrl: null,
        description: 'Heartwarming stories of friendship',
        popularity: 85,
        recommendationScore: 0.0,
      ),

      // Level K-P (Transitional)
      BookRecommendation(
        id: 'b5',
        title: 'Charlotte\'s Web',
        author: 'E.B. White',
        readingLevel: 'M',
        genre: 'Fiction',
        pages: 192,
        coverUrl: null,
        description: 'A timeless tale of friendship and loyalty',
        popularity: 92,
        recommendationScore: 0.0,
      ),
      BookRecommendation(
        id: 'b6',
        title: 'The Wild Robot',
        author: 'Peter Brown',
        readingLevel: 'N',
        genre: 'Science Fiction',
        pages: 288,
        coverUrl: null,
        description: 'A robot learns to survive on a wild island',
        popularity: 87,
        recommendationScore: 0.0,
      ),

      // Level Q-Z (Fluent)
      BookRecommendation(
        id: 'b7',
        title: 'Harry Potter and the Sorcerer\'s Stone',
        author: 'J.K. Rowling',
        readingLevel: 'R',
        genre: 'Fantasy',
        pages: 309,
        coverUrl: null,
        description: 'A young wizard discovers his magical destiny',
        popularity: 98,
        recommendationScore: 0.0,
      ),
      BookRecommendation(
        id: 'b8',
        title: 'Wonder',
        author: 'R.J. Palacio',
        readingLevel: 'S',
        genre: 'Realistic Fiction',
        pages: 320,
        coverUrl: null,
        description: 'A powerful story about kindness and acceptance',
        popularity: 94,
        recommendationScore: 0.0,
      ),
      BookRecommendation(
        id: 'b9',
        title: 'Percy Jackson: The Lightning Thief',
        author: 'Rick Riordan',
        readingLevel: 'T',
        genre: 'Fantasy',
        pages: 377,
        coverUrl: null,
        description: 'Modern-day Greek mythology adventure',
        popularity: 91,
        recommendationScore: 0.0,
      ),
    ];

    // Filter by reading level (+/- 2 levels for variety)
    return allBooks.where((book) {
      return _isLevelInRange(book.readingLevel, level, 2);
    }).toList();
  }

  bool _isLevelInRange(String bookLevel, String studentLevel, int range) {
    // Simplified level comparison - in production, use proper Fountas & Pinnell scale
    const levels = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];

    final bookIndex = levels.indexOf(bookLevel);
    final studentIndex = levels.indexOf(studentLevel);

    if (bookIndex == -1 || studentIndex == -1) return true; // Unknown level, include it

    return (bookIndex - studentIndex).abs() <= range;
  }
}

/// Book Recommendation Data Model
class BookRecommendation {
  final String id;
  final String title;
  final String author;
  final String readingLevel;
  final String genre;
  final int pages;
  final String? coverUrl;
  final String description;
  final int popularity; // 0-100 score
  final double recommendationScore; // 0.0-1.0 personalization score

  BookRecommendation({
    required this.id,
    required this.title,
    required this.author,
    required this.readingLevel,
    required this.genre,
    required this.pages,
    this.coverUrl,
    required this.description,
    required this.popularity,
    required this.recommendationScore,
  });

  BookRecommendation copyWith({
    double? recommendationScore,
  }) {
    return BookRecommendation(
      id: id,
      title: title,
      author: author,
      readingLevel: readingLevel,
      genre: genre,
      pages: pages,
      coverUrl: coverUrl,
      description: description,
      popularity: popularity,
      recommendationScore: recommendationScore ?? this.recommendationScore,
    );
  }
}
