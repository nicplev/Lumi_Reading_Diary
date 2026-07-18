import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../services/firebase_service.dart';

/// Shown when a school-admin account signs into the mobile app. School
/// administration lives entirely in the separate web portal, so the mobile
/// app no longer carries admin screens — this screen points admins there.
class AdminUseWebPortalScreen extends StatelessWidget {
  const AdminUseWebPortalScreen({super.key});

  static const String _portalUrl = 'https://lumi-school-admin-au.web.app/login';

  Future<void> _launchPortal() async {
    final uri = Uri.parse(_portalUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _portalUrl));
    if (context.mounted) {
      showLumiToast(
        message: 'Portal link copied to clipboard!',
        type: LumiToastType.success,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await FirebaseService.instance.signOut(
      afterAuthSignOut: () async {
        if (context.mounted) context.go('/auth/login');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: LumiPadding.allL,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Animate(
                    effects: const [
                      ScaleEffect(
                        duration: Duration(milliseconds: 600),
                        curve: Curves.elasticOut,
                      ),
                    ],
                    child: Image.asset(
                      'assets/staff_characters/la_blue.png',
                      height: 180,
                      fit: BoxFit.contain,
                    ),
                  ),

                  LumiGap.xl,

                  // Title
                  Text(
                    'Manage Your School on the Web',
                    style: LumiType.heading,
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms),

                  LumiGap.s,

                  // Subtitle
                  Text(
                    'The school administration dashboard now lives in the Lumi web portal. Open it in your browser to manage staff, classes, students and reports.',
                    style: LumiType.body.copyWith(
                      color: LumiTokens.muted,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 400.ms),

                  LumiGap.xl,

                  // Open Portal button
                  FilledButton.icon(
                    onPressed: _launchPortal,
                    style: FilledButton.styleFrom(
                      backgroundColor: LumiTokens.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusLarge),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 20),
                    label: Text(
                      'Open Web Portal',
                      style: LumiType.button.copyWith(color: Colors.white),
                    ),
                  ).animate().fadeIn(delay: 600.ms),

                  LumiGap.xs,

                  // Copy link
                  TextButton.icon(
                    onPressed: () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy,
                        size: 18, color: LumiTokens.blue),
                    label: Text(
                      'Copy portal link',
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ).animate().fadeIn(delay: 700.ms),

                  LumiGap.l,

                  // Portal URL display
                  Container(
                    padding: LumiPadding.allS,
                    decoration: BoxDecoration(
                      color: LumiTokens.paper,
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                      border: Border.all(color: LumiTokens.rule),
                    ),
                    child: Text(
                      _portalUrl,
                      style: LumiType.body.copyWith(color: LumiTokens.muted),
                      textAlign: TextAlign.center,
                    ),
                  ).animate().fadeIn(delay: 800.ms),

                  LumiGap.xl,

                  // This account remains authenticated while the external
                  // portal opens, so returning to login must explicitly end
                  // the mobile session rather than only changing routes.
                  OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LumiTokens.ink,
                      side: const BorderSide(color: LumiTokens.rule),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusPill),
                      ),
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text(
                      'Sign out',
                      style: LumiType.button.copyWith(color: LumiTokens.ink),
                    ),
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
