import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../data/models/book_model.dart';

/// Local LLLL (Little Learners Love Literacy) book database.
///
/// Loads a bundled JSON database built from the LEARNING LOGIC DATABASE CSV
/// and scraped Shopify cover images. Provides instant ISBN/barcode lookups
/// without any network calls — used as the first step in the
/// BookLookupService fallback chain.
class LlllBookDatabase {
  static const String _dbAssetPath = 'assets/data/llll_books_db.json';

  Map<String, dynamic>? _books;
  Map<String, List<String>>? _isbnIndex;
  bool _isLoaded = false;

  /// Whether the database has been loaded.
  bool get isLoaded => _isLoaded;

  /// Total number of books in the database.
  int get totalBooks => _books?.length ?? 0;

  /// Load the book database from the bundled asset.
  /// Call this once at app startup or before first lookup.
  Future<void> load() async {
    if (_isLoaded) return;

    final jsonStr = await rootBundle.loadString(_dbAssetPath);
    final data = json.decode(jsonStr) as Map<String, dynamic>;

    _books = (data['books'] as Map<String, dynamic>?) ?? {};

    final rawIndex = (data['isbnIndex'] as Map<String, dynamic>?) ?? {};
    _isbnIndex = rawIndex.map(
      (key, value) => MapEntry(key, List<String>.from(value as List)),
    );

    _isLoaded = true;
  }

  /// Look up a book by ISBN (scanned barcode).
  ///
  /// Returns the first matching book entry, or null if not found.
  /// Handles both raw ISBN with hyphens and normalised numeric-only ISBN.
  LlllBookResult? lookupByIsbn(String isbn) {
    _ensureLoaded();

    final normalised = _normaliseIsbn(isbn);
    if (normalised == null) return null;

    final productCodes = _isbnIndex?[normalised];
    if (productCodes == null || productCodes.isEmpty) return null;

    // Return the first match (typically the base product, not a state variant)
    final code = productCodes.first;
    return _getResult(code);
  }

  /// Look up all books matching an ISBN.
  ///
  /// Useful when an ISBN maps to multiple state variants.
  List<LlllBookResult> lookupAllByIsbn(String isbn) {
    _ensureLoaded();

    final normalised = _normaliseIsbn(isbn);
    if (normalised == null) return [];

    final productCodes = _isbnIndex?[normalised];
    if (productCodes == null) return [];

    return productCodes
        .map(_getResult)
        .whereType<LlllBookResult>()
        .toList();
  }

  /// Look up a book by its product code (e.g., "LLRS1", "LLFK3").
  LlllBookResult? lookupByProductCode(String productCode) {
    _ensureLoaded();
    return _getResult(productCode);
  }

  /// Search books by title (case-insensitive substring match).
  List<LlllBookResult> searchByTitle(String query, {int limit = 20}) {
    _ensureLoaded();
    if (_books == null) return [];

    final lowerQuery = query.toLowerCase();
    final results = <LlllBookResult>[];

    for (final entry in _books!.entries) {
      if (results.length >= limit) break;
      final title = (entry.value['title'] as String? ?? '').toLowerCase();
      if (title.contains(lowerQuery)) {
        final result = _getResult(entry.key);
        if (result != null) results.add(result);
      }
    }

    return results;
  }

  /// Search books by series name.
  List<LlllBookResult> searchBySeries(String series, {int limit = 50}) {
    _ensureLoaded();
    if (_books == null) return [];

    final lowerSeries = series.toLowerCase();
    final results = <LlllBookResult>[];

    for (final entry in _books!.entries) {
      if (results.length >= limit) break;
      final s = (entry.value['series'] as String? ?? '').toLowerCase();
      if (s.contains(lowerSeries)) {
        final result = _getResult(entry.key);
        if (result != null) results.add(result);
      }
    }

    return results;
  }

  /// Get all unique series names in the database.
  List<String> getAllSeries() {
    _ensureLoaded();
    if (_books == null) return [];

    final seriesSet = <String>{};
    for (final book in _books!.values) {
      final s = book['series'] as String?;
      if (s != null && s.isNotEmpty) seriesSet.add(s);
    }

    return seriesSet.toList()..sort();
  }

  /// Get all books for a given reading stage.
  List<LlllBookResult> getBooksByStage(String stage) {
    _ensureLoaded();
    if (_books == null) return [];

    final results = <LlllBookResult>[];
    for (final entry in _books!.entries) {
      if (entry.value['readingStage'] == stage) {
        final result = _getResult(entry.key);
        if (result != null) results.add(result);
      }
    }
    return results;
  }

  /// Convert a lookup result to a [BookModel] for use with existing services.
  BookModel toBookModel(LlllBookResult result) {
    return BookModel(
      id: result.productCode,
      title: result.title,
      isbn: result.isbn,
      coverImageUrl: result.coverImageUrl,
      publisher: result.brand,
      readingLevel: result.readingStage,
      tags: [
        if (result.series != null) result.series!,
        if (result.productType != null) result.productType!,
      ],
      genres: [
        if (result.series != null) result.series!,
        'phonics',
        'literacy',
      ],
      createdAt: DateTime.now(),
      metadata: {
        'productCode': result.productCode,
        'shopifyHandle': result.shopifyHandle,
        'source': 'llll_local_db',
      },
    );
  }

  // -- Private helpers --

  LlllBookResult? _getResult(String productCode) {
    final book = _books?[productCode];
    if (book == null) return null;

    return LlllBookResult(
      productCode: book['productCode'] as String? ?? productCode,
      title: book['title'] as String? ?? '',
      brand: book['brand'] as String? ?? '',
      isbn: book['isbn'] as String?,
      barcodeRaw: book['barcodeRaw'] as String?,
      coverImageUrl: book['coverImageUrl'] as String?,
      series: book['series'] as String?,
      productType: book['productType'] as String?,
      readingStage: book['readingStage'] as String?,
      shopifyHandle: book['shopifyHandle'] as String?,
    );
  }

  String? _normaliseIsbn(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length == 10 || cleaned.length == 13) return cleaned;
    return null;
  }

  void _ensureLoaded() {
    if (!_isLoaded) {
      throw StateError(
        'LlllBookDatabase not loaded. Call load() before using lookups.',
      );
    }
  }
}

/// Result of a book lookup from the local LLLL database.
class LlllBookResult {
  final String productCode;
  final String title;
  final String brand;
  final String? isbn;
  final String? barcodeRaw;
  final String? coverImageUrl;
  final String? series;
  final String? productType;
  final String? readingStage;
  final String? shopifyHandle;

  const LlllBookResult({
    required this.productCode,
    required this.title,
    required this.brand,
    this.isbn,
    this.barcodeRaw,
    this.coverImageUrl,
    this.series,
    this.productType,
    this.readingStage,
    this.shopifyHandle,
  });

  @override
  String toString() => 'LlllBookResult($productCode: $title)';
}
