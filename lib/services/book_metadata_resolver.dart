import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/book_model.dart';
import 'book_lookup_service.dart';

/// Resolves book metadata (cover, author, etc.) for a list of title strings.
///
/// Maintains an in-memory cache and deduplicates concurrent requests.
/// Designed to be used by the bookshelf UI to progressively resolve metadata.
class BookMetadataResolver extends ChangeNotifier {
  BookMetadataResolver({
    required BookLookupService lookupService,
    required String schoolId,
    required String actorId,
  })  : _lookupService = lookupService,
        _schoolId = schoolId,
        _actorId = actorId;

  final BookLookupService _lookupService;
  final String _schoolId;
  final String _actorId;

  /// Resolved metadata keyed by normalized title.
  final Map<String, BookModel?> _cache = {};

  /// In-flight requests to avoid duplicate API calls.
  final Map<String, Completer<BookModel?>> _inFlight = {};

  /// Max concurrent API requests to avoid rate limiting.
  static const _maxConcurrent = 3;
  int _activeCalls = 0;
  final List<_QueuedRequest> _queue = [];

  /// Whether a given title has been resolved (found or not found).
  bool isResolved(String title) {
    final key = BookLookupService.normalizeTitle(title);
    return _cache.containsKey(key);
  }

  /// Get cached metadata for a title. Returns null if not resolved or not found.
  BookModel? getCached(String title) {
    final key = BookLookupService.normalizeTitle(title);
    return _cache[key];
  }

  /// Resolve metadata for a single title. Returns the BookModel if found.
  /// Uses in-memory cache, then delegates to BookLookupService.lookupByTitle.
  Future<BookModel?> resolve(String title) async {
    final key = BookLookupService.normalizeTitle(title);
    if (key.isEmpty) return null;

    // 1. In-memory cache hit
    if (_cache.containsKey(key)) return _cache[key];

    // 2. Already in-flight — wait for existing request
    if (_inFlight.containsKey(key)) return _inFlight[key]!.future;

    // 3. Start new request (possibly queued)
    final completer = Completer<BookModel?>();
    _inFlight[key] = completer;

    if (_activeCalls < _maxConcurrent) {
      _executeResolve(key, title, completer);
    } else {
      _queue.add(_QueuedRequest(key: key, title: title, completer: completer));
    }

    return completer.future;
  }

  /// Resolve metadata for multiple titles. Notifies listeners as each resolves.
  Future<void> resolveAll(List<String> titles) async {
    final uniqueTitles = titles
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .where((t) => !isResolved(t))
        .toList();

    // Fire all resolutions — they self-throttle via _maxConcurrent
    await Future.wait(uniqueTitles.map((t) => resolve(t)));
  }

  void _executeResolve(
    String key,
    String title,
    Completer<BookModel?> completer,
  ) async {
    _activeCalls++;
    try {
      final result = await _lookupService.lookupByTitle(
        title: title,
        schoolId: _schoolId,
        actorId: _actorId,
      );
      _cache[key] = result;
      completer.complete(result);
      notifyListeners();
    } catch (e) {
      debugPrint('BookMetadataResolver: Failed to resolve "$title": $e');
      _cache[key] = null;
      completer.complete(null);
      notifyListeners();
    } finally {
      _activeCalls--;
      _inFlight.remove(key);
      _processQueue();
    }
  }

  void _processQueue() {
    while (_queue.isNotEmpty && _activeCalls < _maxConcurrent) {
      final next = _queue.removeAt(0);
      // Skip if already resolved while queued
      if (_cache.containsKey(next.key)) {
        next.completer.complete(_cache[next.key]);
        continue;
      }
      _executeResolve(next.key, next.title, next.completer);
    }
  }
}

class _QueuedRequest {
  final String key;
  final String title;
  final Completer<BookModel?> completer;

  _QueuedRequest({
    required this.key,
    required this.title,
    required this.completer,
  });
}
