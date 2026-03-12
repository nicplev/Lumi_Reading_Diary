import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/routing/app_router.dart';
import '../../data/providers/user_provider.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/analytics_service.dart';
import '../../services/crash_reporting_service.dart';

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

    final firebaseService = ref.read(firebaseServiceProvider);
    final firebaseUser = firebaseService.auth.currentUser;

    if (firebaseUser != null) {
      // Reload to get fresh emailVerified status from Firebase server
      await firebaseUser.reload();
      final refreshedUser = firebaseService.auth.currentUser;

      // Enforce email verification on returning sessions too
      if (refreshedUser == null || !refreshedUser.emailVerified) {
        await firebaseService.auth.signOut();
        if (!mounted) return;
        _navigateToLogin();
        return;
      }

      // User is logged in — read user document directly (avoids StreamProvider hang)
      try {
        final userRepository = ref.read(userRepositoryProvider);
        final user = await userRepository.getUser(firebaseUser.uid);

        if (user != null && mounted) {
          // Set analytics & crash reporting user context
          AnalyticsService.instance.setUserId(user.id);
          AnalyticsService.instance.setUserRole(user.role.name);
          AnalyticsService.instance.logAppOpened(role: user.role.name);
          CrashReportingService.instance.setUserId(user.id);
          CrashReportingService.instance.setCustomKey('role', user.role.name);

          // Save FCM token for parents on auto-login
          if (user.role == UserRole.parent && user.schoolId != null) {
            NotificationService.instance.saveTokenForUser(
              user.schoolId!,
              user.id,
            );
          }

          // Check if parent is trying to access web
          final redirectRoute = AppRouter.checkParentWebAccess(user.role);
          if (redirectRoute != null) {
            context.go(redirectRoute);
            return;
          }

          // Navigate based on role
          final homeRoute = AppRouter.getHomeRouteForRole(user.role);
          context.go(homeRoute, extra: user);
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
    final route = kIsWeb ? '/landing' : '/auth/login';
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Lumi Mascot with animation
            Animate(
              effects: const [
                ScaleEffect(
                  duration: Duration(milliseconds: 600),
                  begin: Offset(0.5, 0.5),
                  end: Offset(1.0, 1.0),
                  curve: Curves.elasticOut,
                ),
              ],
              child: const LumiMascot(
                mood: LumiMood.happy,
                size: 200,
              ),
            ),

            LumiGap.l,

            // App title
            Text(
              'Lumi',
              style: LumiTextStyles.display(color: AppColors.rosePink),
            ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

            LumiGap.xxs,

            // Tagline
            Text(
              'Reading Diary',
              style: LumiTextStyles.h2(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

            LumiGap.xl,

            // Loading indicator
            CircularProgressIndicator(
              color: AppColors.rosePink,
              strokeWidth: 3,
            ).animate().fadeIn(delay: 800.ms, duration: 500.ms),
          ],
        ),
      ),
    );
  }
}
