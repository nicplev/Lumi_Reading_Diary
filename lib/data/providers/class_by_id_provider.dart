import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/class_model.dart';
import '../../services/firebase_service.dart';

typedef ClassLookup = ({String schoolId, String classId});

/// Resolves a single [ClassModel] from `schools/{schoolId}/classes/{classId}`.
/// Used by teacher routes to hydrate the class when an in-app caller didn't
/// pass it via `extra` (e.g. cold-start deep link).
final classByIdProvider =
    FutureProvider.family<ClassModel?, ClassLookup>((ref, key) async {
  final firestore = ref.watch(firebaseServiceProvider).firestore;
  final doc = await firestore
      .collection('schools')
      .doc(key.schoolId)
      .collection('classes')
      .doc(key.classId)
      .get();
  if (!doc.exists) return null;
  return ClassModel.fromFirestore(doc);
});
