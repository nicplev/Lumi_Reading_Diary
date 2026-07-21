import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reading_log_model.dart';
import 'active_child_provider.dart' show firestoreProvider;

/// Class-scoped key used by the recording inbox providers.
class ComprehensionRecordingsLookup {
  final String schoolId;
  final String classId;

  const ComprehensionRecordingsLookup({
    required this.schoolId,
    required this.classId,
  });

  @override
  bool operator ==(Object other) =>
      other is ComprehensionRecordingsLookup &&
      other.schoolId == schoolId &&
      other.classId == classId;

  @override
  int get hashCode => Object.hash(schoolId, classId);
}

CollectionReference<Map<String, dynamic>> _readingLogs(
  Ref ref,
  String schoolId,
) {
  return ref
      .watch(firestoreProvider)
      .collection('schools')
      .doc(schoolId)
      .collection('readingLogs');
}

/// Recent retained recordings for a class, newest upload first.
///
/// The screen is only allowed to watch this provider after both recording
/// feature gates have resolved to enabled. The callable playback endpoint and
/// Firestore rules independently repeat the school/class authorization.
final classComprehensionRecordingsProvider = StreamProvider.autoDispose
    .family<List<ReadingLogModel>, ComprehensionRecordingsLookup>(
        (ref, lookup) {
  if (lookup.schoolId.isEmpty || lookup.classId.isEmpty) {
    return Stream.value(const <ReadingLogModel>[]);
  }
  return _readingLogs(ref, lookup.schoolId)
      .where('classId', isEqualTo: lookup.classId)
      .where('comprehensionAudioUploaded', isEqualTo: true)
      .orderBy('comprehensionAudioUploadedAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map(ReadingLogModel.fromFirestore)
          .where((log) => log.hasComprehensionAudio)
          .toList(growable: false));
});

/// Keeps the review workflow moving even when a class has more recordings than
/// the recent 200-row archive window. Reviewed rows leave this query and are
/// automatically replaced by the next pending rows.
Stream<List<ReadingLogModel>> _pendingComprehensionRecordings(
  Ref ref,
  ComprehensionRecordingsLookup lookup,
) {
  return _readingLogs(ref, lookup.schoolId)
      .where('classId', isEqualTo: lookup.classId)
      .where('comprehensionAudioUploaded', isEqualTo: true)
      .where('comprehensionAudioReviewStatus', isEqualTo: 'pending')
      .orderBy('comprehensionAudioUploadedAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map(ReadingLogModel.fromFirestore)
          .where((log) => log.hasComprehensionAudio)
          .toList(growable: false));
}

final pendingComprehensionRecordingsProvider = StreamProvider.autoDispose
    .family<List<ReadingLogModel>, ComprehensionRecordingsLookup>(
        (ref, lookup) {
  if (lookup.schoolId.isEmpty || lookup.classId.isEmpty) {
    return Stream.value(const <ReadingLogModel>[]);
  }
  return _pendingComprehensionRecordings(ref, lookup);
});

/// Live shared to-review count for the compact classroom badge.
///
/// This intentionally derives from the inbox's filtered pending stream rather
/// than counting raw Firestore documents. Historical/incomplete upload records
/// can retain a `pending` marker without a playable audio path; the inbox
/// excludes them, so the badge must too. The value is capped for the `99+`
/// compact UI.
final unreviewedComprehensionRecordingCountProvider = StreamProvider.autoDispose
    .family<int, ComprehensionRecordingsLookup>((ref, lookup) {
  if (lookup.schoolId.isEmpty || lookup.classId.isEmpty) {
    return Stream.value(0);
  }
  return _pendingComprehensionRecordings(ref, lookup)
      .map((recordings) => recordings.length > 100 ? 100 : recordings.length);
});

/// Student display names for the recording inbox. This roster subscription is
/// intentionally part of the non-AI provider layer.
final comprehensionRecordingStudentNamesProvider = StreamProvider.autoDispose
    .family<Map<String, String>, ComprehensionRecordingsLookup>((ref, lookup) {
  if (lookup.schoolId.isEmpty || lookup.classId.isEmpty) {
    return Stream.value(const <String, String>{});
  }
  return ref
      .watch(firestoreProvider)
      .collection('schools')
      .doc(lookup.schoolId)
      .collection('students')
      .where('classId', isEqualTo: lookup.classId)
      .snapshots()
      .map((snapshot) {
    final names = <String, String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final direct = data['name'];
      final composed = [data['firstName'], data['lastName']]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(' ')
          .trim();
      final name = direct is String && direct.trim().isNotEmpty
          ? direct.trim()
          : composed;
      if (name.isNotEmpty) names[doc.id] = name;
    }
    return names;
  });
});

/// Marks the current audio generation reviewed for the whole teaching team.
///
/// A transaction makes concurrent co-teacher completion idempotent. Firestore
/// rules pin every written value to the signed-in teacher, server time, and the
/// current object generation, so this client convenience is not an authority
/// boundary.
class ComprehensionRecordingReviewService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ComprehensionRecordingReviewService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Future<void> markReviewed({
    required String schoolId,
    required String logId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('A signed-in teacher is required');
    }

    final ref = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(logId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('Recording log no longer exists');
      }
      final generation = data['comprehensionAudioObjectGeneration']?.toString();
      if (data['comprehensionAudioUploaded'] != true ||
          generation == null ||
          generation.isEmpty) {
        throw StateError('Recording is no longer available');
      }
      if (data['comprehensionAudioReviewStatus'] == 'reviewed' &&
          data['comprehensionAudioReviewedGeneration']?.toString() ==
              generation) {
        return;
      }
      transaction.update(ref, {
        'comprehensionAudioReviewStatus': 'reviewed',
        'comprehensionAudioReviewedAt': FieldValue.serverTimestamp(),
        'comprehensionAudioReviewedGeneration': generation,
      });
    });
  }

  /// Returns the current audio generation to the shared to-review queue.
  ///
  /// This is deliberately the inverse of [markReviewed], rather than a broad
  /// reading-log edit. The transaction only clears a review that belongs to
  /// the same, still-retained audio object. Firestore rules repeat those
  /// checks and restrict this write to teachers assigned to the class.
  Future<void> markToReview({
    required String schoolId,
    required String logId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('A signed-in teacher is required');
    }

    final ref = _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .doc(logId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('Recording log no longer exists');
      }
      final generation = data['comprehensionAudioObjectGeneration']?.toString();
      if (data['comprehensionAudioUploaded'] != true ||
          generation == null ||
          generation.isEmpty) {
        throw StateError('Recording is no longer available');
      }

      // A missing/stale status is already in the to-review queue. Keeping this
      // a no-op avoids writing a reset for an audio replacement that another
      // teacher has just uploaded.
      if (data['comprehensionAudioReviewStatus'] != 'reviewed' ||
          data['comprehensionAudioReviewedGeneration']?.toString() !=
              generation) {
        return;
      }

      transaction.update(ref, {
        'comprehensionAudioReviewStatus': 'pending',
        'comprehensionAudioReviewedAt': FieldValue.delete(),
        'comprehensionAudioReviewedGeneration': FieldValue.delete(),
      });
    });
  }
}
