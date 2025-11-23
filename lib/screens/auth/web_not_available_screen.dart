import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi_mascot.dart';

class WebNotAvailableScreen extends StatelessWidget {
  const WebNotAvailableScreen({super.key});

  // App store URLs (replace with actual URLs when published)
  static const String _appStoreUrl =
      'https://apps.apple.com/app/lumi-reading-diary';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.lumi.reading_diary';

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
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: LumiPadding.allL,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Lumi Mascot
                  Animate(
                    effects: const [
                      ScaleEffect(
                        duration: Duration(milliseconds: 600),
                        curve: Curves.elasticOut,
                      ),
                    ],
                    child: const LumiMascot(
                      mood: LumiMood.waving,
                      size: 180,
                    ),
                  ),

                  LumiGap.xl,

                  // Title
                  Text(
                    'Parent App Available on Mobile',
                    style: LumiTextStyles.h1(color: AppColors.charcoal),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms),

                  LumiGap.s,

                  // Subtitle
                  Text(
                    'The Lumi parent experience is optimized for mobile devices. Download the app to log reading sessions and track your child\'s progress!',
                    style: LumiTextStyles.bodyLarge(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 400.ms),

                  LumiGap.xl,

                  // Download Options
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // App Store Button
                      Expanded(
                        child: _AppStoreButton(
                          title: 'iOS App Store',
                          icon: Icons.apple,
                          color: AppColors.charcoal,
                          onPressed: () => _launchUrl(_appStoreUrl),
                          onLongPress: () =>
                              _copyToClipboard(context, _appStoreUrl),
                        ).animate().fadeIn(delay: 600.ms).slideX(begin: -0.2),
                      ),

                      LumiGap.s,

                      // Play Store Button
                      Expanded(
                        child: _AppStoreButton(
                          title: 'Google Play',
                          icon: Icons.phone_android,
                          color: AppColors.rosePink,
                          onPressed: () => _launchUrl(_playStoreUrl),
                          onLongPress: () =>
                              _copyToClipboard(context, _playStoreUrl),
                        ).animate().fadeIn(delay: 700.ms).slideX(begin: 0.2),
                      ),
                    ],
                  ),

                  LumiGap.m,

                  // Tip text
                  Text(
                    'Tip: Long-press a button to copy the link',
                    style: LumiTextStyles.bodySmall(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ).copyWith(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 900.ms),

                  LumiGap.xl,

                  // Features Section
                  Container(
                    padding: LumiPadding.allM,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: LumiBorders.large,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.charcoal.withValues(alpha: 0.08),
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
                          style: LumiTextStyles.h2(color: AppColors.charcoal),
                        ),
                        LumiGap.s,
                        const _FeatureItem(
                          icon: Icons.touch_app,
                          text: 'One-tap reading logging',
                          delay: 1000,
                        ),
                        const _FeatureItem(
                          icon: Icons.offline_bolt,
                          text: 'Works offline - sync when ready',
                          delay: 1100,
                        ),
                        const _FeatureItem(
                          icon: Icons.notifications_active,
                          text: 'Daily reading reminders',
                          delay: 1200,
                        ),
                        const _FeatureItem(
                          icon: Icons.insights,
                          text: 'Beautiful progress visualizations',
                          delay: 1300,
                        ),
                        const _FeatureItem(
                          icon: Icons.emoji_events,
                          text: 'Achievement badges & streaks',
                          delay: 1400,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.1),

                  LumiGap.xl,

                  // Back Button
                  LumiSecondaryButton(
                    onPressed: () => context.go('/auth/login'),
                    text: 'Back to Login',
                    icon: Icons.arrow_back,
                  ).animate().fadeIn(delay: 1500.ms),

                  LumiGap.s,

                  // Teacher/Admin Note
                  Text(
                    'Are you a teacher or administrator? Use the web app to manage your school.',
                    style: LumiTextStyles.bodySmall(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 1600.ms),
                ],
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
      borderRadius: LumiBorders.medium,
      child: Container(
        padding: LumiPadding.allS,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: LumiBorders.medium,
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
            LumiGap.xs,
            Text(
              title,
              style: LumiTextStyles.h3(color: color),
              textAlign: TextAlign.center,
            ),
            LumiGap.xxs,
            Text(
              'Download',
              style: LumiTextStyles.bodySmall(
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
      padding: const EdgeInsets.only(bottom: LumiSpacing.xs),
      child: Row(
        children: [
          Container(
            padding: LumiPadding.allXS,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: LumiBorders.small,
            ),
            child: Icon(
              icon,
              size: 20,
              color: AppColors.success,
            ),
          ),
          LumiGap.xs,
          Expanded(
            child: Text(
              text,
              style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay.ms).slideX(begin: -0.1);
  }
}
