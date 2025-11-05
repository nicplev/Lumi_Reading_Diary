import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../parent/parent_home_screen.dart';
import '../teacher/teacher_home_screen.dart';
import '../admin/admin_home_screen.dart';
import '../marketing/landing_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Wait for splash animation
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Check if user is logged in
    final User? firebaseUser = _firebaseService.currentUser;

    if (firebaseUser != null) {
      // User is logged in, get their role and navigate accordingly
      try {
        UserModel? user;

        // Search through all schools for the user (nested structure)
        final schoolsSnapshot =
            await _firebaseService.firestore.collection('schools').get();

        for (final schoolDoc in schoolsSnapshot.docs) {
          final schoolId = schoolDoc.id;

          // Try users collection
          final userDoc = await _firebaseService.firestore
              .collection('schools')
              .doc(schoolId)
              .collection('users')
              .doc(firebaseUser.uid)
              .get();

          if (userDoc.exists) {
            user = UserModel.fromFirestore(userDoc);
            break;
          }

          // Also check parents collection
          final parentDoc = await _firebaseService.firestore
              .collection('schools')
              .doc(schoolId)
              .collection('parents')
              .doc(firebaseUser.uid)
              .get();

          if (parentDoc.exists) {
            user = UserModel.fromFirestore(parentDoc);
            break;
          }
        }

        if (user != null && mounted) {
          // Assign to non-nullable variable for type promotion
          final currentUser = user;

          // Navigate based on role
          switch (currentUser.role) {
            case UserRole.parent:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ParentHomeScreen(user: currentUser),
                ),
              );
              break;

            case UserRole.teacher:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherHomeScreen(user: currentUser),
                ),
              );
              break;

            case UserRole.schoolAdmin:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminHomeScreen(user: currentUser),
                ),
              );
              break;
          }
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

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const LandingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
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

            const SizedBox(height: 32),

            // App title
            Text(
              'Lumi',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
            ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

            const SizedBox(height: 8),

            // Tagline
            Text(
              'Reading Diary',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.gray,
                  ),
            ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

            const SizedBox(height: 48),

            // Loading indicator
            CircularProgressIndicator(
              color: AppColors.primaryBlue,
              strokeWidth: 3,
            ).animate().fadeIn(delay: 800.ms, duration: 500.ms),
          ],
        ),
      ),
    );
  }
}
