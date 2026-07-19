import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'access_provider.dart';
import 'active_child_provider.dart' show firestoreProvider;
import '../models/comprehension_eval_model.dart';
import 'student_detail_providers.dart';

/// Whether AI comprehension evaluation is visible for [schoolId].
///
/// FAIL-CLOSED on BOTH sides, including loading/error states — deliberately
/// the opposite of the recording/messaging gate helpers. This is a paid,
/// privacy-sensitive feature: a transient null must hide it, never show it.
/// Firestore rules + the server-side worker gates are the hard backstop.
final aiEvaluationEnabledProvider =
    Provider.family<bool, String>((ref, schoolId) {
  if (schoolId.isEmpty) return false;
  final platformEnabled = ref.watch(platformAiEvaluationEnabledProvider).when(
        data: (enabled) => enabled,
        loading: () => false,
        error: (_, __) => false,
      );
  if (!platformEnabled) return false;
  return ref.watch(schoolByIdProvider(schoolId)).when(
        data: (school) => school?.aiEvaluationEnabled ?? false,
        loading: () => false,
        error: (_, __) => false,
      );
});

/// Platform kill switch stream — `platformConfig/aiEvaluation`. A missing
/// doc or malformed value means OFF.
final platformAiEvaluationEnabledProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection('platformConfig')
      .doc('aiEvaluation')
      .snapshots()
      .map((doc) => doc.data()?['enabled'] == true);
});

CollectionReference<Map<String, dynamic>> _evals(Ref ref, String schoolId) {
  return ref
      .watch(firestoreProvider)
      .collection('schools')
      .doc(schoolId)
      .collection('comprehensionEvals');
}

/// Latest evaluations for one student. ALWAYS filters classId + studentId —
/// teacher `list` rules prove against the query, and a query missing
/// classId is denied outright (the provability trap).
final studentEvalsProvider = StreamProvider.autoDispose
    .family<List<ComprehensionEvalModel>, StudentDetailLookup>((ref, lookup) {
  return _evals(ref, lookup.schoolId)
      .where('classId', isEqualTo: lookup.classId)
      .where('studentId', isEqualTo: lookup.studentId)
      .orderBy('logDate', descending: true)
      .limit(10)
      .snapshots()
      .map((snap) => snap.docs
          .map(ComprehensionEvalModel.fromFirestore)
          .toList(growable: false));
});

/// Family key for class-wide eval queries.
class ClassEvalsLookup {
  final String schoolId;
  final String classId;

  const ClassEvalsLookup({required this.schoolId, required this.classId});

  @override
  bool operator ==(Object other) =>
      other is ClassEvalsLookup &&
      other.schoolId == schoolId &&
      other.classId == classId;

  @override
  int get hashCode => Object.hash(schoolId, classId);
}

/// Class-wide evaluation stream for the review screen (newest first).
/// Filtering by level band / flags / date range happens client-side over
/// this window, mirroring the reading-history screen's approach.
final classEvalsProvider = StreamProvider.autoDispose
    .family<List<ComprehensionEvalModel>, ClassEvalsLookup>((ref, lookup) {
  return _evals(ref, lookup.schoolId)
      .where('classId', isEqualTo: lookup.classId)
      .orderBy('evaluatedAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs
          .map(ComprehensionEvalModel.fromFirestore)
          .toList(growable: false));
});

/// Student names for eval rows (id -> display name), one subscription per
/// class. Teachers already read their class roster elsewhere; this reuses
/// the same class-scoped access shape.
final classStudentNamesProvider = StreamProvider.autoDispose
    .family<Map<String, String>, ClassEvalsLookup>((ref, lookup) {
  return ref
      .watch(firestoreProvider)
      .collection('schools')
      .doc(lookup.schoolId)
      .collection('students')
      .where('classId', isEqualTo: lookup.classId)
      .snapshots()
      .map((snap) {
    final names = <String, String>{};
    for (final doc in snap.docs) {
      final name = doc.data()['name'];
      if (name is String && name.isNotEmpty) names[doc.id] = name;
    }
    return names;
  });
});
