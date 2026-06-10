import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'core/services/app_check_service.dart';
import 'core/services/dev_access_service.dart';
import 'core/services/remote_message_controller.dart';
import 'core/services/service_status_controller.dart';
import 'core/widgets/impersonation_overlay.dart';
import 'core/widgets/remote_message_overlay.dart';
import 'core/widgets/service_status_overlay.dart';
import 'data/providers/remote_message_provider.dart';
import 'services/firebase_service.dart';
import 'services/offline_service.dart';
import 'services/notification_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/analytics_service.dart';
import 'services/phone_verification_recovery_service.dart';
import 'services/teacher_device_book_cache_service.dart';
import 'services/widget_data_service.dart';
import 'firebase_options.dart';

void main() async {
  // Run app with error handling zone - all initialization must happen inside
  await CrashReportingService.runAppWithZoneGuard(
    () async {
      // Ensure Flutter binding is initialized
      WidgetsFlutterBinding.ensureInitialized();

      // Set preferred orientations (mobile only)
      if (!kIsWeb) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }

      // Initialize Hive for local storage
      await Hive.initFlutter();

      // Initialize teacher device book cache (Hive-backed, persists across sessions).
      // Non-fatal if it fails — lookups fall back to Firestore/API chain.
      try {
        await TeacherDeviceBookCacheService.instance.initialize();
      } catch (e) {
        debugPrint('Warning: Teacher device book cache init failed: $e');
      }

      // Initialize Firebase with platform-specific options
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Activate App Check before any other Firebase SDK calls so attested
      // requests include the token from the very first ID-token mint.
      // No-op unless built with --dart-define=LUMI_APP_CHECK_ENABLED=true.
      await AppCheckService.initialize();

      // Initialize crash reporting (must be after Firebase init)
      await CrashReportingService.instance.initialize();

      // Initialize Firebase services
      await FirebaseService.instance.initialize();

      // Bring up the phone-verification recovery store before any auth UI
      // mounts. It needs to be ready before the splash screen runs its
      // peek check, and before the registration/login screens can install
      // the `codeSent` persistence callbacks.
      try {
        await PhoneVerificationRecoveryService.instance.initialize();
      } catch (e) {
        debugPrint('Warning: PhoneVerificationRecoveryService init failed: $e');
      }

      // Kick off the dev-access listener so the flag is hot by the time
      // the login screen (or any DEV-gated surface) reads it.
      DevAccessService.instance;

      // Initialize notification service (local notifications, FCM, timezone data)
      await NotificationService.instance.initialize();

      // Initialize analytics
      await AnalyticsService.instance.initialize();

      // Initialize iOS home screen widget data bridge
      await WidgetDataService.initialize();

      // Bring up the layered service-status probe before any UI mounts so
      // the first probe is already in flight by the time the splash screen
      // renders. Non-fatal — the controller defaults to `unknown` on
      // failure and the banner suppresses itself.
      try {
        await ServiceStatusController.instance.initialize();
      } catch (e) {
        debugPrint('Warning: ServiceStatusController init failed: $e');
      }

      // Bring up the offline sync service: open its Hive boxes and load any
      // writes queued during a prior offline session so they start draining.
      // Without this the offline-fallback path (saveReadingLogLocally) throws
      // a LateInitializationError and the write is lost — the root cause of
      // "logged offline but never synced." Non-fatal; runs after Firebase and
      // the status controller so the first drain has both available.
      try {
        await OfflineService.instance.initialize();
      } catch (e) {
        debugPrint('Warning: OfflineService init failed: $e');
      }

      // Bring up the out-of-band remote-message client. No-op unless
      // `LUMI_STATUS_WORKER_URL` was supplied at build time.
      if (isRemoteMessageConfigured) {
        try {
          await RemoteMessageController.instance.initialize();
        } catch (e) {
          debugPrint('Warning: RemoteMessageController init failed: $e');
        }
      }

      // Configure Flutter Animate
      Animate.restartOnHotReload = true;

      // Run app
      runApp(
        const ProviderScope(
          child: LumiApp(),
        ),
      );
    },
    onError: (error, stack) {
      debugPrint('Uncaught error: $error');
      debugPrint('Stack trace: $stack');
    },
  );
}

class LumiApp extends ConsumerStatefulWidget {
  const LumiApp({super.key});

  @override
  ConsumerState<LumiApp> createState() => _LumiAppState();
}

class _LumiAppState extends ConsumerState<LumiApp> {
  @override
  void initState() {
    super.initState();
    // Install the warm-resume hook for the phone verification recovery
    // service. When `codeSent` fires while the originating widget (e.g.
    // the registration modal) is unmounted, this hook jumps the user
    // straight to /auth/login/phone-verify so the recovery sheet sits on
    // the login screen as its blurred backdrop (the route is nested under
    // /auth/login for exactly this reason).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = ref.read(routerProvider);
      PhoneVerificationRecoveryService.instance.onRecoveryNeeded = (_) {
        router.go('/auth/login/phone-verify');
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Lumi Reading Diary',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => RemoteMessageOverlay(
        child: ServiceStatusOverlay(
          child: ImpersonationOverlay(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
