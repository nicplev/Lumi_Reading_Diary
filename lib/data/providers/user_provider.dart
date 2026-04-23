import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/impersonation_session.dart';
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

  final uid = ref.watch(authStateChangesProvider).value;
  if (uid != null) {
    return userRepository.getUser(uid).asStream();
  }
  return Stream.value(null);
});
