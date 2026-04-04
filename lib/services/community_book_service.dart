import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/models/book_model.dart';

/// Service for the global Community Book Database.
///
/// This database is shared across all schools — any teacher or admin can
/// contribute books by scanning covers and ISBNs. Documents are keyed by
/// normalized ISBN-13 for O(1) lookups.
class CommunityBookService {
  CommunityBookService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  static const String _collection = 'community_books';
  static const String _coverStoragePath = 'community_books/covers';
  static const int _maxCoverWidth = 600;
  static const int _maxCoverHeight = 800;
  static const int _jpegQuality = 85;

  CollectionReference<Map<String, dynamic>> get _booksRef =>
      _firestore.collection(_collection);

  // ── Lookups ────────────────────────────────────────────────────────

  /// Look up a community book by normalized ISBN-13. Returns null if not found.
  Future<BookModel?> lookupByIsbn(String isbn) async {
    try {
      final doc = await _booksRef.doc(isbn).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null ||
          data['title'] == null ||
          (data['title'] as String).isEmpty) {
        return null;
      }
      return BookModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('CommunityBookService.lookupByIsbn failed: $e');
      return null;
    }
  }

  /// Check if a community book already exists for this ISBN.
  Future<bool> exists(String isbn) async {
    try {
      final doc = await _booksRef.doc(isbn).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Search community books by title substring (case-insensitive).
  Future<List<BookModel>> searchByTitle(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    final normalized = query.trim().toLowerCase();

    try {
      // Firestore does not support LIKE queries, so we use a range query on
      // the normalized title field. This finds titles that START with the query.
      final snapshot = await _booksRef
          .where('titleNormalized', isGreaterThanOrEqualTo: normalized)
          .where('titleNormalized', isLessThanOrEqualTo: '$normalized\uf8ff')
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => BookModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('CommunityBookService.searchByTitle failed: $e');
      return [];
    }
  }

  /// Stream of recently added community books.
  Stream<List<BookModel>> recentBooksStream({int limit = 50}) {
    return _booksRef
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => BookModel.fromFirestore(doc)).toList());
  }

  // ── Write Operations ──────────────────────────────────────────────

  /// Add or merge a book into the community database.
  ///
  /// Uses Firestore `set` with merge semantics so that if two teachers scan
  /// the same ISBN, the second enriches rather than overwrites the record.
  /// The [contributedBy] field is only set on initial creation.
  Future<void> addBook({
    required String isbn,
    required String title,
    required String contributorId,
    required String contributorSchoolId,
    String? contributorName,
    String? author,
    String? coverImageUrl,
    String? coverStoragePath,
    String? description,
    List<String>? genres,
    String? readingLevel,
    int? pageCount,
    String? publisher,
    List<String>? tags,
    String source = 'teacher_scan',
    Map<String, dynamic>? metadata,
  }) async {
    final now = Timestamp.now();
    final titleNormalized = title.trim().toLowerCase();

    final docRef = _booksRef.doc(isbn);
    final existingDoc = await docRef.get();

    if (existingDoc.exists) {
      // Merge: update metadata fields but preserve original contributor.
      final updateData = <String, dynamic>{
        'updatedAt': now,
      };
      if (title.isNotEmpty) updateData['title'] = title;
      if (title.isNotEmpty) updateData['titleNormalized'] = titleNormalized;
      if (author != null) updateData['author'] = author;
      if (description != null) updateData['description'] = description;
      if (readingLevel != null) updateData['readingLevel'] = readingLevel;
      if (pageCount != null) updateData['pageCount'] = pageCount;
      if (publisher != null) updateData['publisher'] = publisher;
      if (genres != null && genres.isNotEmpty) updateData['genres'] = genres;
      if (tags != null && tags.isNotEmpty) updateData['tags'] = tags;
      if (metadata != null) updateData['metadata'] = metadata;

      // Only overwrite cover if new one is from a camera scan (higher quality).
      if (coverImageUrl != null &&
          (metadata?['coverSource'] == 'camera_scan' ||
              existingDoc.data()?['coverImageUrl'] == null)) {
        updateData['coverImageUrl'] = coverImageUrl;
        if (coverStoragePath != null) {
          updateData['coverStoragePath'] = coverStoragePath;
        }
      }

      // Preserve original contributedBy — security rules enforce this.
      updateData['contributedBy'] =
          existingDoc.data()!['contributedBy'] ?? contributorId;
      updateData['contributedBySchoolId'] =
          existingDoc.data()!['contributedBySchoolId'] ??
              contributorSchoolId;

      await docRef.update(updateData);
    } else {
      // Create new document.
      await docRef.set({
        'title': title,
        'titleNormalized': titleNormalized,
        'author': author,
        'isbn': isbn,
        'coverImageUrl': coverImageUrl,
        'coverStoragePath': coverStoragePath,
        'description': description,
        'genres': genres ?? [],
        'readingLevel': readingLevel,
        'pageCount': pageCount,
        'publisher': publisher,
        'tags': tags ?? [],
        'source': source,
        'contributedBy': contributorId,
        'contributedBySchoolId': contributorSchoolId,
        'contributedByName': contributorName,
        'createdAt': now,
        'updatedAt': now,
        'metadata': metadata ?? {},
      });
    }
  }

  // ── Cover Image Upload ────────────────────────────────────────────

  /// Resize, compress, and upload a cover image to Firebase Storage.
  /// Returns the download URL on success, null on failure.
  Future<String?> uploadCoverImage({
    required String isbn,
    required File imageFile,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final processed = await compute(_processImage, bytes);
      if (processed == null) return null;

      final storagePath = '$_coverStoragePath/$isbn.jpg';
      final ref = _storage.ref(storagePath);

      await ref.putData(
        processed,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('CommunityBookService.uploadCoverImage failed: $e');
      return null;
    }
  }

  /// Process image in an isolate: resize and compress to JPEG.
  static Uint8List? _processImage(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    img.Image resized;
    if (image.width > _maxCoverWidth || image.height > _maxCoverHeight) {
      resized = img.copyResize(
        image,
        width: image.width > image.height ? null : _maxCoverWidth,
        height: image.width > image.height ? _maxCoverHeight : null,
        maintainAspect: true,
      );
    } else {
      resized = image;
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
  }

  /// Get the storage path for a cover image (for deletion reference).
  String coverStoragePath(String isbn) => '$_coverStoragePath/$isbn.jpg';

  // ── Deletion Requests (Future) ────────────────────────────────────

  /// Submit a deletion request for a community book.
  /// The request is stored in a subcollection and reviewed by the super admin.
  Future<void> requestDeletion({
    required String isbn,
    required String reason,
    required String requestedBy,
    required String requestedByName,
    required String schoolId,
    String? bookTitle,
    String? bookAuthor,
  }) async {
    await _booksRef.doc(isbn).collection('deletionRequests').add({
      'requestedBy': requestedBy,
      'requestedByName': requestedByName,
      'schoolId': schoolId,
      'reason': reason,
      'status': 'pending',
      'createdAt': Timestamp.now(),
      'resolvedAt': null,
      'resolvedBy': null,
      if (bookTitle != null) 'bookTitle': bookTitle,
      if (bookAuthor != null) 'bookAuthor': bookAuthor,
    });
  }
}
