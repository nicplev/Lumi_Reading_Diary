import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lumi_tokens.dart';
import '../../core/routing/app_router.dart';
import '../../data/providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/analytics_service.dart';
import '../../services/crash_reporting_service.dart';
import '../../services/phone_verification_recovery_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Wait for splash animation
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Cold-start recovery: if a phone-auth verification was orphaned on
    // a previous run (iOS reCAPTCHA modal pop, force-quit, etc.), pick
    // up where we left off before doing the normal auth resolution.
    // Stale records (>5 min) are cleared by peek() itself.
    final pendingPhoneVerification =
        await PhoneVerificationRecoveryService.instance.peek();
    if (pendingPhoneVerification != null) {
      if (!mounted) return;
      context.go('/auth/login/phone-verify');
      return;
    }

    final firebaseService = ref.read(firebaseServiceProvider);
    final firebaseUser = firebaseService.auth.currentUser;

    if (firebaseUser != null) {
      // Reload to get fresh emailVerified status from Firebase server
      try {
        await firebaseUser.reload().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Firebase reload timed out or failed: $e');
        // Continue with cached state rather than hanging
      }
      final refreshedUser = firebaseService.auth.currentUser;

      // Enforce email verification on returning sessions — EXCEPT for phone-only
      // accounts. Phone-primary signups (the promoted parent flow) have no email
      // provider, so emailVerified is always false; their verified phone number
      // IS their identity. Signing them out here forced a full phone + SMS
      // re-verify on every cold start. (Email+MFA accounts unlink the primary
      // phone at enrol, so phoneNumber is null for them and the email gate still
      // applies.)
      final phone = refreshedUser?.phoneNumber;
      final hasPhonePrimary = phone != null && phone.isNotEmpty;
      if (refreshedUser == null ||
          (!refreshedUser.emailVerified && !hasPhonePrimary)) {
        await firebaseService.auth.signOut();
        if (!mounted) return;
        _navigateToLogin();
        return;
      }

      // User is logged in — read user document directly (avoids StreamProvider hang)
      try {
        final userRepository = ref.read(userRepositoryProvider);
        final user = await userRepository
            .getUser(firebaseUser.uid)
            .timeout(const Duration(seconds: 10));

        if (user != null && mounted) {
          // Set analytics & crash reporting user context
          AnalyticsService.instance.setUserId(user.id);
          AnalyticsService.instance.setUserRole(user.role.name);
          AnalyticsService.instance.logAppOpened(role: user.role.name);
          CrashReportingService.instance.setUserId(user.id);
          CrashReportingService.instance.setCustomKey('role', user.role.name);

          // Register the FCM token + flush any pending refresh. No-op for
          // non-parents or users without a school.
          NotificationService.instance.onParentAuthenticated(user);

          // Check if parent is trying to access web
          final redirectRoute = AppRouter.checkParentWebAccess(user.role);
          if (redirectRoute != null) {
            context.go(redirectRoute);
            return;
          }

          // Navigate based on role. Don't pass UserModel via `extra` —
          // the route reads from userProvider (avoids the no-codec crash).
          final homeRoute = AppRouter.getHomeRouteForRole(user.role);
          context.go(homeRoute);
        } else {
          // User document doesn't exist, go to login
          _navigateToLogin();
        }
      } catch (e) {
        debugPrint('Error getting user data: $e');
        _navigateToLogin();
      }
    } else {
      // User is not logged in
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;

    // Web users see the marketing landing page
    // Mobile users (iOS/Android) go directly to login
    if (kIsWeb) {
      context.go('/landing');
    } else {
      context.go('/auth/login', extra: const {'fromSplash': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/lumi/Lumi_Splash_Screen.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 48),
              child: Center(
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ).animate().fadeIn(delay: 800.ms, duration: 500.ms),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
