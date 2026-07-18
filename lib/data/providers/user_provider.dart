import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/impersonation_session.dart';
import '../../core/exceptions/session_exceptions.dart';
import '../../core/services/impersonation_service.dart';
import '../../services/firebase_service.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

final authStateChangesProvider = StreamProvider<String?>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return firebaseService.authStateChanges.map((user) => user?.uid);
});

/// Live view of the signed-in Firebase Auth user, re-emitting whenever that
/// user's profile changes — crucially when a phone-only account links an
/// email. [authStateChangesProvider] only fires on sign-in/out, so it can't
/// observe an email being added to an existing session.
final firebaseUserChangesProvider = StreamProvider<User?>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return firebaseService.userChanges;
});

/// The signed-in account's email as a live value (empty/null when none),
/// sourced from Firebase Auth via [firebaseUserChangesProvider] so it updates
/// within moments of an email being linked — no app restart or re-login.
///
/// Returns null during a developer impersonation session: the live auth user
/// is the developer, not the impersonated parent, so callers should fall back
/// to the impersonated [UserModel]'s own email instead.
final authEmailProvider = Provider<String?>((ref) {
  if (ref.watch(impersonationSessionProvider).value != null) return null;
  return ref.watch(firebaseUserChangesProvider).value?.email;
});

/// Exposes the [ImpersonationService] singleton so Riverpod-aware code can
/// watch its ChangeNotifier.
final impersonationServiceProvider = Provider<ImpersonationService>((ref) {
  return ImpersonationService.instance;
});

/// Stream of the current impersonation session, or null when inactive.
/// Rebuilds listeners whenever the service's notifier fires.
final impersonationSessionProvider =
    StreamProvider<ImpersonationSession?>((ref) {
  final service = ref.watch(impersonationServiceProvider);
  final controller = StreamController<ImpersonationSession?>.broadcast();
  controller.add(service.active);
  void listener() => controller.add(service.active);
  service.addListener(listener);
  ref.onDispose(() {
    service.removeListener(listener);
    controller.close();
  });
  return controller.stream;
});

/// Resolves the current user.
///
/// During a developer impersonation session, this returns the TARGET user's
/// model (loaded directly from `schools/{targetSchoolId}/users/{targetUid}`)
/// so downstream providers — dashboards, allocation queries, etc. — behave
/// as if the dev were signed in as that teacher/admin. The real auth UID is
/// still the dev's; only the surfaced UserModel is swapped.
final userProvider = StreamProvider<UserModel?>((ref) {
  final impersonation = ref.watch(impersonationSessionProvider).value;
  final userRepository = ref.read(userRepositoryProvider);

  if (impersonation != null) {
    return userRepository
        .getUserInSchool(impersonation.schoolId, impersonation.targetUserId)
        .asStream();
  }

  final authState = ref.watch(authStateChangesProvider);
  final uid = resolveUserProviderUid(
    authState,
    FirebaseAuth.instance.currentUser?.uid,
  );
  if (uid == null) return Stream.value(null);
  return _loadUserResilient(userRepository, uid);
});

/// Resolves the UID without turning the short initial auth-stream loading
/// window into a false signed-out/profile-missing result.
///
/// An explicit `AsyncData(null)` remains authoritative: once Firebase emits a
/// signed-out state, a possibly stale synchronous user must never resurrect
/// the session. The synchronous UID is used only while the stream is loading
/// or has a transient error; all profile reads still go through Firestore
/// Security Rules with Firebase's verified ID token.
@visibleForTesting
String? resolveUserProviderUid(
  AsyncValue<String?> authState,
  String? currentFirebaseUid,
) {
  return authState.when(
    data: (uid) => uid,
    loading: () => currentFirebaseUid,
    error: (_, __) => currentFirebaseUid,
  );
}

/// Loads the profile for [uid], retrying briefly on a null/failed read while a
/// Firebase session is still present — staying in the loading state (no
/// emission) between attempts rather than surfacing a premature null.
///
/// Right after account creation the phone-MFA enrol revokes and re-establishes
/// the session (a custom-token re-auth). During that swap the first profile
/// read can miss — the ID token / email aren't hydrated yet, or the token is
/// mid-revocation — even though the user is validly signed in. The old one-shot
/// `getUser(uid).asStream()` surfaced that transient miss as a *sticky* null,
/// which the router rendered as a blank login screen that never self-healed.
/// Retrying (and only emitting null once the session is genuinely gone or the
/// attempts are exhausted) makes a fresh signup land on home instead of being
/// bounced back to login.
Stream<UserModel?> _loadUserResilient(
  UserRepository repository,
  String uid,
) async* {
  const maxAttempts = 5;
  const retryGap = Duration(milliseconds: 400);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    UserModel? user;
    try {
      user = await repository.getUser(uid);
    } on InvalidUserSessionException {
      try {
        await FirebaseService.instance.signOut();
      } catch (_) {
        // Firebase Auth sign-out is the essential last resort; the normal
        // service path already made best-effort attempts to clear local data.
        await FirebaseAuth.instance.signOut();
      }
      yield null;
      return;
    } on FirebaseException {
      if (attempt == maxAttempts - 1) rethrow;
      user = null;
    }
    if (user != null) {
      yield user;
      return;
    }
    // Genuinely signed out → surface null so the router shows login.
    if (FirebaseAuth.instance.currentUser == null) {
      yield null;
      return;
    }
    if (attempt < maxAttempts - 1) {
      await Future<void>.delayed(retryGap);
      try {
        await FirebaseAuth.instance.currentUser?.reload();
      } catch (_) {
        // reload can throw while the token is mid-revocation — keep retrying.
      }
    }
  }
  yield null; // Exhausted (~2s) → treat as no profile; router shows login.
}
