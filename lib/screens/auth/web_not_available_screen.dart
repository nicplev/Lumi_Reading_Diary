import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';

class WebNotAvailableScreen extends StatelessWidget {
  const WebNotAvailableScreen({super.key});

  // App store URLs (replace with actual URLs when published)
  static const String _appStoreUrl = 'https://apps.apple.com/app/lumi-reading-diary';
  static const String _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.lumi.reading_diary';

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyToClipboard(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Link copied to clipboard!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Lumi Mascot
                    const LumiMascot(
                      mood: LumiMood.waving,
                      size: 180,
                    ).animate().scale(
                      duration: 600.ms,
                      curve: Curves.elasticOut,
                    ),

                    const SizedBox(height: 40),

                    // Title
                    Text(
                      'Parent App Available on Mobile',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGray,
                          ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 200.ms),

                    const SizedBox(height: 16),

                    // Subtitle
                    Text(
                      'The Lumi parent experience is optimized for mobile devices. Download the app to log reading sessions and track your child\'s progress!',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.gray,
                          ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 400.ms),

                    const SizedBox(height: 48),

                    // Download Options
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // App Store Button
                        Expanded(
                          child: _AppStoreButton(
                            title: 'iOS App Store',
                            icon: Icons.apple,
                            color: AppColors.darkGray,
                            onPressed: () => _launchUrl(_appStoreUrl),
                            onLongPress: () => _copyToClipboard(context, _appStoreUrl),
                          ).animate().fadeIn(delay: 600.ms).slideX(begin: -0.2),
                        ),

                        const SizedBox(width: 16),

                        // Play Store Button
                        Expanded(
                          child: _AppStoreButton(
                            title: 'Google Play',
                            icon: Icons.phone_android,
                            color: AppColors.secondaryPurple,
                            onPressed: () => _launchUrl(_playStoreUrl),
                            onLongPress: () => _copyToClipboard(context, _playStoreUrl),
                          ).animate().fadeIn(delay: 700.ms).slideX(begin: 0.2),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Tip text
                    Text(
                      'Tip: Long-press a button to copy the link',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray,
                            fontStyle: FontStyle.italic,
                          ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 900.ms),

                    const SizedBox(height: 48),

                    // Features Section
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.darkGray.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What Parents Love:',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.darkGray,
                                ),
                          ),
                          const SizedBox(height: 16),
                          _FeatureItem(
                            icon: Icons.touch_app,
                            text: 'One-tap reading logging',
                            delay: 1000,
                          ),
                          _FeatureItem(
                            icon: Icons.offline_bolt,
                            text: 'Works offline - sync when ready',
                            delay: 1100,
                          ),
                          _FeatureItem(
                            icon: Icons.notifications_active,
                            text: 'Daily reading reminders',
                            delay: 1200,
                          ),
                          _FeatureItem(
                            icon: Icons.insights,
                            text: 'Beautiful progress visualizations',
                            delay: 1300,
                          ),
                          _FeatureItem(
                            icon: Icons.emoji_events,
                            text: 'Achievement badges & streaks',
                            delay: 1400,
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.1),

                    const SizedBox(height: 40),

                    // Back Button
                    OutlinedButton.icon(
                      onPressed: () => context.go('/auth/login'),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Login'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ).animate().fadeIn(delay: 1500.ms),

                    const SizedBox(height: 16),

                    // Teacher/Admin Note
                    Text(
                      'Are you a teacher or administrator? Use the web app to manage your school.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray,
                          ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 1600.ms),
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

class _AppStoreButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  const _AppStoreButton({
    required this.title,
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color: color,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Download',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.8),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final int delay;

  const _FeatureItem({
    required this.icon,
    required this.text,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.darkGray,
                  ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay.ms).slideX(begin: -0.1);
  }
}
