import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/book_lookup_service.dart';
import '../../services/llll_book_database.dart';

/// Singleton provider for the local LLLL book database.
final llllBookDatabaseProvider = Provider<LlllBookDatabase>((ref) {
  return LlllBookDatabase();
});

/// Singleton provider for the book lookup service (LLLL + Google Books + Open Library).
final bookLookupServiceProvider = Provider<BookLookupService>((ref) {
  final llllDb = ref.watch(llllBookDatabaseProvider);
  return BookLookupService(llllDatabase: llllDb);
});

/// FutureProvider that ensures the LLLL book database is loaded.
///
/// Watch this in widgets that depend on the book database being ready:
///   final asyncDb = ref.watch(bookDatabaseReadyProvider);
///   asyncDb.when(
///     data: (_) => /* database ready, can scan barcodes */,
///     loading: () => CircularProgressIndicator(),
///     error: (e, _) => Text('Failed to load book database'),
///   );
final bookDatabaseReadyProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(bookLookupServiceProvider);
  await service.loadLocalDatabase();
});
