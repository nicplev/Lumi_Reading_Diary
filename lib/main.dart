import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'services/firebase_service.dart';
import 'services/crash_reporting_service.dart';
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

      // Initialize Firebase with platform-specific options
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Initialize crash reporting (must be after Firebase init)
      await CrashReportingService.instance.initialize();

      // Initialize Firebase services
      await FirebaseService.instance.initialize();

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

class LumiApp extends StatelessWidget {
  const LumiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Lumi Reading Diary',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.light,
      routerConfig: AppRouter.router,
    );
  }
}
