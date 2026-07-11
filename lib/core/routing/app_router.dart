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
import '../../data/providers/student_by_id_provider.dart';
import '../../services/firebase_service.dart';
import '../services/navigation_state_service.dart';
import '../../screens/auth/splash_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/dev/impersonation_picker_screen.dart';
import '../config/dev_access.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/phone_verify_recovery_screen.dart';
import '../../screens/auth/terms_acceptance_screen.dart';
import '../../screens/auth/web_not_available_screen.dart';
import '../../screens/auth/admin_use_web_portal_screen.dart';
import '../../screens/parent/parent_home_screen.dart';
import '../../screens/parent/log_reading_screen.dart';
import '../../screens/parent/access_locked_screen.dart';
import '../../screens/parent/reading_history_screen.dart';
import '../../screens/parent/student_goals_screen.dart';
import '../../screens/parent/achievements_screen.dart';
import '../../screens/parent/progress_screen.dart';
import '../../screens/parent/offline_management_screen.dart';
import '../../screens/shared/app_icon_screen.dart';
import '../../screens/shared/service_status_screen.dart';
import '../../screens/parent/student_report_screen.dart';
import '../../screens/parent/book_browser_screen.dart';
import '../../screens/parent/parent_notifications_screen.dart';
import '../../screens/parent/reading_success_screen.dart';
import '../../screens/parent/link_child_screen.dart';
import '../../screens/teacher/teacher_home_screen.dart';
import '../../screens/teacher/allocation/allocation_screen.dart';
import '../../screens/teacher/reading_groups_screen.dart';
import '../../screens/teacher/awards_screen.dart';
import '../../screens/teacher/class_report_screen.dart';
import '../../screens/teacher/teacher_profile_screen.dart';
import '../../screens/teacher/student_detail_screen.dart';
import '../../screens/teacher/teacher_student_reading_history_screen.dart';
import '../../screens/teacher/isbn_scanner_screen.dart';
import '../../screens/teacher/cover_scanner_screen.dart';
import '../../screens/teacher/kiosk/classroom_kiosk_screen.dart';
import '../../screens/teacher/teacher_level_management_screen.dart';
import '../../screens/shared/staff_notifications_screen.dart';
import '../../screens/onboarding/school_registration_wizard.dart';
import '../../screens/onboarding/school_demo_screen.dart';
import '../../screens/onboarding/demo_request_screen.dart';
import '../../screens/marketing/landing_screen.dart';
import '../../screens/design_system_demo_screen.dart';
import '../../services/terms_acceptance_service.dart';

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

      // iOS widget deep links arrive as `lumi://widget/home?childId=…` or
      // `lumi://widget/log?childId=…`. Flutter's deep-link channel hands the
      // raw URI to GoRouter, which only sees the path (`/home` or `/log`) and
      // would otherwise 404. Funnel both into the parent home with the child
      // pre-selected; the home_widget plugin's own callback is best-effort.
      if (location == '/home' || location == '/log') {
        final childId = state.uri.queryParameters['childId'] ?? '';
        final action = location == '/log' ? 'log' : 'home';
        return Uri(
          path: '/parent/home',
          queryParameters: {
            if (childId.isNotEmpty) 'widgetChildId': childId,
            'widgetAction': action,
            'widgetTap': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        ).toString();
      }
      if (location == '/teacher') {
        return '/teacher/home';
      }
      final isTermsRoute = location == '/terms-acceptance';

      // Firebase Auth's phone-verification / reCAPTCHA callback
      // (`<reversed-client-id>://firebaseauth/link…`) surfaces in the router as
      // `/link` on iOS after the Safari handoff pops the calling modal. Route
      // it to the phone-verify recovery screen, which reads the persisted
      // verification and shows the SMS-code entry — instead of 404-ing to login
      // or bouncing to the dashboard.
      if (location == '/link') {
        return '/auth/login/phone-verify';
      }

      final firebaseService = _ref.read(firebaseServiceProvider);
      final isLoggedIn = firebaseService.auth.currentUser != null;

      // Web is a marketing-only surface — there is no Flutter web app login.
      // The landing page's login buttons are hidden, but the route still
      // exists, so funnel any direct hit on /auth/login back to the landing
      // page. Parents use the iOS/Android app; teachers/admins use the
      // separate school portal. (Other /auth/* routes — web-not-available,
      // forgot-password — stay reachable.)
      if (kIsWeb && location == '/auth/login') {
        return '/landing';
      }

      // Public routes: accessible without authentication
      final isPublicRoute = location == '/splash' ||
          location.startsWith('/auth') ||
          location == '/landing' ||
          location.startsWith('/onboarding');

      final isPhoneRecoveryRoute = location == '/auth/login/phone-verify';
      if (isPublicRoute && (!isLoggedIn || isPhoneRecoveryRoute)) {
        return null;
      }

      // Dev routes: block in production (design-system-demo)
      if (location == '/design-system-demo') {
        if (!isLoggedIn) return '/auth/login';
        // Gated to dev-access accounts.
        if (!hasDevAccess()) return '/auth/login';
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
        final userRepository = _ref.read(userRepositoryProvider);
        // Right after account creation the MFA enrol revokes + re-establishes
        // the session; the first profile read can transiently miss even though
        // the user is validly signed in. Retry briefly before bouncing to a
        // (blank) login screen, so a fresh signup isn't kicked back to login.
        for (var attempt = 0; attempt < 4; attempt++) {
          final currentUser = firebaseService.auth.currentUser;
          if (currentUser == null) break;
          userModel = await userRepository.getUser(currentUser.uid);
          if (userModel != null || attempt == 3) break;
          await Future<void>.delayed(const Duration(milliseconds: 350));
          try {
            await firebaseService.auth.currentUser?.reload();
          } catch (_) {
            // Token may be mid-revocation; keep retrying.
          }
        }
      }

      if (userModel == null) {
        return '/auth/login';
      }

      final userRole = userModel.role;
      final isImpersonating =
          _ref.read(impersonationSessionProvider).value != null;
      final hasAcceptedTerms =
          TermsAcceptanceService.hasAcceptedCurrentTerms(userModel);

      if (!isImpersonating && !hasAcceptedTerms) {
        if (isTermsRoute) return null;
        return Uri(
          path: '/terms-acceptance',
          queryParameters: {'returnTo': state.uri.toString()},
        ).toString();
      }

      if (isTermsRoute) {
        final returnTo = state.uri.queryParameters['returnTo'];
        if (returnTo != null &&
            returnTo.startsWith('/') &&
            !returnTo.startsWith('/terms-acceptance')) {
          return returnTo;
        }
        return getHomeRouteForRole(userRole);
      }

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
      // School admins use the web portal — there are no /admin/* routes in
      // the mobile app. Any legacy /admin link funnels to the role home,
      // which sends a school admin to the web-portal notice screen.
      if (location.startsWith('/admin')) {
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

      GoRoute(
        path: '/terms-acceptance',
        name: 'terms-acceptance',
        builder: (context, state) => TermsAcceptanceScreen(
          returnTo: state.uri.queryParameters['returnTo'],
        ),
      ),

      // ============================================
      // AUTHENTICATION ROUTES
      // ============================================
      GoRoute(
        path: '/auth/login',
        name: 'login',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final fromSplash = extra is Map && extra['fromSplash'] == true;
          if (!fromSplash) {
            return const MaterialPage<void>(child: LoginScreen());
          }
          return CustomTransitionPage<void>(
            child: const LoginScreen(),
            transitionDuration: const Duration(milliseconds: 900),
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
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
        routes: [
          // Recovery screen for in-flight phone-auth verifications that were
          // orphaned by an iOS reCAPTCHA modal pop (or app relaunch).
          // [PhoneVerificationRecoveryService] persists the verification ID +
          // flow context; this screen reads it and completes the SMS step.
          //
          // Nested under /auth/login so the login screen stays in the stack
          // as the recovery sheet's backdrop — AuthBottomSheetOverlay
          // requires the route to be opaque:false + barrierColor transparent
          // so its BackdropFilter has something real to blur (see the
          // overlay's class docstring).
          GoRoute(
            path: 'phone-verify',
            name: 'phone-verify-recovery',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              opaque: false,
              barrierColor: Colors.transparent,
              transitionDuration: const Duration(milliseconds: 850),
              reverseTransitionDuration: const Duration(milliseconds: 260),
              // The overlay drives its own blur/slide off
              // ModalRoute.of(context).animation, so we just hand the child
              // through here.
              transitionsBuilder: (_, __, ___, child) => child,
              child: const PhoneVerifyRecoveryScreen(),
            ),
          ),
        ],
      ),

      GoRoute(
        path: '/auth/signing-out',
        name: 'signing-out',
        builder: (context, state) => const _SigningOutScreen(),
      ),

      GoRoute(
        path: '/auth/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // ============================================
      // DEVELOPER IMPERSONATION (dev-access gated)
      // ============================================
      GoRoute(
        path: '/dev/impersonate',
        name: 'dev-impersonate',
        redirect: (context, state) => hasDevAccess() ? null : '/auth/login',
        builder: (context, state) => const ImpersonationPickerScreen(),
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
        builder: (context, state) => _userScopedRoute(
          extra: state.extra,
          child: (user) => ParentHomeScreen(
            user: user,
            widgetChildId: state.uri.queryParameters['widgetChildId'],
            widgetAction: state.uri.queryParameters['widgetAction'],
            widgetTapId: state.uri.queryParameters['widgetTap'],
            promptForCharacterOnEntry:
                state.uri.queryParameters['firstParentLogin'] == '1',
          ),
        ),
      ),

      GoRoute(
        path: '/parent/link-child',
        name: 'link-child',
        builder: (context, state) => _userScopedRoute(
          extra: state.extra,
          child: (user) => LinkChildScreen(user: user),
        ),
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

          // Fail-closed entitlement gate. All logging entry points route
          // through here, so one check covers them. The Firestore rules deny
          // the underlying write regardless; this surfaces a clear reason
          // (lapsed child vs suspended school) instead of an opaque error.
          if (!student.hasActiveAccess) {
            return AccessLockedScreen(student: student);
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
        path: '/parent/progress',
        name: 'parent-progress',
        builder: (context, state) {
          final params = state.extra as Map<String, dynamic>?;
          final student = params?['student'] as StudentModel?;
          if (student == null) return const LoginScreen();
          return ProgressScreen(student: student);
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
        path: '/settings/service-status',
        name: 'service-status',
        builder: (context, state) => const ServiceStatusScreen(),
      ),

      // App-icon pack is still in testing — dev-access accounts only, like
      // /dev/impersonate. Drop the redirect to release it publicly.
      GoRoute(
        path: '/settings/app-icon',
        name: 'app-icon',
        redirect: (context, state) => hasDevAccess() ? null : '/auth/login',
        builder: (context, state) => const AppIconScreen(),
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
        path: '/parent/notifications',
        name: 'parent-notifications',
        builder: (context, state) => _userScopedRoute(
          extra: state.extra,
          child: (user) => ParentNotificationsScreen(
            user: user,
            openedFromPush: state.uri.queryParameters['fromPush'] == 'true',
          ),
        ),
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
          final restDayApplied = params?['restDayApplied'] as bool? ?? false;
          final savedOffline = params?['savedOffline'] as bool? ?? false;
          if (student == null || parent == null || readingLog == null) {
            return const LoginScreen();
          }
          return ReadingSuccessScreen(
            student: student,
            parent: parent,
            readingLog: readingLog,
            updatedStats: updatedStats,
            savedOffline: savedOffline,
            restDayApplied: restDayApplied,
          );
        },
      ),

      // ============================================
      // TEACHER ROUTES
      // ============================================
      GoRoute(
        path: '/teacher/home',
        name: 'teacher-home',
        builder: (context, state) => _userScopedRoute(
          extra: state.extra,
          child: (user) => TeacherHomeScreen(user: user),
        ),
      ),

      GoRoute(
        path: '/teacher/allocation',
        name: 'allocation',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          return _userScopedRoute(
            extra: state.extra,
            child: (teacher) => AllocationScreen(
              teacher: teacher,
              selectedClass: params?['selectedClass'] as ClassModel?,
              preselectedStudentId: params?['preselectedStudentId'] as String?,
            ),
          );
        },
      ),

      GoRoute(
        path: '/teacher/reading-groups',
        name: 'reading-groups',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final classModel = params?['classModel'] as ClassModel?;
          if (classModel == null) {
            return const _ResourceNotFoundScaffold(
              message: 'Pick a class first',
            );
          }
          return _userScopedRoute(
            extra: state.extra,
            child: (_) => ReadingGroupsScreen(classModel: classModel),
          );
        },
      ),

      GoRoute(
        path: '/teacher/awards',
        name: 'teacher-awards',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final classModel = params?['classModel'] as ClassModel?;
          if (classModel == null) {
            return const _ResourceNotFoundScaffold(
              message: 'Pick a class first',
            );
          }
          return _userScopedRoute(
            extra: state.extra,
            child: (_) => AwardsScreen(classModel: classModel),
          );
        },
      ),

      GoRoute(
        path: '/teacher/class-report',
        name: 'class-report',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final classModel = params?['classModel'] as ClassModel?;
          if (classModel == null) {
            return const _ResourceNotFoundScaffold(
              message: 'Pick a class first',
            );
          }
          return _userScopedRoute(
            extra: state.extra,
            child: (_) => ClassReportScreen(classModel: classModel),
          );
        },
      ),

      GoRoute(
        path: '/teacher/profile',
        name: 'teacher-profile',
        builder: (context, state) => _userScopedRoute(
          extra: state.extra,
          child: (user) => TeacherProfileScreen(user: user),
        ),
      ),

      GoRoute(
        path: '/teacher/notifications',
        name: 'teacher-notifications',
        builder: (context, state) {
          final extra = state.extra;
          UserModel? extraUser;
          String? preFilledTitle;
          String? preFilledBody;
          Set<String>? preSelectedStudentIds;

          if (extra is Map<String, dynamic>) {
            extraUser = extra['user'] as UserModel?;
            preFilledTitle = extra['preFilledTitle'] as String?;
            preFilledBody = extra['preFilledBody'] as String?;
            final ids = extra['preSelectedStudentIds'];
            if (ids is Set<String>) {
              preSelectedStudentIds = ids;
            } else if (ids is List) {
              preSelectedStudentIds = ids.cast<String>().toSet();
            }
          } else if (extra is UserModel) {
            extraUser = extra;
          }

          return _userScopedRoute(
            extra: extraUser,
            child: (user) => StaffNotificationsScreen(
              user: user,
              preFilledTitle: preFilledTitle,
              preFilledBody: preFilledBody,
              preSelectedStudentIds: preSelectedStudentIds,
            ),
          );
        },
      ),

      GoRoute(
        path: '/teacher/student-detail/:studentId',
        name: 'student-detail',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final classModel = params?['classModel'] as ClassModel?;
          return _studentScopedTeacherRoute(
            extra: state.extra,
            studentIdFromPath: state.pathParameters['studentId']!,
            child: (teacher, student) => StudentDetailScreen(
              teacher: teacher,
              student: student,
              classModel: classModel,
            ),
          );
        },
      ),

      GoRoute(
        path: '/teacher/student-achievements/:studentId',
        name: 'teacher-student-achievements',
        builder: (context, state) => _studentScopedTeacherRoute(
          extra: state.extra,
          studentIdFromPath: state.pathParameters['studentId']!,
          child: (_, student) => AchievementsScreen(
            studentId: student.id,
            schoolId: student.schoolId,
          ),
        ),
      ),

      GoRoute(
        path: '/teacher/student-reading-history/:studentId',
        name: 'teacher-student-reading-history',
        builder: (context, state) => _studentScopedTeacherRoute(
          extra: state.extra,
          studentIdFromPath: state.pathParameters['studentId']!,
          child: (_, student) =>
              TeacherStudentReadingHistoryScreen(student: student),
        ),
      ),

      GoRoute(
        path: '/teacher/level-management',
        name: 'teacher-level-management',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final classModel = params?['classModel'] as ClassModel?;
          if (classModel == null) {
            return const _ResourceNotFoundScaffold(
              message: 'Pick a class first',
            );
          }
          return _userScopedRoute(
            extra: state.extra,
            child: (teacher) => TeacherLevelManagementScreen(
              teacher: teacher,
              classModel: classModel,
            ),
          );
        },
      ),

      GoRoute(
        path: '/teacher/isbn-scanner',
        name: 'teacher-isbn-scanner',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final student = params?['student'] as StudentModel?;
          final studentQueue = params?['studentQueue'] as List<StudentModel>?;
          final classModel = params?['classModel'] as ClassModel?;
          final initialTargetDate = params?['initialTargetDate'] as DateTime?;
          if (classModel == null) {
            return const _ResourceNotFoundScaffold(
              message: 'Pick a class first',
            );
          }
          if (student == null &&
              (studentQueue == null || studentQueue.isEmpty)) {
            return const _ResourceNotFoundScaffold(
              message: 'Pick a student to scan for',
            );
          }
          return _userScopedRoute(
            extra: state.extra,
            child: (teacher) => IsbnScannerScreen(
              teacher: teacher,
              student: student,
              studentQueue: studentQueue,
              classModel: classModel,
              initialTargetDate: initialTargetDate,
            ),
          );
        },
      ),

      GoRoute(
        path: '/teacher/kiosk',
        name: 'teacher-kiosk',
        builder: (context, state) {
          final params = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null;
          final classModel = params?['classModel'] as ClassModel?;
          if (classModel == null) {
            return const _ResourceNotFoundScaffold(
              message: 'Pick a class first',
            );
          }
          return _userScopedRoute(
            extra: state.extra,
            child: (teacher) => ClassroomKioskScreen(
              teacher: teacher,
              classModel: classModel,
            ),
          );
        },
      ),

      GoRoute(
        path: '/teacher/community-scanner',
        name: 'teacher-community-scanner',
        builder: (context, state) => _userScopedRoute(
          extra: state.extra,
          child: (teacher) => CoverScannerScreen(teacher: teacher),
        ),
      ),

      // ============================================
      // ADMIN PORTAL NOTICE
      // ============================================
      // School admins manage their school via the separate web portal.
      // Any school-admin account that signs into the mobile app lands here.
      GoRoute(
        path: '/auth/admin-portal',
        name: 'admin-portal',
        builder: (context, state) => const AdminUseWebPortalScreen(),
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
        // School admins manage their school via the web portal.
        return '/auth/admin-portal';
    }
  }

  /// String-typed variant used by flows (e.g. dev impersonation) that receive
  /// the role over the wire as a raw string. Falls back to the teacher home
  /// for any unknown value.
  static String getHomeRouteForRoleName(String roleName) {
    switch (roleName) {
      case 'parent':
        return '/parent/home';
      case 'teacher':
        return '/teacher/home';
      case 'schoolAdmin':
        return '/auth/admin-portal';
      default:
        return '/teacher/home';
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

/// Builds a route that needs a [UserModel]. Prefers `extra` when it's a
/// [UserModel] (callers that pass it explicitly); otherwise reactively
/// watches [userProvider] so the route does not flash LoginScreen during
/// the brief AsyncLoading window right after sign-in or cold start.
Widget _userScopedRoute({
  required Object? extra,
  required Widget Function(UserModel user) child,
}) {
  if (extra is UserModel) return child(extra);
  if (extra is Map<String, dynamic>) {
    final mapped = extra['teacher'] ?? extra['user'];
    if (mapped is UserModel) return child(mapped);
  }
  return Consumer(
    builder: (context, ref, _) {
      final userAsync = ref.watch(userProvider);
      return userAsync.when(
        data: (user) => user == null ? const LoginScreen() : child(user),
        loading: () => const _RouteLoadingScaffold(),
        error: (_, __) => const LoginScreen(),
      );
    },
  );
}

/// Builds a teacher route that needs a [UserModel] and a [StudentModel].
/// Fast path: both come via `extra`. Otherwise resolves user from
/// [userProvider] and hydrates the student via [studentByIdProvider] using
/// [studentIdFromPath]. Survives cold-start deep links.
Widget _studentScopedTeacherRoute({
  required Object? extra,
  required String studentIdFromPath,
  required Widget Function(UserModel teacher, StudentModel student) child,
}) {
  final params = extra is Map<String, dynamic> ? extra : null;
  final extraUser = params?['teacher'] as UserModel?;
  final extraStudent = params?['student'] as StudentModel?;

  if (extraUser != null && extraStudent != null) {
    return child(extraUser, extraStudent);
  }

  return Consumer(
    builder: (context, ref, _) {
      final userAsync = extraUser != null
          ? AsyncValue<UserModel?>.data(extraUser)
          : ref.watch(userProvider);
      return userAsync.when(
        loading: () => const _RouteLoadingScaffold(),
        error: (_, __) => const LoginScreen(),
        data: (user) {
          if (user == null) return const LoginScreen();
          if (extraStudent != null) return child(user, extraStudent);
          final schoolId = user.schoolId;
          if (schoolId == null) {
            return const _ResourceNotFoundScaffold(
                message: 'Student not found');
          }
          final studentAsync = ref.watch(
            studentByIdProvider(
              (schoolId: schoolId, studentId: studentIdFromPath),
            ),
          );
          return studentAsync.when(
            loading: () => const _RouteLoadingScaffold(),
            error: (_, __) => const _ResourceNotFoundScaffold(
              message: 'Student not found',
            ),
            data: (student) => student == null
                ? const _ResourceNotFoundScaffold(message: 'Student not found')
                : child(user, student),
          );
        },
      );
    },
  );
}

class _RouteLoadingScaffold extends StatelessWidget {
  const _RouteLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SigningOutScreen extends StatelessWidget {
  const _SigningOutScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 16),
              Text('Signing out...'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a route's required resource (class, student) can't be
/// hydrated — invalid id, deleted record, or no extras + no path param.
/// Friendlier than bouncing to LoginScreen.
class _ResourceNotFoundScaffold extends StatelessWidget {
  const _ResourceNotFoundScaffold({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/teacher/home'),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
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
                'assets/lumi/Lumi_Splash_Screen.png',
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}
