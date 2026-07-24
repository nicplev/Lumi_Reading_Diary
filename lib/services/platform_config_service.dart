import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads platform-wide feature flags written by the Lumi super-admin portal
/// to `platformConfig/{flagId}`.
///
/// A missing doc or failed read counts as disabled. Child voice recordings are
/// privacy-sensitive, so the UI should agree with the callable's fail-closed
/// platform gate instead of exposing an affordance it cannot safely fulfil.
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
      final enabled = doc.data()?['enabled'] == true;
      _cachedComprehensionEnabled = enabled;
      _cachedAt = DateTime.now();
      return enabled;
    } catch (_) {
      return _cachedComprehensionEnabled ?? false;
    }
  }

  static bool? _cachedBackdatingEnabled;
  static DateTime? _cachedBackdatingAt;

  /// D1 kill-switch for parent Yesterday backdating
  /// (`platformConfig/parentBackdating`). House convention for this flag:
  /// a MISSING doc means ENABLED — it ships on for first-round school
  /// testing and the super-admin Operations toggle can turn it off without
  /// an app release, based on real evidence.
  Future<bool> isParentBackdatingEnabled() async {
    final cachedAt = _cachedBackdatingAt;
    if (_cachedBackdatingEnabled != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _cachedBackdatingEnabled!;
    }
    try {
      final doc = await _firestore
          .collection('platformConfig')
          .doc('parentBackdating')
          .get();
      final enabled = !doc.exists || doc.data()?['enabled'] != false;
      _cachedBackdatingEnabled = enabled;
      _cachedBackdatingAt = DateTime.now();
      return enabled;
    } catch (_) {
      return _cachedBackdatingEnabled ?? true;
    }
  }

  /// Test hook: clears the in-memory flag cache.
  static void debugResetCache() {
    _cachedComprehensionEnabled = null;
    _cachedAt = null;
    _cachedBackdatingEnabled = null;
    _cachedBackdatingAt = null;
  }
}
