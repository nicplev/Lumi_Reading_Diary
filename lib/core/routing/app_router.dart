import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/widget_channel_handler.dart';
import '../../services/notification_service.dart';

import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/allocation_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../services/navigation_state_service.dart';
import '../../screens/auth/splash_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/web_not_available_screen.dart';
import '../../screens/parent/parent_home_screen.dart';
import '../../screens/parent/log_reading_screen.dart';
import '../../screens/parent/reading_history_screen.dart';
import '../../screens/parent/student_goals_screen.dart';
import '../../screens/parent/achievements_screen.dart';
import '../../screens/parent/offline_management_screen.dart';
import '../../screens/parent/student_report_screen.dart';
import '../../screens/parent/parent_profile_screen.dart';
import '../../screens/parent/book_browser_screen.dart';
import '../../screens/parent/parent_notifications_screen.dart';
import '../../screens/parent/reading_success_screen.dart';
import '../../screens/teacher/teacher_home_screen.dart';
import '../../screens/teacher/allocation/allocation_screen.dart';
import '../../screens/teacher/class_detail_screen.dart';
import '../../screens/teacher/reading_groups_screen.dart';
import '../../screens/teacher/class_report_screen.dart';
import '../../screens/teacher/teacher_profile_screen.dart';
import '../../screens/teacher/student_detail_screen.dart';
import '../../screens/teacher/teacher_student_reading_history_screen.dart';
import '../../screens/teacher/isbn_scanner_screen.dart';
import '../../screens/teacher/cover_scanner_screen.dart';
import '../../screens/teacher/teacher_level_management_screen.dart';
import '../../screens/admin/admin_home_screen.dart';
import '../../screens/admin/user_management_screen.dart';
import '../../screens/admin/student_management_screen.dart';
import '../../screens/admin/class_management_screen.dart';
import '../../screens/admin/school_analytics_dashboard.dart';
import '../../screens/admin/parent_linking_management_screen.dart';
import '../../screens/admin/database_migration_screen.dart';
import '../../screens/shared/staff_notifications_screen.dart';
import '../../screens/admin/reading_level_settings_screen.dart';
import '../../screens/onboarding/school_registration_wizard.dart';
import '../../screens/onboarding/school_demo_screen.dart';
import '../../screens/onboarding/demo_request_screen.dart';
import '../../screens/marketing/landing_screen.dart';
import '../../screens/design_system_demo_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final appRouter = AppRouter(ref);
  WidgetChannelHandler.initialize(appRouter.router);
  NotificationService.instance.setRouter(appRouter.router);
  return appRouter.router;
});

/// Global navigation key for GoRouter
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// App router configuration with role-based guards and deep linking
class AppRouter {
  final Ref _ref;

  AppRouter(this._ref);

  late final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: '/splash',

    // Global redirect handler for authentication and authorization
    redirect: (context, state) async {
      final location = state.matchedLocation;
      final firebaseService = _ref.read(firebaseServiceProvider);
      final isLoggedIn = firebaseService.auth.currentUser != null;

      // Public routes: accessible without authentication
      final isPublicRoute = location == '/splash' ||
          location.startsWith('/auth') ||
          location == '/landing' ||
          location.startsWith('/onboarding');

      if (isPublicRoute) {
        return null;
      }

      // Dev routes: block in production (design-system-demo)
      if (location == '/design-system-demo') {
        if (!isLoggedIn) return '/auth/login';
        // Only allow admin access to design system demo
        final userModel = await _ref.read(userProvider.future);
        if (userModel == null || userModel.role != UserRole.schoolAdmin) {
          return '/auth/login';
        }
        return null;
      }

      // All remaining routes require authentication
      if (!isLoggedIn) {
        return '/auth/login';
      }

      // Verify user role server-side. Try the cached provider first,
      // fall back to a direct Firestore read to avoid StreamProvider hang.
      UserModel? userModel = _ref.read(userProvider).value;
      if (userModel == null) {
        final uid = firebaseService.auth.currentUser!.uid;
        final userRepository = _ref.read(userRepositoryProvider);
        userModel = await userRepository.getUser(uid);
      }

      if (userModel == null) {
        return '/auth/login';
      }

      final userRole = userModel.role;

      // Web platform check: parent app is mobile-only
      if (kIsWeb &&
          userRole == UserRole.parent &&
          location.startsWith('/parent')) {
        return '/auth/web-not-available';
      }

      // Role-based route protection
      if (location.startsWith('/parent') && userRole != UserRole.parent) {
        return getHomeRouteForRole(userRole);
      }
      if (location.startsWith('/teacher') && userRole != UserRole.teacher) {
        return getHomeRouteForRole(userRole);
      }
      if (location.startsWith('/admin') && userRole != UserRole.schoolAdmin) {
        return getHomeRouteForRole(userRole);
      }

      return null;
    },

    routes: [
      // ============================================
      // SPLASH & LANDING
      // ============================================
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      GoRoute(
        path: '/landing',
        name: 'landing',
        builder: (context, state) => const LandingScreen(),
      ),

      // ============================================
      // AUTHENTICATION ROUTES
      // ============================================
      GoRoute(
        path: '/auth/login',
        name: 'login',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final fromSplash =
              extra is Map && extra['fromSplash'] == true;
          if (!fromSplash) {
            return const MaterialPage<void>(child: LoginScreen());
          }
          return CustomTransitionPage<void>(
            child: const LoginScreen(),
            transitionDuration: const Duration(milliseconds: 900),
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return Stack(
                children: [
                  child,
                  Positioned.fill(
                    child: _BookCoverOverlay(animation: animation),
                  ),
                ],
              );
            },
          );
        },
      ),

      GoRoute(
        path: '/auth/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      GoRoute(
        path: '/auth/web-not-available',
        name: 'web-not-available',
        builder: (context, state) => const WebNotAvailableScreen(),
      ),

      // ============================================
      // ONBOARDING ROUTES
      // ============================================
      GoRoute(
        path: '/onboarding/school-registration',
        name: 'school-registration',
        builder: (context, state) {
          final onboardingId =
              state.uri.queryParameters['onboardingId'] ?? 'default';
          return SchoolRegistrationWizard(onboardingId: onboardingId);
        },
      ),

      GoRoute(
        path: '/onboarding/demo',
        name: 'school-demo',
        builder: (context, state) => const SchoolDemoScreen(),
      ),

      GoRoute(
        path: '/onboarding/demo-request',
        name: 'demo-request',
        builder: (context, state) => const DemoRequestScreen(),
      ),

      // ============================================
      // PARENT ROUTES (Mobile Only)
      // ============================================
      GoRoute(
        path: '/parent/home',
        name: 'parent-home',
        builder: (context, state) {
          final user =
              state.extra as UserModel? ?? _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return ParentHomeScreen(user: user);
        },
      ),

      GoRoute(
        path: '/parent/log-reading',
        name: 'log-reading',
        builder: (context, state) {
          final tempData = NavigationStateService().getTempData();
          final parent = tempData?['parent'] as UserModel?;
          final student = tempData?['student'] as StudentModel?;
          final rawAllocations = tempData?['allocations'];
          final allocations = rawAllocations is List
              ? rawAllocations.whereType<AllocationModel>().toList()
              : const <AllocationModel>[];

          if (parent == null || student == null) {
            return const LoginScreen();
          }

          return LogReadingScreen(
            parent: parent,
            student: student,
            allocations: allocations,
          );
        },
      ),

      GoRoute(
        path: '/parent/reading-history',
        name: 'reading-history',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return ReadingHistoryScreen(
            studentId: student.id,
            parentId:
                student.parentIds.isNotEmpty ? student.parentIds.first : '',
            schoolId: student.schoolId,
          );
        },
      ),

      GoRoute(
        path: '/parent/student-goals',
        name: 'student-goals',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return StudentGoalsScreen(
            student: student,
          );
        },
      ),

      GoRoute(
        path: '/parent/achievements',
        name: 'achievements',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return AchievementsScreen(
            studentId: student.id,
            schoolId: student.schoolId,
          );
        },
      ),


      GoRoute(
        path: '/parent/offline-management',
        name: 'offline-management',
        builder: (context, state) {
          return const OfflineManagementScreen();
        },
      ),

      GoRoute(
        path: '/parent/student-report',
        name: 'student-report',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return StudentReportScreen(
            student: student,
          );
        },
      ),

      GoRoute(
        path: '/parent/profile',
        name: 'parent-profile',
        builder: (context, state) {
          final user =
              state.extra as UserModel? ?? _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return ParentProfileScreen(user: user);
        },
      ),

      GoRoute(
        path: '/parent/notifications',
        name: 'parent-notifications',
        builder: (context, state) {
          final user =
              state.extra as UserModel? ?? _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return ParentNotificationsScreen(user: user);
        },
      ),

      GoRoute(
        path: '/parent/book-browser',
        name: 'book-browser',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return BookBrowserScreen(
            student: student,
          );
        },
      ),

      GoRoute(
        path: '/parent/reading-success',
        name: 'reading-success',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          final parent = params?['parent'] as UserModel?;
          final readingLog = params?['readingLog'] as ReadingLogModel?;
          final updatedStats = params?['updatedStats'] as Map<String, dynamic>?;
          if (student == null || parent == null || readingLog == null) {
            return const LoginScreen();
          }
          return ReadingSuccessScreen(
            student: student,
            parent: parent,
            readingLog: readingLog,
            updatedStats: updatedStats,
          );
        },
      ),

      // ============================================
      // TEACHER ROUTES
      // ============================================
      GoRoute(
        path: '/teacher/home',
        name: 'teacher-home',
        builder: (context, state) {
          final user =
              state.extra as UserModel? ?? _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return TeacherHomeScreen(user: user);
        },
      ),

      GoRoute(
        path: '/teacher/allocation',
        name: 'allocation',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final teacher = params?['teacher'] as UserModel?;
          if (teacher == null) return const LoginScreen();
          return AllocationScreen(
            teacher: teacher,
            selectedClass: params?['selectedClass'] as ClassModel?,
            preselectedStudentId: params?['preselectedStudentId'] as String?,
          );
        },
      ),

      GoRoute(
        path: '/teacher/class-detail/:classId',
        name: 'class-detail',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final teacher = params?['teacher'] as UserModel?;
          final classModel = params?['classModel'] as ClassModel?;
          if (teacher == null || classModel == null) return const LoginScreen();
          return ClassDetailScreen(
            teacher: teacher,
            classModel: classModel,
          );
        },
      ),

      GoRoute(
        path: '/teacher/reading-groups',
        name: 'reading-groups',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final classModel = params?['classModel'] as ClassModel?;
          if (classModel == null) return const LoginScreen();
          return ReadingGroupsScreen(
            classModel: classModel,
          );
        },
      ),

      GoRoute(
        path: '/teacher/class-report',
        name: 'class-report',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final classModel = params?['classModel'] as ClassModel?;
          if (classModel == null) return const LoginScreen();
          return ClassReportScreen(
            classModel: classModel,
          );
        },
      ),

      GoRoute(
        path: '/teacher/profile',
        name: 'teacher-profile',
        builder: (context, state) {
          final user =
              state.extra as UserModel? ?? _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return TeacherProfileScreen(user: user);
        },
      ),

      GoRoute(
        path: '/teacher/notifications',
        name: 'teacher-notifications',
        builder: (context, state) {
          final extra = state.extra;
          UserModel? user;
          String? preFilledTitle;
          String? preFilledBody;
          Set<String>? preSelectedStudentIds;

          if (extra is Map<String, dynamic>) {
            user = extra['user'] as UserModel?;
            preFilledTitle = extra['preFilledTitle'] as String?;
            preFilledBody = extra['preFilledBody'] as String?;
            final ids = extra['preSelectedStudentIds'];
            if (ids is Set<String>) {
              preSelectedStudentIds = ids;
            } else if (ids is List) {
              preSelectedStudentIds = ids.cast<String>().toSet();
            }
          } else if (extra is UserModel) {
            user = extra;
          }

          user ??= _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return StaffNotificationsScreen(
            user: user,
            preFilledTitle: preFilledTitle,
            preFilledBody: preFilledBody,
            preSelectedStudentIds: preSelectedStudentIds,
          );
        },
      ),

      GoRoute(
        path: '/teacher/student-detail/:studentId',
        name: 'student-detail',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final teacher = params?['teacher'] as UserModel?;
          final student = params?['student'] as StudentModel?;
          final classModel = params?['classModel'] as ClassModel?;
          if (teacher == null || student == null) return const LoginScreen();
          return StudentDetailScreen(
            teacher: teacher,
            student: student,
            classModel: classModel,
          );
        },
      ),

      GoRoute(
        path: '/teacher/student-reading-history/:studentId',
        name: 'teacher-student-reading-history',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return TeacherStudentReadingHistoryScreen(student: student);
        },
      ),

      GoRoute(
        path: '/teacher/level-management',
        name: 'teacher-level-management',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final teacher = params?['teacher'] as UserModel?;
          final classModel = params?['classModel'] as ClassModel?;
          if (teacher == null || classModel == null) {
            return const LoginScreen();
          }
          return TeacherLevelManagementScreen(
            teacher: teacher,
            classModel: classModel,
          );
        },
      ),

      GoRoute(
        path: '/teacher/isbn-scanner',
        name: 'teacher-isbn-scanner',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final teacher = params?['teacher'] as UserModel?;
          final student = params?['student'] as StudentModel?;
          final studentQueue = params?['studentQueue'] as List<StudentModel>?;
          final classModel = params?['classModel'] as ClassModel?;
          final initialTargetDate = params?['initialTargetDate'] as DateTime?;
          if (teacher == null || classModel == null) {
            return const LoginScreen();
          }
          if (student == null &&
              (studentQueue == null || studentQueue.isEmpty)) {
            return const LoginScreen();
          }
          return IsbnScannerScreen(
            teacher: teacher,
            student: student,
            studentQueue: studentQueue,
            classModel: classModel,
            initialTargetDate: initialTargetDate,
          );
        },
      ),

      GoRoute(
        path: '/teacher/community-scanner',
        name: 'teacher-community-scanner',
        builder: (context, state) {
          final teacher = AppRouter.resolveUserFromRoute(
            extra: state.extra,
            fallback: _ref.read(userProvider).value,
          );
          if (teacher == null) return const LoginScreen();
          return CoverScannerScreen(teacher: teacher);
        },
      ),

      // ============================================
      // ADMIN ROUTES
      // ============================================
      GoRoute(
        path: '/admin/home',
        name: 'admin-home',
        builder: (context, state) {
          final user =
              state.extra as UserModel? ?? _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return AdminHomeScreen(user: user);
        },
      ),

      GoRoute(
        path: '/admin/user-management',
        name: 'user-management',
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return UserManagementScreen(adminUser: user);
        },
      ),

      GoRoute(
        path: '/admin/student-management',
        name: 'student-management',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final adminUser = params?['adminUser'] as UserModel?;
          final classModel = params?['classModel'] as ClassModel?;
          if (adminUser == null || classModel == null) {
            return const LoginScreen();
          }
          return StudentManagementScreen(
            adminUser: adminUser,
            classModel: classModel,
          );
        },
      ),

      GoRoute(
        path: '/admin/class-management',
        name: 'class-management',
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return ClassManagementScreen(adminUser: user);
        },
      ),

      GoRoute(
        path: '/admin/analytics',
        name: 'school-analytics',
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null || user.schoolId == null) return const LoginScreen();
          return SchoolAnalyticsDashboard(schoolId: user.schoolId!);
        },
      ),

      GoRoute(
        path: '/admin/parent-linking',
        name: 'parent-linking',
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return ParentLinkingManagementScreen(user: user);
        },
      ),

      GoRoute(
        path: '/admin/reading-level-settings',
        name: 'reading-level-settings',
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return ReadingLevelSettingsScreen(adminUser: user);
        },
      ),

      GoRoute(
        path: '/admin/database-migration',
        name: 'database-migration',
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return DatabaseMigrationScreen(adminUser: user);
        },
      ),

      GoRoute(
        path: '/admin/notifications',
        name: 'admin-notifications',
        builder: (context, state) {
          final extra = state.extra;
          UserModel? user;

          if (extra is Map<String, dynamic>) {
            user = extra['user'] as UserModel?;
          } else if (extra is UserModel) {
            user = extra;
          }

          user ??= _ref.read(userProvider).value;
          if (user == null) return const LoginScreen();
          return StaffNotificationsScreen(user: user);
        },
      ),

      // ============================================
      // DEVELOPMENT & DEMO
      // ============================================
      GoRoute(
        path: '/design-system-demo',
        name: 'design-system-demo',
        builder: (context, state) => const DesignSystemDemoScreen(),
      ),
    ],

    // Error handling
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found: ${state.matchedLocation}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/auth/login'),
              child: const Text('Go to Login'),
            ),
          ],
        ),
      ),
    ),
  );

  /// Helper method to navigate to the appropriate home screen based on role
  static String getHomeRouteForRole(UserRole role) {
    switch (role) {
      case UserRole.parent:
        return '/parent/home';
      case UserRole.teacher:
        return '/teacher/home';
      case UserRole.schoolAdmin:
        return '/admin/home';
    }
  }

  /// Helper method to check if a parent is on web and redirect
  static String? checkParentWebAccess(UserRole role) {
    if (kIsWeb && role == UserRole.parent) {
      return '/auth/web-not-available';
    }
    return null;
  }

  @visibleForTesting
  static UserModel? resolveUserFromRoute({
    required Object? extra,
    required UserModel? fallback,
  }) {
    return extra is UserModel ? extra : fallback;
  }
}

/// Splash PNG rendered as a book cover hinged on the left edge. As [animation]
/// runs 0 → 1, the right edge rotates away from the viewer, revealing the
/// login screen beneath.
class _BookCoverOverlay extends StatelessWidget {
  const _BookCoverOverlay({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = curved.value;
          if (t >= 0.98) {
            return const SizedBox.shrink();
          }
          final angle = t * (math.pi / 2);
          return Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25 * t),
                    blurRadius: 24 * t,
                    offset: Offset(8 * t, 0),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/lumi/Lumi_Splash_Screem.png',
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}
