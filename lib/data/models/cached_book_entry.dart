import 'book_model.dart';

/// Local-only DTO for the teacher device book cache.
/// Maps to/from [BookModel] without exposing Hive types.
class CachedBookEntry {
  final String isbn;
  final String title;
  final String? author;
  final String? coverImageUrl;
  final String bookId;
  final String? readingLevel;
  final String source;
  final String teacherId;
  final String schoolId;
  final DateTime cachedAt;
  DateTime lastUsedAt;

  CachedBookEntry({
    required this.isbn,
    required this.title,
    this.author,
    this.coverImageUrl,
    required this.bookId,
    this.readingLevel,
    required this.source,
    required this.teacherId,
    required this.schoolId,
    required this.cachedAt,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'isbn': isbn,
      'title': title,
      'author': author,
      'coverImageUrl': coverImageUrl,
      'bookId': bookId,
      'readingLevel': readingLevel,
      'source': source,
      'teacherId': teacherId,
      'schoolId': schoolId,
      'cachedAt': cachedAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
    };
  }

  /// Deserialize from a Hive map. Throws [FormatException] if required
  /// fields (isbn, title, bookId) are missing or empty — the caller should
  /// treat a corrupted entry as a cache miss and delete it.
  factory CachedBookEntry.fromMap(Map<String, dynamic> map) {
    final isbn = (map['isbn'] as String?)?.trim() ?? '';
    final title = (map['title'] as String?)?.trim() ?? '';
    final bookId = (map['bookId'] as String?)?.trim() ?? '';

    if (isbn.isEmpty || title.isEmpty || bookId.isEmpty) {
      throw FormatException(
        'CachedBookEntry: required fields missing '
        '(isbn=$isbn, title=$title, bookId=$bookId)',
      );
    }

    return CachedBookEntry(
      isbn: isbn,
      title: title,
      author: map['author'] as String?,
      coverImageUrl: map['coverImageUrl'] as String?,
      bookId: bookId,
      readingLevel: map['readingLevel'] as String?,
      source: map['source'] as String? ?? 'unknown',
      teacherId: map['teacherId'] as String? ?? '',
      schoolId: map['schoolId'] as String? ?? '',
      cachedAt: DateTime.tryParse(map['cachedAt'] as String? ?? '') ??
          DateTime.now(),
      lastUsedAt: DateTime.tryParse(map['lastUsedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  BookModel toBookModel() {
    return BookModel(
      id: bookId,
      title: title,
      author: author,
      isbn: isbn,
      coverImageUrl: coverImageUrl,
      readingLevel: readingLevel,
      createdAt: cachedAt,
      metadata: {'source': source, 'fromDeviceCache': true},
    );
  }

  factory CachedBookEntry.fromBookModel(
    BookModel book, {
    required String teacherId,
    required String schoolId,
  }) {
    final now = DateTime.now();
    return CachedBookEntry(
      isbn: book.isbn ?? '',
      title: book.title,
      author: book.author,
      coverImageUrl: book.coverImageUrl,
      bookId: book.id,
      readingLevel: book.readingLevel,
      source: book.metadata?['source'] as String? ?? 'unknown',
      teacherId: teacherId,
      schoolId: schoolId,
      cachedAt: now,
      lastUsedAt: now,
    );
  }
}
