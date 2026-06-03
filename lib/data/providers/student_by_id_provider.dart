import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/student_model.dart';
import '../../services/firebase_service.dart';

typedef StudentLookup = ({String schoolId, String studentId});

/// Resolves a single [StudentModel] from
/// `schools/{schoolId}/students/{studentId}`. Used by teacher routes to
/// hydrate the student when an in-app caller didn't pass it via `extra`
/// (e.g. cold-start deep link).
final studentByIdProvider =
    FutureProvider.family<StudentModel?, StudentLookup>((ref, key) async {
  final firestore = ref.watch(firebaseServiceProvider).firestore;
  final doc = await firestore
      .collection('schools')
      .doc(key.schoolId)
      .collection('students')
      .doc(key.studentId)
      .get();
  if (!doc.exists) return null;
  return StudentModel.fromFirestore(doc);
});
