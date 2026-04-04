import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/models/book_model.dart';
import '../data/models/cached_book_entry.dart';
import 'persistent_image_cache_service.dart';

/// Persistent on-device cache of books a teacher has scanned via ISBN.
///
/// Backed by a Hive box, keyed per teacher+school+isbn so repeat scans
/// resolve from disk before any Firestore or external API call.
///
/// This service is intentionally **separate from [OfflineService]** because
/// it has a different lifecycle: the cache persists across logout for
/// term-long reuse. Isolation is enforced by teacher+school scoping.
class TeacherDeviceBookCacheService {
  TeacherDeviceBookCacheService._();

  static TeacherDeviceBookCacheService? _instance;
  static TeacherDeviceBookCacheService get instance =>
      _instance ??= TeacherDeviceBookCacheService._();

  /// Replace singleton for testing.
  @visibleForTesting
  static set instance(TeacherDeviceBookCacheService value) =>
      _instance = value;

  static const _boxName = 'teacher_isbn_scan_cache_v1';
  static const _maxEntriesPerTeacher = 500;

  Box<Map>? _box;
  bool _initialized = false;

  /// Whether the service is available. Returns false if initialization
  /// failed (e.g. corrupted Hive file).
  bool get isAvailable => _initialized && _box != null;

  /// Open the Hive box. Call once at app startup.
  /// If this fails, the service degrades gracefully — all lookups return null
  /// and all writes are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<Map>(_boxName);
      _initialized = true;
    } catch (e) {
      debugPrint('TeacherDeviceBookCacheService: initialization failed: $e');
      // Service remains unavailable; all operations will no-op.
    }
  }

  /// Build a deterministic cache key.
  static String _key(String teacherId, String schoolId, String isbn) =>
      '$teacherId|$schoolId|$isbn';

  /// Parse teacher+school from a composite key (for counting/pruning).
  static String _teacherSchoolPrefix(String teacherId, String schoolId) =>
      '$teacherId|$schoolId|';

  /// Look up a book by its already-normalized ISBN. Returns null on miss.
  ///
  /// This is synchronous because Hive loads the box into memory on open.
  /// On cache hit, `lastUsedAt` is updated asynchronously for LRU tracking.
  BookModel? lookupByIsbn({
    required String teacherId,
    required String schoolId,
    required String isbn,
  }) {
    final box = _box;
    if (!isAvailable || box == null) return null;

    final key = _key(teacherId, schoolId, isbn);
    final raw = box.get(key);
    if (raw == null) return null;

    try {
      final entry = CachedBookEntry.fromMap(Map<String, dynamic>.from(raw));

      // Fire-and-forget LRU timestamp update.
      entry.lastUsedAt = DateTime.now();
      box.put(key, entry.toMap()).catchError((Object e) {
        debugPrint('TeacherDeviceBookCacheService: lastUsedAt update failed: $e');
      });

      return entry.toBookModel();
    } catch (e) {
      debugPrint('TeacherDeviceBookCacheService: failed to deserialize cache entry: $e');
      // Corrupted entry — remove it silently.
      box.delete(key).catchError((Object _) {});
      return null;
    }
  }

  /// Write a book to the cache and best-effort prewarm its cover image.
  ///
  /// Placeholder/unresolved books (title "Unrecognised Book") must NOT be
  /// passed here — callers are responsible for filtering them out so that
  /// repeated unknown ISBNs continue to retry remote resolution.
  Future<void> cacheBook({
    required String teacherId,
    required String schoolId,
    required BookModel book,
  }) async {
    final box = _box;
    if (!isAvailable || box == null) return;

    final isbn = book.isbn;
    if (isbn == null || isbn.isEmpty) return;

    final entry = CachedBookEntry.fromBookModel(
      book,
      teacherId: teacherId,
      schoolId: schoolId,
    );

    final key = _key(teacherId, schoolId, isbn);
    await box.put(key, entry.toMap());

    // Prune if over cap.
    await _pruneIfNeeded(teacherId, schoolId);

    // Best-effort cover image prewarming.
    final coverUrl = book.coverImageUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      try {
        unawaited(
          PersistentImageCacheService.instance.getCachedFilePath(coverUrl),
        );
      } catch (_) {
        // Prewarming is best-effort; swallow errors.
      }
    }
  }

  /// Remove all cached entries for a specific teacher+school pair.
  Future<void> clearForTeacher(String teacherId, String schoolId) async {
    final box = _box;
    if (!isAvailable || box == null) return;
    final prefix = _teacherSchoolPrefix(teacherId, schoolId);
    final keysToDelete =
        box.keys.where((k) => (k as String).startsWith(prefix)).toList();
    await box.deleteAll(keysToDelete);
  }

  /// Remove all cached entries (all teachers, all schools).
  Future<void> clearAll() async {
    final box = _box;
    if (!isAvailable || box == null) return;
    await box.clear();
  }

  /// Number of cached entries for a teacher+school pair.
  int countForTeacher(String teacherId, String schoolId) {
    final box = _box;
    if (!isAvailable || box == null) return 0;
    final prefix = _teacherSchoolPrefix(teacherId, schoolId);
    return box.keys.where((k) => (k as String).startsWith(prefix)).length;
  }

  /// Prune least-recently-used entries when over the per-teacher cap.
  Future<void> _pruneIfNeeded(String teacherId, String schoolId) async {
    final box = _box;
    if (box == null) return;

    final prefix = _teacherSchoolPrefix(teacherId, schoolId);
    final teacherKeys =
        box.keys.where((k) => (k as String).startsWith(prefix)).toList();

    if (teacherKeys.length <= _maxEntriesPerTeacher) return;

    // Build (key, lastUsedAt) pairs and sort ascending by lastUsedAt.
    final entries = <MapEntry<String, DateTime>>[];
    for (final key in teacherKeys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final map = Map<String, dynamic>.from(raw);
      final lastUsed =
          DateTime.tryParse(map['lastUsedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
      entries.add(MapEntry(key as String, lastUsed));
    }
    entries.sort((a, b) => a.value.compareTo(b.value));

    // Delete oldest entries to bring count back to cap.
    final toDelete = entries.length - _maxEntriesPerTeacher;
    if (toDelete <= 0) return;
    final keysToDelete = entries.take(toDelete).map((e) => e.key).toList();
    await box.deleteAll(keysToDelete);
  }
}
