import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Keeps a reactive cached answer to "does the signed-in user have dev access?"
///
/// The source of truth is the Firestore collection `/devAccessEmails/{hash}`,
/// where hash = sha256(lowercased email). The super-admin portal (lumi-admin)
/// is the only writer; Firestore rules only permit a keyed `get` from signed-in
/// clients, so the rest of the list is never exposed.
///
/// Listens to [FirebaseAuth.userChanges] so the flag updates automatically on
/// sign-in / sign-out. Widgets can listen via [ValueNotifier] semantics and
/// rebuild when the value flips.
class DevAccessService extends ChangeNotifier {
  DevAccessService._({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance {
    _authSub = _auth.userChanges().listen(_onAuthChanged);
    _onAuthChanged(_auth.currentUser);
  }

  static DevAccessService? _instance;

  /// Singleton accessor. Call once at app boot (e.g. in `main.dart` after
  /// Firebase is initialised) to start observing auth state; subsequent calls
  /// return the same instance.
  static DevAccessService get instance =>
      _instance ??= DevAccessService._();

  /// Test seam — lets tests inject fakes and replace the singleton.
  @visibleForTesting
  static void debugSetInstance(DevAccessService service) {
    _instance?.dispose();
    _instance = service;
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  StreamSubscription<User?>? _authSub;
  String? _activeEmail;
  bool _hasAccess = false;
  bool _sessionUnlocked = false;

  /// Current cached answer. Safe to read synchronously from `build()`.
  ///
  /// Returns true if EITHER the signed-in user is on the dev allowlist, OR
  /// the dev-access modal verified a dev account during this app run (see
  /// [unlockForSession]). The latter survives the signOut that the modal
  /// performs to avoid poisoning the mobile auth session.
  bool get hasAccess => _sessionUnlocked || _hasAccess;

  /// Marks dev access as unlocked for the remainder of this app process,
  /// independent of the current Firebase Auth user. Called by the dev-access
  /// modal after credentials have been verified against Firestore. The flag
  /// lives only in memory so it's cleared on full app restart — users must
  /// re-verify each launch.
  void unlockForSession() {
    if (_sessionUnlocked) return;
    _sessionUnlocked = true;
    notifyListeners();
  }

  /// Email hash used as the Firestore doc ID. Exposed for tests / debugging.
  @visibleForTesting
  static String hashEmail(String email) {
    return sha256
        .convert(utf8.encode(email.trim().toLowerCase()))
        .toString();
  }

  Future<void> _onAuthChanged(User? user) async {
    final email = user?.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      _activeEmail = null;
      _setAccess(false);
      return;
    }
    // If the listener fires repeatedly for the same user (token refresh, etc.)
    // avoid re-querying.
    if (email == _activeEmail) return;
    _activeEmail = email;

    try {
      final snap = await _firestore
          .collection('devAccessEmails')
          .doc(hashEmail(email))
          .get();
      // Guard against race: another auth change may have superseded this one.
      if (_activeEmail != email) return;
      _setAccess(snap.exists);
    } on FirebaseException catch (e) {
      // `unavailable` is a transient Firestore connection hiccup (common
      // immediately after a fresh sign-in, when gRPC is still warming up).
      // Dev access just stays off; no need to pollute logs.
      if (_activeEmail != email) return;
      _setAccess(false);
      if (e.code != 'unavailable') {
        debugPrint('[DevAccessService] lookup failed for $email: $e');
      }
    } catch (e, st) {
      debugPrint('[DevAccessService] lookup failed for $email: $e\n$st');
      if (_activeEmail != email) return;
      _setAccess(false);
    }
  }

  void _setAccess(bool value) {
    if (_hasAccess == value) return;
    _hasAccess = value;
    notifyListeners();
  }

  /// Force-refresh the current user's access flag. Useful right after a
  /// super-admin grants or revokes access and you want the UI to update
  /// without waiting for the next auth event.
  Future<void> refresh() async {
    final current = _activeEmail;
    _activeEmail = null; // bust the dedupe guard
    await _onAuthChanged(_auth.currentUser);
    // Restore if the user didn't change.
    if (_activeEmail == null && current != null) _activeEmail = current;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
