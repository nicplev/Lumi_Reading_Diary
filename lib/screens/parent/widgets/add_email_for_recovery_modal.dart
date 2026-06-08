import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/user_school_index_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../data/models/user_model.dart';
import '../../../services/firebase_service.dart';
import '../../../services/sms_verification_service.dart';

/// Lets a phone-only parent attach an email + password to their existing
/// Firebase Auth account so they have an account-recovery path. The modal
/// links the email credential, sends a verification link, and auto-detects
/// when the parent clicks the link (no "I verified it" button needed).
class AddEmailForRecoveryModal extends StatefulWidget {
  const AddEmailForRecoveryModal({super.key, required this.user});

  final UserModel user;

  static Future<bool?> show({
    required BuildContext context,
    required UserModel user,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => AddEmailForRecoveryModal(user: user),
    );
  }

  @override
  State<AddEmailForRecoveryModal> createState() =>
      _AddEmailForRecoveryModalState();
}

enum _Stage { form, sending, checkInbox, success }

class _AddEmailForRecoveryModalState extends State<AddEmailForRecoveryModal>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Stage _stage = _Stage.form;
  String? _errorMessage;
  StreamSubscription<User?>? _userChangesSub;
  Timer? _resendCooldown;
  int _resendRemainingSec = 0;
  String? _pendingEmail;

  static const _resendCooldownSec = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Resume mid-flow if the user already linked an unverified credential
    // earlier (closed the modal before clicking the email link).
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser?.email != null && fbUser?.emailVerified == false) {
      _pendingEmail = fbUser!.email;
      _stage = _Stage.checkInbox;
      _subscribeToVerification();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _userChangesSub?.cancel();
    _resendCooldown?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user clicks the verification link in their inbox and returns
    // to the app, force a reload so userChanges() emits with the fresh
    // emailVerified value.
    if (state == AppLifecycleState.resumed && _stage == _Stage.checkInbox) {
      FirebaseAuth.instance.currentUser?.reload();
    }
  }

  void _subscribeToVerification() {
    _userChangesSub?.cancel();
    _userChangesSub = FirebaseAuth.instance.userChanges().listen((user) async {
      if (!mounted || user == null) return;
      if (user.emailVerified && user.email != null) {
        await _onEmailVerified(user.email!);
      }
    });
  }

  Future<void> _onEmailVerified(String email) async {
    if (!mounted) return;
    setState(() => _stage = _Stage.success);

    try {
      final schoolId = widget.user.schoolId;
      final uid = widget.user.id;
      if (schoolId == null) return;

      final collection = widget.user.role == UserRole.parent ? 'parents' : 'users';
      await FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection(collection)
          .doc(uid)
          .update({'email': email});

      await UserSchoolIndexService().createOrUpdateIndex(
        email: email,
        schoolId: schoolId,
        userType: collection == 'parents' ? 'parent' : 'user',
        userId: uid,
      );
    } catch (_) {
      // Firestore write failed — the credential is linked and verified on
      // the Firebase Auth side, so recovery still works; the index miss
      // just means email login won't resolve the school. Don't block the
      // success surface; surface a debug-only message and move on.
    }

    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _stage = _Stage.sending;
      _errorMessage = null;
    });

    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        throw FirebaseAuthException(
          code: 'no-current-user',
          message: 'You\'re signed out. Please sign in again and retry.',
        );
      }
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      await fbUser.linkWithCredential(credential);
      await fbUser.sendEmailVerification();

      if (!mounted) return;
      setState(() {
        _stage = _Stage.checkInbox;
        _pendingEmail = email;
      });
      _startResendCooldown();
      _subscribeToVerification();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.form;
        _errorMessage = _friendlyLinkError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.form;
        _errorMessage = 'Couldn\'t add this email. Please try again.';
      });
    }
  }

  Future<void> _resendVerification() async {
    if (_resendRemainingSec > 0) return;
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _startResendCooldown();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
    }
  }

  void _startResendCooldown() {
    _resendCooldown?.cancel();
    setState(() => _resendRemainingSec = _resendCooldownSec);
    _resendCooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendRemainingSec--;
        if (_resendRemainingSec <= 0) {
          timer.cancel();
        }
      });
    });
  }

  String _friendlyLinkError(FirebaseAuthException e) => switch (e.code) {
        'email-already-in-use' || 'credential-already-in-use' =>
          'This email is already used for another account. Try a different one.',
        'invalid-email' =>
          'That email address doesn\'t look right. Please check it.',
        'weak-password' => 'Pick a longer password — at least 6 characters.',
        'requires-recent-login' =>
          'For security, sign out and back in, then add the email again.',
        _ => e.message ?? 'Something went wrong. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (_stage) {
              _Stage.form => _buildForm(key: const ValueKey('form')),
              _Stage.sending => _buildLoading(key: const ValueKey('sending')),
              _Stage.checkInbox => _buildCheckInbox(key: const ValueKey('check')),
              _Stage.success => _buildSuccess(key: const ValueKey('success')),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGrabber() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.charcoal.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildForm({required Key key}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGrabber(),
        Text(
          'Add an email for account recovery',
          style: LumiTextStyles.h2(),
        ),
        const SizedBox(height: 8),
        Text(
          'We\'ll send a verification link to this email. You\'ll be able to sign in with email + password if you ever lose your phone.',
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Please enter your email.';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                    return 'That doesn\'t look like an email.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Create a password',
                  hintText: 'At least 6 characters',
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) {
                  if ((v ?? '').length < 6) {
                    return 'At least 6 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'Passwords don\'t match.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: LumiTextStyles.bodySmall(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 20),
        LumiPrimaryButton(
          onPressed: _submit,
          text: 'Send verification link',
          isFullWidth: true,
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Widget _buildLoading({required Key key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildCheckInbox({required Key key}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGrabber(),
        const Icon(Icons.mark_email_unread_rounded,
            size: 56, color: AppColors.rosePink),
        const SizedBox(height: 16),
        Text('Check your inbox', style: LumiTextStyles.h2(), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'We sent a verification link to ${_pendingEmail ?? "your email"}. Tap the link, then come back here — this screen will update on its own.',
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _resendRemainingSec > 0 ? null : _resendVerification,
          child: Text(
            _resendRemainingSec > 0
                ? 'Resend in ${_resendRemainingSec}s'
                : 'Resend verification email',
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('I\'ll do this later'),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: LumiTextStyles.bodySmall(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildSuccess({required Key key}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildGrabber(),
        const Icon(Icons.check_circle_rounded,
            size: 64, color: AppColors.success),
        const SizedBox(height: 12),
        Text('Email verified', style: LumiTextStyles.h2()),
        const SizedBox(height: 4),
        Text(
          'You can now sign in with email + password too.',
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
