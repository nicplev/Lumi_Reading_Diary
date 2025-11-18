import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for books in the reading diary system
/// Supports book metadata, recommendations, and tracking
class BookModel {
  final String id;
  final String title;
  final String? author;
  final String? isbn;
  final String? coverImageUrl;
  final String? description;
  final List<String> genres;
  final String? readingLevel; // e.g., 'A', 'B', 'C' or '1', '2', '3'
  final int? pageCount;
  final String? publisher;
  final DateTime? publishedDate;
  final List<String> tags; // For categorization
  final double? averageRating; // 0-5 stars
  final int ratingCount;
  final bool isPopular;
  final int timesRead; // How many students have read this
  final DateTime createdAt;
  final String? addedBy; // User ID who added this book
  final Map<String, dynamic>? metadata;

  BookModel({
    required this.id,
    required this.title,
    this.author,
    this.isbn,
    this.coverImageUrl,
    this.description,
    this.genres = const [],
    this.readingLevel,
    this.pageCount,
    this.publisher,
    this.publishedDate,
    this.tags = const [],
    this.averageRating,
    this.ratingCount = 0,
    this.isPopular = false,
    this.timesRead = 0,
    required this.createdAt,
    this.addedBy,
    this.metadata,
  });

  factory BookModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BookModel(
      id: doc.id,
      title: data['title'] ?? '',
      author: data['author'],
      isbn: data['isbn'],
      coverImageUrl: data['coverImageUrl'],
      description: data['description'],
      genres: List<String>.from(data['genres'] ?? []),
      readingLevel: data['readingLevel'],
      pageCount: data['pageCount'],
      publisher: data['publisher'],
      publishedDate: data['publishedDate'] != null
          ? (data['publishedDate'] as Timestamp).toDate()
          : null,
      tags: List<String>.from(data['tags'] ?? []),
      averageRating: data['averageRating']?.toDouble(),
      ratingCount: data['ratingCount'] ?? 0,
      isPopular: data['isPopular'] ?? false,
      timesRead: data['timesRead'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      addedBy: data['addedBy'],
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'author': author,
      'isbn': isbn,
      'coverImageUrl': coverImageUrl,
      'description': description,
      'genres': genres,
      'readingLevel': readingLevel,
      'pageCount': pageCount,
      'publisher': publisher,
      'publishedDate':
          publishedDate != null ? Timestamp.fromDate(publishedDate!) : null,
      'tags': tags,
      'averageRating': averageRating,
      'ratingCount': ratingCount,
      'isPopular': isPopular,
      'timesRead': timesRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'addedBy': addedBy,
      'metadata': metadata,
    };
  }

  BookModel copyWith({
    String? id,
    String? title,
    String? author,
    String? isbn,
    String? coverImageUrl,
    String? description,
    List<String>? genres,
    String? readingLevel,
    int? pageCount,
    String? publisher,
    DateTime? publishedDate,
    List<String>? tags,
    double? averageRating,
    int? ratingCount,
    bool? isPopular,
    int? timesRead,
    DateTime? createdAt,
    String? addedBy,
    Map<String, dynamic>? metadata,
  }) {
    return BookModel(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      isbn: isbn ?? this.isbn,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      description: description ?? this.description,
      genres: genres ?? this.genres,
      readingLevel: readingLevel ?? this.readingLevel,
      pageCount: pageCount ?? this.pageCount,
      publisher: publisher ?? this.publisher,
      publishedDate: publishedDate ?? this.publishedDate,
      tags: tags ?? this.tags,
      averageRating: averageRating ?? this.averageRating,
      ratingCount: ratingCount ?? this.ratingCount,
      isPopular: isPopular ?? this.isPopular,
      timesRead: timesRead ?? this.timesRead,
      createdAt: createdAt ?? this.createdAt,
      addedBy: addedBy ?? this.addedBy,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Reading history entry for a student-book pair
class BookReadingHistory {
  final String id;
  final String studentId;
  final String bookId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int minutesSpent;
  final double? rating; // Student's rating (0-5)
  final String? review; // Student's review
  final bool isCompleted;

  BookReadingHistory({
    required this.id,
    required this.studentId,
    required this.bookId,
    required this.startedAt,
    this.completedAt,
    this.minutesSpent = 0,
    this.rating,
    this.review,
    this.isCompleted = false,
  });

  factory BookReadingHistory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BookReadingHistory(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      bookId: data['bookId'] ?? '',
      startedAt: (data['startedAt'] as Timestamp).toDate(),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
      minutesSpent: data['minutesSpent'] ?? 0,
      rating: data['rating']?.toDouble(),
      review: data['review'],
      isCompleted: data['isCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'bookId': bookId,
      'startedAt': Timestamp.fromDate(startedAt),
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'minutesSpent': minutesSpent,
      'rating': rating,
      'review': review,
      'isCompleted': isCompleted,
    };
  }
}
