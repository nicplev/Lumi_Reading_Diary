import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Which auth flow generated the pending verification. The recovery
/// screen reads this to know how to finalise after the SMS code is
/// entered.
enum PhoneVerificationMode {
  /// Parent registering without an email (phone is the primary credential).
  /// `contextJson` carries the link-code + name + relationship so the
  /// recovery screen can write the parent doc + index + child link after
  /// `signInWithCredential` returns.
  phonePrimaryRegistration,

  /// Existing phone-only parent signing in. `contextJson` is empty — the
  /// recovery screen looks up the school via `lookupSchoolByPhone`.
  phoneLogin,

  /// Teacher signing up with email + password, enrolling the phone as a
  /// second factor. The email/password account already exists and is signed
  /// in (the session survives the teardown / relaunch), so recovery links the
  /// verified phone + enrols server-side rather than signing in. `contextJson`
  /// carries schoolId / email / fullName / codeId so the recovery screen can
  /// write the teacher doc + index after enrolment.
  teacherMfaEnrollment,

  /// Parent signing up with email + password, enrolling the phone as a second
  /// factor. Like [teacherMfaEnrollment] but the recovery tail writes the
  /// parent doc + indexes + links the student. `contextJson` carries
  /// schoolId / linkCode / email / fullName / relationshipLabel.
  parentMfaEnrollment,
}

/// Snapshot of an in-flight Firebase phone verification that needs to
/// outlive the calling widget. Persisted to Hive so the SMS step can be
/// completed even if iOS popped the modal route during the reCAPTCHA
/// Safari handoff (the bug this service exists to defend against), or
/// even across a full app relaunch.
@immutable
class PendingPhoneVerification {
  const PendingPhoneVerification({
    required this.verificationId,
    required this.phoneE164,
    required this.mode,
    required this.contextJson,
    required this.savedAt,
    this.resendToken,
  });

  final String verificationId;
  final int? resendToken;
  final String phoneE164;
  final PhoneVerificationMode mode;
  final Map<String, dynamic> contextJson;
  final DateTime savedAt;

  Map<String, dynamic> toMap() => {
        'verificationId': verificationId,
        'resendToken': resendToken,
        'phoneE164': phoneE164,
        'mode': mode.name,
        'contextJson': contextJson,
        'savedAt': savedAt.toIso8601String(),
      };

  static PendingPhoneVerification? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    try {
      final modeName = raw['mode'] as String?;
      final mode = PhoneVerificationMode.values
          .firstWhere((m) => m.name == modeName, orElse: () => PhoneVerificationMode.phoneLogin);
      return PendingPhoneVerification(
        verificationId: raw['verificationId'] as String,
        resendToken: raw['resendToken'] as int?,
        phoneE164: raw['phoneE164'] as String,
        mode: mode,
        contextJson: Map<String, dynamic>.from(
          (raw['contextJson'] as Map?) ?? const {},
        ),
        savedAt: DateTime.parse(raw['savedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Singleton that owns the "in-flight phone verification" record. Phone
/// auth on iOS opens `SFSafariViewController` for reCAPTCHA when silent
/// push isn't available; that presentation can knock the underlying
/// Flutter modal route off the stack, and Firebase's `codeSent` callback
/// then fires with a valid verification ID that nothing is listening for.
/// We persist the verification ID + flow context inside the `codeSent`
/// callback so the recovery screen can pick it up — warm-resumed via
/// [onRecoveryNeeded] if the modal was popped, or cold-started via the
/// splash screen's [peek] on the next launch.
class PhoneVerificationRecoveryService {
  PhoneVerificationRecoveryService._();

  static final PhoneVerificationRecoveryService instance =
      PhoneVerificationRecoveryService._();

  static const String _boxName = 'phone_verification_recovery';
  static const String _recordKey = 'pending';

  /// Secure-storage key under which the base64 Hive AES key lives (Keychain
  /// on iOS / Keystore-backed EncryptedSharedPreferences on Android).
  static const String _cipherKeyName = 'phone_verification_recovery_key';

  /// Records older than this are treated as stale and cleared on read.
  /// Firebase verification IDs typically expire after ~60 seconds; we
  /// give a generous buffer for slow networks and OS pauses.
  static const Duration _maxAge = Duration(minutes: 5);

  Box<dynamic>? _box;
  bool _initialized = false;

  /// Called when [save] runs and the caller has indicated (typically by
  /// closure-captured `mounted == false`) that the originating widget is
  /// gone. The owner — usually the app root — installs a closure that
  /// navigates to the recovery screen using the global GoRouter.
  void Function(PendingPhoneVerification record)? onRecoveryNeeded;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final cipher = await _resolveCipher();
      _box = await _openEncryptedBox(cipher);
      _initialized = true;
      if (kDebugMode) {
        debugPrint(
            '[phone-recovery] initialized box=$_boxName (encrypted) hasPending=${_box?.get(_recordKey) != null}');
      }
    } catch (e) {
      // Recovery is a safety net — if Hive fails to open we'd rather
      // limp along without recovery than crash the app.
      if (kDebugMode) {
        debugPrint('[phone-recovery] init failed: $e');
      }
    }
  }

  /// Resolves the AES cipher, minting + persisting a fresh 256-bit key in
  /// secure storage (Keychain / Keystore) on first run. The record this box
  /// holds carries signup PII (email, name, link code, phone), so it must be
  /// encrypted at rest — `allowBackup=false` alone doesn't protect a rooted
  /// or jailbroken device.
  Future<HiveAesCipher> _resolveCipher() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
    );
    final existing = await storage.read(key: _cipherKeyName);
    if (existing != null) {
      return HiveAesCipher(base64Decode(existing));
    }
    final key = Hive.generateSecureKey();
    await storage.write(key: _cipherKeyName, value: base64Encode(key));
    return HiveAesCipher(key);
  }

  /// Opens the box with [cipher]. If a pre-existing box on disk was written
  /// unencrypted (an app upgraded from before 3.1) or with a key we no longer
  /// hold, opening with a cipher throws — in that case we wipe and recreate.
  /// Safe: the box only ever holds a single record with a <5-minute TTL, so
  /// the worst case is one in-flight verification is dropped and the user
  /// re-requests the SMS code.
  Future<Box<dynamic>> _openEncryptedBox(HiveAesCipher cipher) async {
    try {
      return await Hive.openBox<dynamic>(_boxName, encryptionCipher: cipher);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[phone-recovery] encrypted open failed, wiping legacy box: $e');
      }
      await Hive.deleteBoxFromDisk(_boxName);
      return Hive.openBox<dynamic>(_boxName, encryptionCipher: cipher);
    }
  }

  /// Persists [record], overwriting any prior record. Safe to call from
  /// inside the Firebase `codeSent` callback — no awaits before the
  /// write reaches Hive's queue.
  Future<void> save(PendingPhoneVerification record) async {
    if (_box == null) return;
    try {
      await _box!.put(_recordKey, record.toMap());
      if (kDebugMode) {
        debugPrint(
            '[phone-recovery] saved mode=${record.mode.name} phone=${record.phoneE164} verificationIdLen=${record.verificationId.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[phone-recovery] save failed: $e');
      }
    }
  }

  /// Reads the current pending record, or null if absent / stale. Stale
  /// records are deleted as a side-effect so the next call sees a clean
  /// state.
  Future<PendingPhoneVerification?> peek() async {
    if (_box == null) return null;
    final raw = _box!.get(_recordKey) as Map?;
    final record = PendingPhoneVerification.fromMap(raw);
    if (record == null) return null;
    final age = DateTime.now().difference(record.savedAt);
    if (age > _maxAge) {
      if (kDebugMode) {
        debugPrint(
            '[phone-recovery] peek discarded stale record age=${age.inSeconds}s');
      }
      await clear();
      return null;
    }
    return record;
  }

  /// Removes any pending record. Called on successful verification,
  /// user cancel, sign-out, and stale-record reads.
  Future<void> clear() async {
    if (_box == null) return;
    try {
      await _box!.delete(_recordKey);
      if (kDebugMode) {
        debugPrint('[phone-recovery] cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[phone-recovery] clear failed: $e');
      }
    }
  }

  /// Synchronous "has any record" check used by widgets that need to
  /// decide at build time without awaiting. Doesn't enforce expiry — use
  /// [peek] for that.
  bool get hasPendingRaw {
    if (_box == null) return false;
    return _box!.get(_recordKey) != null;
  }
}
