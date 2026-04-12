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

  // Schema provenance — stored in community_books so consumers know which
  // schema the readingLevel belongs to (e.g., 'pmBenchmark', 'llll_stages').
  final String? levelSchema;

  // School-specific overlay fields (stored in schools/{schoolId}/books only).
  // communityLevelSchema is copied from the community book at cache time.
  // schoolReadingLevel is set explicitly by this school's teacher.
  final String? communityLevelSchema;
  final String? schoolReadingLevel;

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

  // School library provenance
  final List<String>
      scannedByTeacherIds; // Teachers who scanned this into the school library
  final int
      timesAssignedSchoolWide; // Total times assigned to students across the school

  BookModel({
    required this.id,
    required this.title,
    this.author,
    this.isbn,
    this.coverImageUrl,
    this.description,
    this.genres = const [],
    this.readingLevel,
    this.levelSchema,
    this.communityLevelSchema,
    this.schoolReadingLevel,
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
    this.scannedByTeacherIds = const [],
    this.timesAssignedSchoolWide = 0,
  });

  factory BookModel.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data = rawData is Map<String, dynamic>
        ? rawData
        : rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : <String, dynamic>{};

    return BookModel(
      id: doc.id,
      title: _asString(data['title']),
      author: _asNullableString(data['author']),
      isbn: _asNullableString(data['isbn']),
      coverImageUrl: _asNullableString(data['coverImageUrl']),
      description: _asNullableString(data['description']),
      genres: _asStringList(data['genres']),
      readingLevel: _asNullableString(data['readingLevel']),
      levelSchema: _asNullableString(data['levelSchema']),
      communityLevelSchema: _asNullableString(data['communityLevelSchema']),
      schoolReadingLevel: _asNullableString(data['schoolReadingLevel']),
      pageCount: _asInt(data['pageCount']),
      publisher: _asNullableString(data['publisher']),
      publishedDate: _asDateTime(data['publishedDate']),
      tags: _asStringList(data['tags']),
      averageRating: _asDouble(data['averageRating']),
      ratingCount: _asInt(data['ratingCount']) ?? 0,
      isPopular: data['isPopular'] == true,
      timesRead: _asInt(data['timesRead']) ?? 0,
      createdAt: _asDateTime(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      addedBy: _asNullableString(data['addedBy']),
      metadata: _asStringMap(data['metadata']),
      scannedByTeacherIds: _asStringList(data['scannedByTeacherIds']),
      timesAssignedSchoolWide: _asInt(data['timesAssignedSchoolWide']) ?? 0,
    );
  }

  static String _asString(dynamic value) => value?.toString() ?? '';

  static String? _asNullableString(dynamic value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  static List<String> _asStringList(dynamic value) {
    if (value is! Iterable) return const [];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
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
      if (levelSchema != null) 'levelSchema': levelSchema,
      if (communityLevelSchema != null) 'communityLevelSchema': communityLevelSchema,
      if (schoolReadingLevel != null) 'schoolReadingLevel': schoolReadingLevel,
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
      'scannedByTeacherIds': scannedByTeacherIds,
      'timesAssignedSchoolWide': timesAssignedSchoolWide,
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
    String? levelSchema,
    String? communityLevelSchema,
    String? schoolReadingLevel,
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
    List<String>? scannedByTeacherIds,
    int? timesAssignedSchoolWide,
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
      levelSchema: levelSchema ?? this.levelSchema,
      communityLevelSchema: communityLevelSchema ?? this.communityLevelSchema,
      schoolReadingLevel: schoolReadingLevel ?? this.schoolReadingLevel,
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
      scannedByTeacherIds: scannedByTeacherIds ?? this.scannedByTeacherIds,
      timesAssignedSchoolWide:
          timesAssignedSchoolWide ?? this.timesAssignedSchoolWide,
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
