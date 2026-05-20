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

/// Shown when a school-admin account signs into the mobile app. School
/// administration lives entirely in the separate web portal, so the mobile
/// app no longer carries admin screens — this screen points admins there.
class AdminUseWebPortalScreen extends StatelessWidget {
  const AdminUseWebPortalScreen({super.key});

  // School-admin web portal. Update this when the production portal URL
  // differs from the current (dev) deployment.
  static const String _portalUrl = 'https://lumi-dev-admin.web.app';

  Future<void> _launchPortal() async {
    final uri = Uri.parse(_portalUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _portalUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Portal link copied to clipboard!'),
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
                      variant: LumiVariant.welcome,
                      size: 180,
                    ),
                  ),

                  LumiGap.xl,

                  // Title
                  Text(
                    'Manage Your School on the Web',
                    style: LumiTextStyles.h1(color: AppColors.charcoal),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms),

                  LumiGap.s,

                  // Subtitle
                  Text(
                    'The school administration dashboard now lives in the Lumi web portal. Open it in your browser to manage staff, classes, students and reports.',
                    style: LumiTextStyles.bodyLarge(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 400.ms),

                  LumiGap.xl,

                  // Open Portal button
                  LumiPrimaryButton(
                    onPressed: _launchPortal,
                    text: 'Open Web Portal',
                    icon: Icons.open_in_new,
                  ).animate().fadeIn(delay: 600.ms),

                  LumiGap.xs,

                  // Copy link
                  TextButton.icon(
                    onPressed: () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy portal link'),
                  ).animate().fadeIn(delay: 700.ms),

                  LumiGap.l,

                  // Portal URL display
                  Container(
                    padding: LumiPadding.allS,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: LumiBorders.medium,
                      border: Border.all(
                        color: AppColors.charcoal.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      _portalUrl,
                      style: LumiTextStyles.bodyMedium(
                        color: AppColors.charcoal.withValues(alpha: 0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ).animate().fadeIn(delay: 800.ms),

                  LumiGap.xl,

                  // Back Button
                  LumiSecondaryButton(
                    onPressed: () => context.go('/auth/login'),
                    text: 'Back to Login',
                    icon: Icons.arrow_back,
                  ).animate().fadeIn(delay: 900.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
