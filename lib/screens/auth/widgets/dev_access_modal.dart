import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/dev_access_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_borders.dart';
import '../../../core/theme/lumi_spacing.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';

/// Opens a modal that authenticates the caller as a dev-approved account.
///
/// Flow:
///  1. User enters email + password.
///  2. We call `signInWithEmailAndPassword` to verify credentials.
///  3. If sign-in succeeds, we refresh [DevAccessService] (Firestore lookup
///     against `/devAccessEmails/{sha256(email)}`).
///  4. If they're on the allowlist → modal closes, caller's `hasDevAccess()`
///     flips to `true` through the service's `ValueNotifier`.
///  5. If they're signed in but NOT on the allowlist → we sign them out
///     again so a rejected account can't leak into the rest of the app.
///
/// Returns `true` iff dev access was successfully unlocked.
Future<bool> showDevAccessModal(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _DevAccessDialog(),
  );
  return result ?? false;
}

class _DevAccessDialog extends StatefulWidget {
  const _DevAccessDialog();

  @override
  State<_DevAccessDialog> createState() => _DevAccessDialogState();
}

class _DevAccessDialogState extends State<_DevAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final auth = FirebaseAuth.instance;
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = _authErrorMessage(e.code);
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Could not verify. Check your connection and retry.';
      });
      return;
    }

    // Credentials accepted — now verify the account is actually on the
    // dev allowlist. refresh() awaits the Firestore lookup.
    await DevAccessService.instance.refresh();
    if (!mounted) return;

    if (DevAccessService.instance.hasAccess) {
      Navigator.of(context).pop(true);
      return;
    }

    // Authenticated but not authorised for dev surfaces. Sign the account
    // out again so the rest of the app doesn't treat them as a logged-in
    // user, and tell them why.
    try {
      await auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errorMessage =
          'This account doesn\'t have dev access. Ask the super admin to add you.';
    });
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-email':
        return 'Invalid email or password.';
      case 'user-disabled':
        return 'This account is disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Check your connection and retry.';
      default:
        return 'Could not verify. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: LumiBorders.medium),
      title: Text(
        'Dev access',
        style: LumiTextStyles.h3(),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign in with a dev-approved account to unlock DEV-only features.',
              style: LumiTextStyles.bodySmall().copyWith(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            LumiGap.m,
            if (_errorMessage != null) ...[
              Container(
                padding: LumiPadding.allS,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: LumiBorders.small,
                  border: Border.all(color: AppColors.error, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 20),
                    LumiGap.horizontalXS,
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: LumiTextStyles.bodySmall().copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              LumiGap.s,
            ],
            TextFormField(
              controller: _emailController,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Email is required';
                if (!v.contains('@') || !v.contains('.')) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            LumiGap.s,
            TextFormField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Password is required' : null,
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        LumiPrimaryButton(
          onPressed: _busy ? null : _submit,
          text: 'Verify',
          isLoading: _busy,
        ),
      ],
    );
  }
}
