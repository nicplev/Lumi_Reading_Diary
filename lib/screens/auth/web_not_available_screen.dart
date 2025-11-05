import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';

class WebNotAvailableScreen extends StatelessWidget {
  const WebNotAvailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryBlue.withValues(alpha: 0.1),
              AppColors.secondaryPurple.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const LumiMascot(
                  mood: LumiMood.thinking,
                  size: 150,
                ),
                const SizedBox(height: 32),
                Text(
                  'Web Version for Teachers & Admins Only',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkGray,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Parents, please use the mobile app to log reading and track your child\'s progress.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.gray,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.phone_android,
                        size: 48,
                        color: AppColors.info,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Download the Mobile App',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkGray,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Available on iOS and Android',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.gray,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
