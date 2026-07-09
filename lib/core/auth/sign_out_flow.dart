import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../services/firebase_service.dart';

/// Signs out from a mounted UI surface, unmounts authenticated screens before
/// Firestore persistence is torn down, then exposes the login screen.
Future<void> signOutAndNavigateToLogin(
  BuildContext context, {
  FirebaseService? firebaseService,
}) async {
  final service = firebaseService ?? FirebaseService.instance;
  final router = GoRouter.of(context);
  await service.signOut(
    afterAuthSignOut: () async {
      router.go('/auth/signing-out');
      await WidgetsBinding.instance.endOfFrame;
    },
  );
  router.go('/auth/login');
}
