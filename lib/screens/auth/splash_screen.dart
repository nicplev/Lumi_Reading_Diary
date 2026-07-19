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
import '../../services/phone_verification_recovery_service.dart';
import '../../core/exceptions/session_exceptions.dart';
import '../../core/utils/image_decode.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _checking = true;
  String? _resolutionError;

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate({bool includeSplashDelay = true}) async {
    // Wait for splash animation
    if (includeSplashDelay) {
      await Future.delayed(const Duration(seconds: 2));
    }

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
        if (isTerminalAuthSessionError(e)) {
          await _endInvalidSession(firebaseService);
          return;
        }
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
          // Optional analytics is deliberately pseudonymous. Never attach the
          // Firebase UID, child identity, school or account role.
          AnalyticsService.instance.logAppOpened(role: user.role.name);

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
          // A local Auth user without an authoritative profile must not stay
          // half-signed-in (that state loops public login routes).
          await _endInvalidSession(firebaseService);
        }
      } on InvalidUserSessionException {
        await _endInvalidSession(firebaseService);
      } catch (e) {
        debugPrint('Error getting user data: $e');
        _showResolutionError();
      }
    } else {
      // User is not logged in
      _navigateToLogin();
    }
  }

  Future<void> _endInvalidSession(FirebaseService firebaseService) async {
    try {
      await firebaseService.signOut();
    } catch (_) {
      try {
        await firebaseService.auth.signOut();
      } catch (_) {
        // Checked below; never navigate into a public-route loop while the SDK
        // still reports this dead local user as signed in.
      }
    }
    if (firebaseService.auth.currentUser != null) {
      _showResolutionError();
      return;
    }
    if (mounted) _navigateToLogin();
  }

  void _showResolutionError() {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _resolutionError = 'Lumi could not check your sign-in. Check your '
          'connection and try again. Your local reading data is still safe.';
    });
  }

  Future<void> _retryResolution() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _resolutionError = null;
    });
    await _checkAuthAndNavigate(includeSplashDelay: false);
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
              // 4097×6145 source — decode at device resolution, not full size.
              cacheWidth:
                  decodeCacheSize(context, MediaQuery.sizeOf(context).width),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 48),
              child: Center(
                child: _resolutionError == null
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ).animate().fadeIn(delay: 800.ms, duration: 500.ms)
                    : Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _resolutionError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _checking ? null : _retryResolution,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
