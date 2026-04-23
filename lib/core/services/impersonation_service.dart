import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../exceptions/impersonation_exceptions.dart';
import '../models/impersonation_session.dart';

/// Orchestrates the client-side lifecycle of a developer impersonation session.
///
/// Flow:
///   1. `start()` calls `startImpersonationSession` via Cloud Function,
///      which returns a custom token with ephemeral claims.
///   2. Local Firestore cache is cleared to prevent cross-school leakage.
///   3. Client re-signs in with the custom token — the new ID token now
///      carries the impersonation claims which Firestore rules honour.
///   4. A snapshot listener watches the session doc for remote revocation
///      (super-admin kill, dev-access removal, TTL expiry).
///   5. `end()` calls `endImpersonationSession`, clears the cache again,
///      and signs out so the dev must re-authenticate.
///
/// The [active] session is held in memory only. A full app restart clears
/// it; the server-side TTL (30 min) handles truly abandoned sessions.
class ImpersonationService extends ChangeNotifier {
  ImpersonationService._({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  static ImpersonationService? _instance;
  static ImpersonationService get instance =>
      _instance ??= ImpersonationService._();

  @visibleForTesting
  static void debugSetInstance(ImpersonationService service) {
    _instance?.dispose();
    _instance = service;
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  ImpersonationSession? _active;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  Timer? _expiryTimer;

  /// Current active session, or null.
  ImpersonationSession? get active => _active;

  bool get isActive => _active != null;

  // ── Picker-support calls ────────────────────────────────────────────────

  Future<List<ImpersonationSchoolSummary>> listSchools() async {
    final result = await _functions
        .httpsCallable('listImpersonableSchools')
        .call<Map<Object?, Object?>>();
    final schools = (result.data['schools'] as List?) ?? const [];
    return schools
        .whereType<Map>()
        .map((m) => ImpersonationSchoolSummary.fromMap(
            m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<ImpersonationUserSummary>> listUsers({
    required String schoolId,
    required String role,
  }) async {
    final result = await _functions
        .httpsCallable('listImpersonableUsers')
        .call<Map<Object?, Object?>>({'schoolId': schoolId, 'role': role});
    final users = (result.data['users'] as List?) ?? const [];
    return users
        .whereType<Map>()
        .map((m) => ImpersonationUserSummary.fromMap(
            m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Starts a new impersonation session. Completes when the client is signed
  /// in with the impersonation claims and the session watcher is live.
  Future<ImpersonationSession> start({
    required String schoolId,
    required String schoolName,
    required String userId,
    required String userLabel,
    required String role,
    required String reason,
  }) async {
    if (_active != null) {
      throw StateError('An impersonation session is already active.');
    }

    final Map<String, dynamic> response;
    try {
      final result = await _functions
          .httpsCallable('startImpersonationSession')
          .call<Map<Object?, Object?>>({
        'targetSchoolId': schoolId,
        'targetUserId': userId,
        'targetRole': role,
        'reason': reason,
        'clientInfo': {
          'platform': defaultTargetPlatform.name,
          'appVersion': null,
        },
      });
      response = result.data.cast<String, dynamic>();
    } on FirebaseFunctionsException catch (e) {
      throw ImpersonationStartException(e.code, e.message ?? 'unknown');
    }

    final customToken = response['customToken'] as String?;
    final sessionId = response['sessionId'] as String?;
    final expiresAtMs = (response['expiresAt'] as num?)?.toInt();
    if (customToken == null || sessionId == null || expiresAtMs == null) {
      throw ImpersonationStartException(
        'invalid-response',
        'Cloud Function returned an incomplete payload.',
      );
    }

    // Isolate target-school reads from any cached dev-account data before
    // the new claims take effect. Terminate() is required before
    // clearPersistence() on the current SDK.
    await _firestore.terminate();
    await _firestore.clearPersistence();

    // Re-sign-in with the custom token. Firebase Auth swaps the session;
    // the new ID token carries the impersonation claims.
    await _auth.signInWithCustomToken(customToken);

    final now = DateTime.now();
    final session = ImpersonationSession(
      sessionId: sessionId,
      schoolId: schoolId,
      schoolName: schoolName,
      targetUserId: userId,
      targetUserLabel: userLabel,
      role: role,
      reason: reason,
      startedAt: now,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
    );

    _active = session;
    _armExpiryTimer();
    _subscribeToSessionDoc(sessionId);
    notifyListeners();
    return session;
  }

  /// Ends the current session gracefully. Safe to call even if the session
  /// has already been remotely revoked — will no-op cleanup.
  Future<void> end({String reason = 'user_exited'}) async {
    final session = _active;
    if (session == null) return;

    try {
      await _functions
          .httpsCallable('endImpersonationSession')
          .call<Map<Object?, Object?>>({'sessionId': session.sessionId});
    } on FirebaseFunctionsException catch (e) {
      // Best-effort — local teardown must still run.
      debugPrint('[Impersonation] end() function call failed: ${e.code}');
    }

    await _localCleanup();
  }

  /// Called by [assertWritable] whenever a client write is attempted during
  /// an active session. Fire-and-forget; failures only log.
  Future<void> reportBlockedWrite({
    required String collection,
    String? docId,
    String? operation,
    String? reason,
  }) async {
    final session = _active;
    if (session == null) return;
    try {
      await _functions
          .httpsCallable('reportBlockedWrite')
          .call<Map<Object?, Object?>>({
        'sessionId': session.sessionId,
        'collection': collection,
        'docId': docId,
        'operation': operation,
        'reason': reason,
      });
    } catch (e) {
      debugPrint('[Impersonation] reportBlockedWrite failed: $e');
    }
  }

  /// Called when the user navigates to a new top-level screen during a
  /// session. Coarse-grained read logging — one event per screen.
  Future<void> reportScreenViewed(String screen) async {
    final session = _active;
    if (session == null) return;
    try {
      await _functions
          .httpsCallable('reportImpersonationActivity')
          .call<Map<Object?, Object?>>({
        'sessionId': session.sessionId,
        'eventType': 'screen_viewed',
        'details': {'screen': screen},
      });
    } catch (_) {
      // Best-effort.
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────

  void _armExpiryTimer() {
    _expiryTimer?.cancel();
    final session = _active;
    if (session == null) return;
    final remaining = session.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      // Already expired — end immediately without re-calling the function
      // (it will already be marked expired by the scheduled cleaner).
      unawaited(_localCleanup());
      return;
    }
    _expiryTimer = Timer(remaining, () {
      unawaited(end(reason: 'client_ttl_expired'));
    });
  }

  void _subscribeToSessionDoc(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = _firestore
        .collection('devImpersonationSessions')
        .doc(sessionId)
        .snapshots()
        .listen(
      (snap) {
        if (!snap.exists) return;
        final status = snap.data()?['status'];
        if (status != 'active') {
          debugPrint('[Impersonation] session remote-ended: status=$status');
          unawaited(_localCleanup());
        }
      },
      onError: (Object e) {
        // During rule transitions this listener may briefly error; log only.
        debugPrint('[Impersonation] session listener error: $e');
      },
    );
  }

  Future<void> _localCleanup() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _sessionSub?.cancel();
    _sessionSub = null;
    _active = null;
    notifyListeners();
    // Wipe any cached impersonated-school data and sign out so the dev is
    // forced to re-authenticate as themselves.
    try {
      await _firestore.terminate();
      await _firestore.clearPersistence();
    } catch (e) {
      debugPrint('[Impersonation] cache clear on cleanup failed: $e');
    }
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('[Impersonation] signOut on cleanup failed: $e');
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }
}

class ImpersonationSchoolSummary {
  ImpersonationSchoolSummary({
    required this.schoolId,
    required this.name,
    required this.teacherCount,
  });

  factory ImpersonationSchoolSummary.fromMap(Map<String, dynamic> m) =>
      ImpersonationSchoolSummary(
        schoolId: (m['schoolId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        teacherCount: (m['teacherCount'] as num?)?.toInt() ?? 0,
      );

  final String schoolId;
  final String name;
  final int teacherCount;
}

class ImpersonationUserSummary {
  ImpersonationUserSummary({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
  });

  factory ImpersonationUserSummary.fromMap(Map<String, dynamic> m) =>
      ImpersonationUserSummary(
        userId: (m['userId'] ?? '').toString(),
        email: (m['email'] ?? '').toString(),
        fullName: (m['fullName'] ?? '').toString(),
        role: (m['role'] ?? '').toString(),
      );

  final String userId;
  final String email;
  final String fullName;
  final String role;
}
