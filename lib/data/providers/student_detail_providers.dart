import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_child_provider.dart' show firestoreProvider;

/// Composite family key for the teacher student-detail screen's streams,
/// following the repo's `*Lookup` convention (see StudentLookup/ClassLookup).
/// All three ids participate in equality so a cached stream can never be
/// served across a school or student switch.
class StudentDetailLookup {
  final String schoolId;
  final String classId;
  final String studentId;

  const StudentDetailLookup({
    required this.schoolId,
    required this.classId,
    required this.studentId,
  });

  @override
  bool operator ==(Object other) =>
      other is StudentDetailLookup &&
      other.schoolId == schoolId &&
      other.classId == classId &&
      other.studentId == studentId;

  @override
  int get hashCode => Object.hash(schoolId, classId, studentId);
}

CollectionReference<Map<String, dynamic>> _readingLogs(
  Ref ref,
  StudentDetailLookup lookup,
) {
  return ref
      .watch(firestoreProvider)
      .collection('schools')
      .doc(lookup.schoolId)
      .collection('readingLogs');
}

/// Feelings-tracker source: up to ~12 months of logs so the tracker can cover
/// its widest (all-time) window. The date floor is computed once per
/// subscription (autoDispose → fresh on next screen visit), which keeps the
/// underlying Firestore listener stable across rebuilds.
final studentFeelingLogsProvider = StreamProvider.autoDispose
    .family<QuerySnapshot<Map<String, dynamic>>, StudentDetailLookup>(
        (ref, lookup) {
  final floor = DateTime.now().subtract(const Duration(days: 366));
  return _readingLogs(ref, lookup)
      .where('classId', isEqualTo: lookup.classId)
      .where('studentId', isEqualTo: lookup.studentId)
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(floor))
      .orderBy('date', descending: true)
      .limit(400)
      .snapshots();
});

/// Recent Reading list source (20 most recent logs).
final studentRecentLogsProvider = StreamProvider.autoDispose
    .family<QuerySnapshot<Map<String, dynamic>>, StudentDetailLookup>(
        (ref, lookup) {
  return _readingLogs(ref, lookup)
      .where('classId', isEqualTo: lookup.classId)
      .where('studentId', isEqualTo: lookup.studentId)
      .orderBy('date', descending: true)
      .limit(20)
      .snapshots();
});

/// Latest-parent-comment source (newest 50 logs are scanned for a comment).
final studentCommentLogsProvider = StreamProvider.autoDispose
    .family<QuerySnapshot<Map<String, dynamic>>, StudentDetailLookup>(
        (ref, lookup) {
  return _readingLogs(ref, lookup)
      .where('classId', isEqualTo: lookup.classId)
      .where('studentId', isEqualTo: lookup.studentId)
      .orderBy('date', descending: true)
      .limit(50)
      .snapshots();
});

/// Active allocations for the student's class (assigned-books section).
final studentAllocationsProvider = StreamProvider.autoDispose
    .family<QuerySnapshot<Map<String, dynamic>>, StudentDetailLookup>(
        (ref, lookup) {
  return ref
      .watch(firestoreProvider)
      .collection('schools')
      .doc(lookup.schoolId)
      .collection('allocations')
      .where('classId', isEqualTo: lookup.classId)
      .where('isActive', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .snapshots();
});

/// Reading-progress source for the assigned-books section (200 most recent
/// logs). Separate from [studentRecentLogsProvider] because the book cards
/// need a deeper window to compute per-book progress.
final allocationLogsProvider = StreamProvider.autoDispose
    .family<QuerySnapshot<Map<String, dynamic>>, StudentDetailLookup>(
        (ref, lookup) {
  return _readingLogs(ref, lookup)
      .where('classId', isEqualTo: lookup.classId)
      .where('studentId', isEqualTo: lookup.studentId)
      .orderBy('date', descending: true)
      .limit(200)
      .snapshots();
});
