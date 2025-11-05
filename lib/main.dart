import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core/theme/app_theme.dart';
import 'services/firebase_service.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Firebase services
  await FirebaseService.instance.initialize();

  // Configure Flutter Animate
  Animate.restartOnHotReload = true;

  runApp(
    const ProviderScope(
      child: LumiApp(),
    ),
  );
}

class LumiApp extends StatelessWidget {
  const LumiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumi Reading Diary',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
      },
    );
  }
}
