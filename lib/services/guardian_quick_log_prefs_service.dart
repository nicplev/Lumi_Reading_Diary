import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';

/// Guardian×child quick-log preferences (plan §6.4), stored at
/// `schools/{schoolId}/parents/{parentId}.preferences.quickLog.{studentId}`.
/// Keyed by guardian so separated households naturally diverge; never
/// changed silently — only the explicit "make usual?" prompt or a settings
/// action writes here.
class GuardianQuickLogPrefsService {
  GuardianQuickLogPrefsService._();

  static final GuardianQuickLogPrefsService instance =
      GuardianQuickLogPrefsService._();

  /// Divergence streak needed before the app may ASK to update the usual
  /// duration (decision D5).
  static const int usualPromptThreshold = 3;

  DocumentReference<Map<String, dynamic>> _parentRef(
          String schoolId, String parentId) =>
      FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('parents')
          .doc(parentId);

  Future<void> setUsualMinutes({
    required String schoolId,
    required String parentId,
    required String studentId,
    required int minutes,
  }) async {
    await _parentRef(schoolId, parentId).update({
      'preferences.quickLog.$studentId.usualMinutes': minutes,
      'preferences.quickLog.$studentId.divergenceStreak': 0,
      'preferences.quickLog.$studentId.updatedAt':
          FieldValue.serverTimestamp(),
    });
  }

  Future<void> setPinnedBook({
    required String schoolId,
    required String parentId,
    required String studentId,
    required String? title,
  }) async {
    await _parentRef(schoolId, parentId).update({
      'preferences.quickLog.$studentId.pinnedBookTitle':
          (title == null || title.trim().isEmpty)
              ? FieldValue.delete()
              : title.trim(),
      'preferences.quickLog.$studentId.updatedAt':
          FieldValue.serverTimestamp(),
    });
  }

  /// Records one saved session's minutes against the guardian's usual and
  /// returns true when the app should ASK "Make [minutes] the usual?" —
  /// after [usualPromptThreshold] consecutive sessions at the same
  /// divergent value. Best-effort: failures never block a save.
  Future<bool> recordSessionMinutes({
    required String schoolId,
    required String parentId,
    required String studentId,
    required int minutes,
    required int currentUsual,
  }) async {
    try {
      if (minutes == currentUsual) {
        await _parentRef(schoolId, parentId).update({
          'preferences.quickLog.$studentId.divergenceStreak': 0,
        });
        return false;
      }
      final ref = _parentRef(schoolId, parentId);
      final snap = await ref.get();
      final prefs = (snap.data()?['preferences'] as Map?)?['quickLog'];
      final child = prefs is Map ? prefs[studentId] : null;
      final lastValue =
          child is Map ? (child['divergenceValue'] as num?)?.toInt() : null;
      final streak =
          child is Map ? (child['divergenceStreak'] as num?)?.toInt() ?? 0 : 0;
      final nextStreak = lastValue == minutes ? streak + 1 : 1;
      await ref.update({
        'preferences.quickLog.$studentId.divergenceValue': minutes,
        'preferences.quickLog.$studentId.divergenceStreak': nextStreak,
      });
      return nextStreak >= usualPromptThreshold;
    } catch (e) {
      debugPrint('recordSessionMinutes failed: $e');
      return false;
    }
  }
}
