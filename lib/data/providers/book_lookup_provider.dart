import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/book_lookup_service.dart';

/// Singleton provider for the book lookup service
/// (Community Books → Firestore cache → Google Books → Open Library).
final bookLookupServiceProvider = Provider<BookLookupService>((ref) {
  return BookLookupService();
});
