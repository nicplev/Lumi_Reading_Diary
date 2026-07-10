import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'core/services/app_check_service.dart';
import 'core/services/dev_access_service.dart';
import 'core/services/remote_message_controller.dart';
import 'core/services/service_status_controller.dart';
import 'core/widgets/force_update_gate.dart';
import 'core/widgets/impersonation_overlay.dart';
import 'core/widgets/lumi_toast_overlay.dart';
import 'core/widgets/remote_message_overlay.dart';
import 'core/widgets/service_status_overlay.dart';
import 'data/providers/remote_message_provider.dart';
import 'services/firebase_service.dart';
import 'services/offline_service.dart';
import 'services/isbn_assignment_service.dart';
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
      // A failed bootstrap used to die before runApp — a black screen with
      // no message and no way out (the review's "startup brick"). Now any
      // throw in the critical chain lands on a retry screen instead.
      try {
        await _initializeCore();
      } catch (error, stack) {
        debugPrint('FATAL: app bootstrap failed: $error');
        debugPrint('$stack');
        runApp(BootstrapErrorApp(error: error));
        return;
      }

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

/// The critical init chain. Idempotent so the [BootstrapErrorApp] retry can
/// re-run it after a partial failure: Firebase.initializeApp is guarded on
/// Firebase.apps, FirebaseService/NotificationService/Analytics guard
/// themselves, Hive.initFlutter and SystemChrome are safe to repeat, and the
/// best-effort services are individually try-wrapped.
Future<void> _initializeCore() async {
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

  // Initialize Firebase with platform-specific options (guarded so a
  // bootstrap retry after a later-step failure doesn't double-initialize).
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // If a previous sign-out flagged the Firestore cache for clearing, do it now
  // — after Firebase init but BEFORE any Firestore client starts or any
  // listener attaches. This is the only place clearPersistence() is provably
  // safe: doing it inline on sign-out raced live document `.snapshots()`
  // streams and crashed natively, and left a terminated instance that broke the
  // first post-logout login. Here the client hasn't started, so no terminate()
  // is needed and the fresh instance serves the next user cleanly.
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(FirebaseService.firestoreClearPendingKey) ?? false) {
      await FirebaseFirestore.instance.clearPersistence();
      await prefs.remove(FirebaseService.firestoreClearPendingKey);
      debugPrint('bootstrap: cleared Firestore persistence from prior sign-out');
    }
  } catch (e) {
    // Non-fatal — worst case the cache survives to the next launch, which is
    // no worse than before and never blocks startup.
    debugPrint('bootstrap: deferred Firestore clear skipped: $e');
  }

      // OPT-IN: skip phone app-verification so configured Firebase test numbers
      // (e.g. +61400000000 → 123456) sign in directly on the iOS Simulator,
      // which can't receive the silent push used for real app-verification.
      //
      // CRITICAL — off by default. With this on, ONLY console test numbers work;
      // a real number fails with `missing-client-identifier`. The previous
      // `if (kDebugMode)` guard applied it to EVERY debug build, so a debug
      // build sideloaded onto a real phone couldn't sign up with a real number.
      // A physical device (even a debug build) does app-verification for real,
      // so it must stay on. Enable for simulator/test-number runs only with:
      //   flutter run --dart-define=LUMI_DISABLE_APP_VERIFICATION=true
      // NEVER put this in .dart_define.json (that file feeds release builds).
      const disableAppVerification =
          bool.fromEnvironment('LUMI_DISABLE_APP_VERIFICATION');
      if (kDebugMode && !kIsWeb && disableAppVerification) {
        try {
          await FirebaseAuth.instance
              .setSettings(appVerificationDisabledForTesting: true);
          debugPrint('[phone-auth] app verification disabled for testing');
        } catch (e) {
          debugPrint('Warning: phone-auth test settings not applied: $e');
        }
      }

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
        // Register the offline allocation-assignment replay: queued classroom
        // scans drain by re-running the assignment transaction online (the
        // dependency is inverted so OfflineService doesn't import the feature).
        OfflineService.instance.registerAllocationReplay(
          (data) => IsbnAssignmentService().replayQueuedAssignment(data),
        );
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
}

/// Minimal fallback app shown when the critical bootstrap throws — no
/// dependencies on anything that may have failed to initialize. Offers a
/// retry, which re-runs the (idempotent) init chain and swaps in the real
/// app on success.
class BootstrapErrorApp extends StatefulWidget {
  const BootstrapErrorApp({super.key, required this.error});

  final Object error;

  @override
  State<BootstrapErrorApp> createState() => _BootstrapErrorAppState();
}

class _BootstrapErrorAppState extends State<BootstrapErrorApp> {
  late Object _error = widget.error;
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await _initializeCore();
      runApp(const ProviderScope(child: LumiApp()));
    } catch (error, stack) {
      debugPrint('Bootstrap retry failed: $error');
      debugPrint('$stack');
      if (mounted) {
        setState(() {
          _error = error;
          _retrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFBF7F0),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 56, color: Color(0xFF6B6B6B)),
                    const SizedBox(height: 20),
                    const Text(
                      "Lumi couldn't start",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Something went wrong while starting up. Check your '
                      'connection and try again — if it keeps happening, '
                      'restart the app.',
                      style:
                          TextStyle(fontSize: 15, color: Color(0xFF6B6B6B)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$_error',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9B9B9B)),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _retrying ? null : _retry,
                      icon: _retrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(_retrying ? 'Retrying…' : 'Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
      // ForceUpdateGate sits outermost: when the status worker demands a
      // newer build, it replaces everything (banners included) with the
      // blocking update screen.
      builder: (context, child) => ForceUpdateGate(
        // LumiToastOverlay sits outermost of the overlays so bento toasts always
        // float above app + banner chrome; it self-offsets below the service
        // banner when that's showing.
        child: LumiToastOverlay(
          child: RemoteMessageOverlay(
            child: ServiceStatusOverlay(
              child: ImpersonationOverlay(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
