import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local, per-teacher kiosk exit PIN.
///
/// Optional: when set, leaving the classroom kiosk requires the PIN, so a
/// student can't tap Exit and land in the teacher's full account. Stored in
/// the platform keychain/keystore (never Firestore) because it only guards
/// the kiosk on this device — signing out always remains the recovery path
/// for a forgotten PIN.
class KioskPinService {
  KioskPinService._();
  static final KioskPinService instance = KioskPinService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  String _pinKey(String teacherId) => 'kiosk_exit_pin_$teacherId';
  String _offeredKey(String teacherId) => 'kiosk_pin_offered_$teacherId';

  /// The stored PIN, or null when none is set (or storage is unavailable).
  Future<String?> getPin(String teacherId) async {
    if (teacherId.isEmpty) return null;
    try {
      final value = await _storage.read(key: _pinKey(teacherId));
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      // Secure storage can fail on odd device states — treat as "no PIN"
      // rather than locking the teacher in or out.
      return null;
    }
  }

  Future<bool> hasPin(String teacherId) async =>
      (await getPin(teacherId)) != null;

  Future<void> setPin(String teacherId, String pin) async {
    if (teacherId.isEmpty || pin.isEmpty) return;
    try {
      await _storage.write(key: _pinKey(teacherId), value: pin);
    } catch (_) {
      // Best-effort: a failed write simply leaves the kiosk PIN-less.
    }
  }

  Future<void> clearPin(String teacherId) async {
    if (teacherId.isEmpty) return;
    try {
      await _storage.delete(key: _pinKey(teacherId));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Whether the one-time "set an exit PIN?" offer has already been shown.
  Future<bool> wasOffered(String teacherId) async {
    if (teacherId.isEmpty) return true;
    try {
      return await _storage.read(key: _offeredKey(teacherId)) == '1';
    } catch (_) {
      return true; // On storage failure, don't nag.
    }
  }

  Future<void> markOffered(String teacherId) async {
    if (teacherId.isEmpty) return;
    try {
      await _storage.write(key: _offeredKey(teacherId), value: '1');
    } catch (_) {
      // Best-effort.
    }
  }
}
