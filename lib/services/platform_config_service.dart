import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads platform-wide feature flags written by the Lumi super-admin portal
/// to `platformConfig/{flagId}`.
///
/// A missing doc or a failed read counts as "enabled": the per-school
/// `settings.comprehensionRecording` toggle already defaults to off, so
/// failing open here can never force-enable the feature for a school that
/// didn't opt in. The Storage rules read the same doc server-side, so even a
/// client holding a stale "enabled" answer cannot upload audio while the
/// kill switch is off.
class PlatformConfigService {
  PlatformConfigService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static bool? _cachedComprehensionEnabled;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(minutes: 5);

  Future<bool> isComprehensionRecordingEnabled() async {
    final cachedAt = _cachedAt;
    if (_cachedComprehensionEnabled != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _cachedComprehensionEnabled!;
    }
    try {
      final doc = await _firestore
          .collection('platformConfig')
          .doc('comprehensionRecording')
          .get();
      final enabled = (doc.data()?['enabled'] as bool?) ?? true;
      _cachedComprehensionEnabled = enabled;
      _cachedAt = DateTime.now();
      return enabled;
    } catch (_) {
      return _cachedComprehensionEnabled ?? true;
    }
  }

  /// Test hook: clears the in-memory flag cache.
  static void debugResetCache() {
    _cachedComprehensionEnabled = null;
    _cachedAt = null;
  }
}
