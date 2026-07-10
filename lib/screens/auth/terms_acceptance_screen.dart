import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/user_model.dart';
import '../../data/providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/terms_acceptance_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';

class TermsAcceptanceScreen extends ConsumerStatefulWidget {
  const TermsAcceptanceScreen({super.key, this.returnTo});

  final String? returnTo;

  @override
  ConsumerState<TermsAcceptanceScreen> createState() =>
      _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends ConsumerState<TermsAcceptanceScreen> {
  final TermsAcceptanceService _termsService = TermsAcceptanceService();

  bool _agreed = false;
  bool _saving = false;
  String? _error;

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the legal document.');
    }
  }

  Future<void> _accept(UserModel user) async {
    if (!_agreed || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _termsService.acceptCurrentTerms(user);
      ref.invalidate(userProvider);
      if (!mounted) return;
      context.go(_destinationFor(user));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'We could not save your agreement. Check your connection and try again.';
      });
    }
  }

  Future<void> _signOut() async {
    if (_saving) return;
    setState(() => _saving = true);
    await FirebaseService.instance.signOut(
      afterAuthSignOut: () async {
        if (mounted) context.go('/auth/login');
      },
    );
  }

  String _destinationFor(UserModel user) {
    final returnTo = widget.returnTo;
    if (returnTo != null &&
        returnTo.startsWith('/') &&
        !returnTo.startsWith('/terms-acceptance')) {
      return returnTo;
    }
    return switch (user.role) {
      UserRole.parent => '/parent/home',
      UserRole.teacher => '/teacher/home',
      UserRole.schoolAdmin => '/auth/admin-portal',
    };
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: LumiTokens.cream,
        body: SafeArea(
          child: userAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: LumiTokens.green),
            ),
            error: (_, __) => _ErrorState(onSignOut: _signOut),
            data: (user) {
              if (user == null) {
                return _ErrorState(onSignOut: _signOut);
              }
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _TermsCard(
                      agreed: _agreed,
                      saving: _saving,
                      error: _error,
                      onAgreementChanged: (value) {
                        setState(() => _agreed = value ?? false);
                      },
                      onAccept: () => _accept(user),
                      onSignOut: _signOut,
                      onOpenTerms: () =>
                          _openLegalUrl(TermsAcceptanceService.termsUrl),
                      onOpenPrivacy: () =>
                          _openLegalUrl(TermsAcceptanceService.privacyUrl),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TermsCard extends StatelessWidget {
  const _TermsCard({
    required this.agreed,
    required this.saving,
    required this.onAgreementChanged,
    required this.onAccept,
    required this.onSignOut,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    this.error,
  });

  final bool agreed;
  final bool saving;
  final String? error;
  final ValueChanged<bool?> onAgreementChanged;
  final VoidCallback onAccept;
  final VoidCallback onSignOut;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowFloat,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: LumiTokens.tintGreen.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset('assets/lumi/Lumi_Welcome.png'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Before you continue', style: LumiType.heading),
                    const SizedBox(height: 6),
                    Text(
                      'Please accept Lumi\'s Terms of Use and Privacy Policy to use the app.',
                      style: LumiType.body.copyWith(color: LumiTokens.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 460 ? 3 : 1;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _BentoTile(
                    width: _tileWidth(constraints.maxWidth, columns),
                    icon: Icons.shield_outlined,
                    color: LumiTokens.green,
                    title: 'Protected data',
                    body: 'Your school and reading data stay account-scoped.',
                  ),
                  _BentoTile(
                    width: _tileWidth(constraints.maxWidth, columns),
                    icon: Icons.family_restroom_rounded,
                    color: LumiTokens.blue,
                    title: 'Family access',
                    body: 'Parents only see children linked to their account.',
                  ),
                  _BentoTile(
                    width: _tileWidth(constraints.maxWidth, columns),
                    icon: Icons.auto_stories_rounded,
                    color: LumiTokens.yellow,
                    title: 'Reading tools',
                    body:
                        'Logs, awards, notifications, and reports support reading.',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: LumiTokens.cream,
              borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
              border: Border.all(color: LumiTokens.rule),
            ),
            child: Column(
              children: [
                _LegalLinkRow(
                  icon: Icons.article_outlined,
                  label: 'Terms of Use',
                  onTap: onOpenTerms,
                ),
                const Divider(height: 1, color: LumiTokens.rule),
                _LegalLinkRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: onOpenPrivacy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: saving ? null : () => onAgreementChanged(!agreed),
            borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: agreed
                    ? LumiTokens.tintGreen.withValues(alpha: 0.35)
                    : LumiTokens.paper,
                borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                border: Border.all(
                  color: agreed ? LumiTokens.green : LumiTokens.rule,
                  width: 1.3,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: agreed,
                    onChanged: saving ? null : onAgreementChanged,
                    activeColor: LumiTokens.green,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'I have read and agree to the Terms of Use and Privacy Policy.',
                        style: LumiType.body.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: LumiType.caption.copyWith(
                color: LumiTokens.red,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: agreed && !saving ? onAccept : null,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LumiTokens.paper,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                saving ? 'Saving agreement...' : 'Agree and continue',
                style: LumiType.button,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: LumiTokens.green,
                disabledBackgroundColor: LumiTokens.rule,
                disabledForegroundColor: LumiTokens.muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: saving ? null : onSignOut,
            child: Text(
              'Sign out',
              style: LumiType.button.copyWith(color: LumiTokens.muted),
            ),
          ),
        ],
      ),
    );
  }

  double _tileWidth(double maxWidth, int columns) {
    if (columns == 1) return maxWidth;
    return (maxWidth - (10 * (columns - 1))) / columns;
  }
}

class _BentoTile extends StatelessWidget {
  const _BentoTile({
    required this.width,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final double width;
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 18),
            Text(title,
                style: LumiType.caption.copyWith(color: LumiTokens.ink)),
            const SizedBox(height: 4),
            Text(
              body,
              style: LumiType.caption.copyWith(color: LumiTokens.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalLinkRow extends StatelessWidget {
  const _LegalLinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: LumiTokens.green),
      title: Text(label, style: LumiType.body),
      trailing: const Icon(Icons.open_in_new_rounded, color: LumiTokens.muted),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 44, color: LumiTokens.muted),
            const SizedBox(height: 12),
            Text('Could not load your account', style: LumiType.subhead),
            const SizedBox(height: 8),
            Text(
              'Sign out and try again.',
              style: LumiType.body.copyWith(color: LumiTokens.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onSignOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
