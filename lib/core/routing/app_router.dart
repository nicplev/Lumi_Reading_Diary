import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';
import '../services/navigation_state_service.dart';
import '../../screens/auth/splash_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/parent_registration_screen.dart';
import '../../screens/auth/web_not_available_screen.dart';
import '../../screens/parent/parent_home_screen.dart';
import '../../screens/parent/log_reading_screen.dart';
import '../../screens/parent/reading_history_screen.dart';
import '../../screens/parent/student_goals_screen.dart';
import '../../screens/parent/achievements_screen.dart';
import '../../screens/parent/reminder_settings_screen.dart';
import '../../screens/parent/offline_management_screen.dart';
import '../../screens/parent/student_report_screen.dart';
import '../../screens/parent/parent_profile_screen.dart';
import '../../screens/parent/book_browser_screen.dart';
import '../../screens/teacher/teacher_home_screen.dart';
import '../../screens/teacher/allocation_screen.dart';
import '../../screens/teacher/class_detail_screen.dart';
import '../../screens/teacher/reading_groups_screen.dart';
import '../../screens/teacher/class_report_screen.dart';
import '../../screens/teacher/teacher_profile_screen.dart';
import '../../screens/admin/admin_home_screen.dart';
import '../../screens/admin/user_management_screen.dart';
import '../../screens/admin/student_management_screen.dart';
import '../../screens/admin/class_management_screen.dart';
import '../../screens/admin/school_analytics_dashboard.dart';
import '../../screens/admin/parent_linking_management_screen.dart';
import '../../screens/admin/database_migration_screen.dart';
import '../../screens/onboarding/school_registration_wizard.dart';
import '../../screens/onboarding/school_demo_screen.dart';
import '../../screens/onboarding/demo_request_screen.dart';
import '../../screens/marketing/landing_screen.dart';
import '../../screens/design_system_demo_screen.dart';

/// Global navigation key for GoRouter
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// App router configuration with role-based guards and deep linking
class AppRouter {
  static final FirebaseService _firebaseService = FirebaseService.instance;

  /// Main GoRouter instance
  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: '/splash',

    // Global redirect handler for authentication
    redirect: (context, state) async {
      final isLoggedIn = _firebaseService.auth.currentUser != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth') ||
          state.matchedLocation == '/splash';

      // Allow splash and auth routes
      if (state.matchedLocation == '/splash' || isAuthRoute) {
        return null;
      }

      // Redirect to login if not authenticated
      if (!isLoggedIn) {
        return '/auth/login';
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
        builder: (context, state) => const LoginScreen(),
      ),

      GoRoute(
        path: '/auth/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),

      GoRoute(
        path: '/auth/parent-register',
        name: 'parent-register',
        builder: (context, state) => const ParentRegistrationScreen(),
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
          final onboardingId = state.uri.queryParameters['onboardingId'] ?? 'default';
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
        redirect: (context, state) => _requireRole(UserRole.parent),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();

          // Check if parent is accessing from web
          if (kIsWeb) {
            return const WebNotAvailableScreen();
          }

          return ParentHomeScreen(user: user);
        },
      ),

      GoRoute(
        path: '/parent/log-reading',
        name: 'log-reading',
        redirect: (context, state) => _requireRole(UserRole.parent),
        builder: (context, state) {
          // Try to get data from navigation service first
          final tempData = NavigationStateService().getTempData();

          debugPrint('DEBUG: log-reading route - tempData: $tempData');

          final parent = tempData?['parent'] as UserModel?;
          final student = tempData?['student'] as StudentModel?;
          final allocation = tempData?['allocation'] as AllocationModel?;

          debugPrint('DEBUG: parent: ${parent?.id}, student: ${student?.id}, allocation: ${allocation?.id}');

          if (parent == null || student == null) {
            debugPrint('DEBUG: parent or student is null, redirecting to login');
            return const LoginScreen();
          }

          return LogReadingScreen(
            parent: parent,
            student: student,
            allocation: allocation,
          );
        },
      ),

      GoRoute(
        path: '/parent/reading-history',
        name: 'reading-history',
        redirect: (context, state) => _requireRole(UserRole.parent),
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return ReadingHistoryScreen(
            studentId: student.id,
            parentId: student.parentIds.isNotEmpty ? student.parentIds.first : '',
            schoolId: student.schoolId,
          );
        },
      ),

      GoRoute(
        path: '/parent/student-goals',
        name: 'student-goals',
        redirect: (context, state) => _requireRole(UserRole.parent),
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
        redirect: (context, state) => _requireRole(UserRole.parent),
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
        path: '/parent/reminder-settings',
        name: 'reminder-settings',
        redirect: (context, state) => _requireRole(UserRole.parent),
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final studentName = params?['studentName'] as String? ?? 'Student';
          return ReminderSettingsScreen(studentName: studentName);
        },
      ),

      GoRoute(
        path: '/parent/offline-management',
        name: 'offline-management',
        redirect: (context, state) => _requireRole(UserRole.parent),
        builder: (context, state) {
          return const OfflineManagementScreen();
        },
      ),

      GoRoute(
        path: '/parent/student-report',
        name: 'student-report',
        redirect: (context, state) => _requireRole(UserRole.parent),
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
        redirect: (context, state) => _requireRole(UserRole.parent),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          return ParentProfileScreen(user: user!);
        },
      ),

      GoRoute(
        path: '/parent/book-browser',
        name: 'book-browser',
        redirect: (context, state) => _requireRole(UserRole.parent),
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return BookBrowserScreen(
            student: student,
          );
        },
      ),

      // ============================================
      // TEACHER ROUTES
      // ============================================
      GoRoute(
        path: '/teacher/home',
        name: 'teacher-home',
        redirect: (context, state) => _requireRole(UserRole.teacher),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return TeacherHomeScreen(user: user);
        },
      ),

      GoRoute(
        path: '/teacher/allocation',
        name: 'allocation',
        redirect: (context, state) => _requireRole(UserRole.teacher),
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final teacher = params?['teacher'] as UserModel?;
          if (teacher == null) return const LoginScreen();
          return AllocationScreen(
            teacher: teacher,
            selectedClass: params?['selectedClass'] as ClassModel?,
          );
        },
      ),

      GoRoute(
        path: '/teacher/class-detail/:classId',
        name: 'class-detail',
        redirect: (context, state) => _requireRole(UserRole.teacher),
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
        redirect: (context, state) => _requireRole(UserRole.teacher),
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
        redirect: (context, state) => _requireRole(UserRole.teacher),
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
        redirect: (context, state) => _requireRole(UserRole.teacher),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          return TeacherProfileScreen(user: user!);
        },
      ),

      // ============================================
      // ADMIN ROUTES
      // ============================================
      GoRoute(
        path: '/admin/home',
        name: 'admin-home',
        redirect: (context, state) => _requireRole(UserRole.schoolAdmin),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return AdminHomeScreen(user: user);
        },
      ),

      GoRoute(
        path: '/admin/user-management',
        name: 'user-management',
        redirect: (context, state) => _requireRole(UserRole.schoolAdmin),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return UserManagementScreen(adminUser: user);
        },
      ),

      GoRoute(
        path: '/admin/student-management',
        name: 'student-management',
        redirect: (context, state) => _requireRole(UserRole.schoolAdmin),
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final adminUser = params?['adminUser'] as UserModel?;
          final classModel = params?['classModel'] as ClassModel?;
          if (adminUser == null || classModel == null) return const LoginScreen();
          return StudentManagementScreen(
            adminUser: adminUser,
            classModel: classModel,
          );
        },
      ),

      GoRoute(
        path: '/admin/class-management',
        name: 'class-management',
        redirect: (context, state) => _requireRole(UserRole.schoolAdmin),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return ClassManagementScreen(adminUser: user);
        },
      ),

      GoRoute(
        path: '/admin/analytics',
        name: 'school-analytics',
        redirect: (context, state) => _requireRole(UserRole.schoolAdmin),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null || user.schoolId == null) return const LoginScreen();
          return SchoolAnalyticsDashboard(schoolId: user.schoolId!);
        },
      ),

      GoRoute(
        path: '/admin/parent-linking',
        name: 'parent-linking',
        redirect: (context, state) => _requireRole(UserRole.schoolAdmin),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          return ParentLinkingManagementScreen(user: user!);
        },
      ),

      GoRoute(
        path: '/admin/database-migration',
        name: 'database-migration',
        redirect: (context, state) => _requireRole(UserRole.schoolAdmin),
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) return const LoginScreen();
          return DatabaseMigrationScreen(adminUser: user);
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

  /// Role-based route guard
  static String? _requireRole(UserRole requiredRole) {
    final currentUser = _firebaseService.auth.currentUser;

    if (currentUser == null) {
      return '/auth/login';
    }

    // Note: In a real implementation, you'd need to fetch the user's role
    // from Firestore here. For now, we return null (allow access).
    // This could be enhanced with a StreamProvider or FutureProvider
    // to cache the user's role in memory.

    return null;
  }

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
}
