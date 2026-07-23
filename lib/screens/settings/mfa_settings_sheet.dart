import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_input.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../data/models/user_model.dart';
import '../../services/mfa_settings_service.dart';
import '../../services/phone_verification_recovery_service.dart';
import '../../services/sms_verification_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';

Future<bool?> showMfaSettingsSheet({
  required BuildContext context,
  required UserModel user,
  required Color accentColor,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MfaSettingsSheet(
      user: user,
      accentColor: accentColor,
    ),
  );
}

class _MfaSettingsSheet extends StatefulWidget {
  final UserModel user;
  final Color accentColor;

  const _MfaSettingsSheet({
    required this.user,
    required this.accentColor,
  });

  @override
  State<_MfaSettingsSheet> createState() => _MfaSettingsSheetState();
}

class _MfaSettingsSheetState extends State<_MfaSettingsSheet> {
  final _service = MfaSettingsService();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  MfaStatus? _status;
  String? _verificationId;
  int? _resendToken;
  bool _loading = true;
  bool _sending = false;
  bool _verifying = false;
  bool _disabling = false;
  String? _error;
  bool _changed = false;

  static final _auMobileRegex = RegExp(r'^04\d{8}$');

  String get _phoneDigits =>
      _phoneController.text.replaceAll(RegExp(r'\s+'), '');
  bool get _phoneValid => _auMobileRegex.hasMatch(_phoneDigits);
  String get _phoneE164 => '+61${_phoneDigits.substring(1)}';
  bool get _codeValid => RegExp(r'^\d{6}$').hasMatch(_codeController.text);

  @override
  void initState() {
    super.initState();
    _prefillPhone();
    _loadStatus();
  }

  /// Pre-fill the phone field with the number already on the account (stored in
  /// E.164, e.g. +61412345678) converted to the local 04… form the input uses,
  /// so the parent doesn't have to retype it. No-op if none is on file.
  void _prefillPhone() {
    final e164 = widget.user.phoneNumber?.trim() ?? '';
    if (e164.startsWith('+61') && e164.length == 12) {
      _phoneController.text = '0${e164.substring(3)}';
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.loadStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = SmsVerificationService.friendlyError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load MFA settings. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    if (!_phoneValid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final handle = await _service.sendEnableCode(
        phoneE164: _phoneE164,
        forceResendingToken: _resendToken,
        // Persist the in-flight verification so the SMS step survives an iOS
        // reCAPTCHA modal pop: if the sheet was already torn down, jump to the
        // code-entry recovery screen; otherwise it stays here in the sheet.
        onCodeSentPersist: (h) {
          final record = PendingPhoneVerification(
            verificationId: h.verificationId,
            resendToken: h.resendToken,
            phoneE164: _phoneE164,
            mode: PhoneVerificationMode.optionalMfaEnrollment,
            contextJson: {
              'role': widget.user.role.name,
              'schoolId': widget.user.schoolId ?? '',
            },
            savedAt: DateTime.now(),
          );
          unawaited(PhoneVerificationRecoveryService.instance.save(record));
          if (!mounted) {
            PhoneVerificationRecoveryService.instance.onRecoveryNeeded
                ?.call(record);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _verificationId = handle.verificationId;
        _resendToken = handle.resendToken;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = SmsVerificationService.friendlyError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send code. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final schoolId = widget.user.schoolId;
    final verificationId = _verificationId;
    if (schoolId == null ||
        schoolId.isEmpty ||
        verificationId == null ||
        !_phoneValid ||
        !_codeValid ||
        _verifying) {
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final outcome = await _service.enableWithCode(
        verificationId: verificationId,
        smsCode: _codeController.text.trim(),
        phoneE164: _phoneE164,
        role: widget.user.role,
        schoolId: schoolId,
      );
      if (!mounted) return;
      _changed = true;
      // Completed in-sheet — drop the recovery record so it can't fire a
      // spurious recovery screen on the next launch.
      unawaited(PhoneVerificationRecoveryService.instance.clear());
      if (outcome == MfaSignupOutcome.needsLogin) {
        showLumiToast(
          message: 'MFA is on. Please sign in again to continue.',
          type: LumiToastType.info,
        );
        Navigator.pop(context, true);
        return;
      }
      await _loadStatus();
      if (!mounted) return;
      showLumiToast(
        message: 'SMS verification turned on',
        type: LumiToastType.success,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = SmsVerificationService.friendlyError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not verify code. Please try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _disable() async {
    final schoolId = widget.user.schoolId;
    final status = _status;
    if (schoolId == null ||
        schoolId.isEmpty ||
        status == null ||
        _disabling) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Turn off SMS check?', style: LumiType.subhead),
        content: Text(
          'Your next sign-in will only use your email and password.',
          style: LumiType.body,
        ),
        actions: [
          LumiDialogAction(
            onPressed: () => Navigator.pop(context, false),
            label: 'Cancel',
            variant: LumiDialogActionVariant.cancel,
          ),
          LumiDialogAction(
            onPressed: () => Navigator.pop(context, true),
            label: 'Turn off',
            variant: LumiDialogActionVariant.destructive,
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _disabling = true;
      _error = null;
    });
    try {
      await _service.disable(
        status: status,
        role: widget.user.role,
        schoolId: schoolId,
      );
      if (!mounted) return;
      _changed = true;
      await _loadStatus();
      if (!mounted) return;
      showLumiToast(
        message: 'SMS verification turned off',
        type: LumiToastType.info,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = SmsVerificationService.friendlyError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not turn off MFA. Please try again.');
    } finally {
      if (mounted) setState(() => _disabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard height (viewInsets) lifts the fields above the keyboard;
    // padding.bottom clears the home indicator. No SafeArea wrapper — that would
    // apply padding.bottom a SECOND time, floating the whole sheet off the
    // bottom edge and exposing the scrim underneath.
    final bottom = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Container(
          decoration: const BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(LumiTokens.radiusXL),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            LumiTokens.space5,
            LumiTokens.space2,
            LumiTokens.space5,
            bottom + LumiTokens.space5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: LumiTokens.rule,
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusPill),
                  ),
                ),
              ),
              const SizedBox(height: LumiTokens.space4),
              Text(
                'SMS verification',
                textAlign: TextAlign.center,
                style: LumiType.subhead,
              ),
              const SizedBox(height: LumiTokens.space4),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                _buildContent(),
              if (_error != null) ...[
                const SizedBox(height: LumiTokens.space3),
                Text(
                  _error!,
                  style: LumiType.caption.copyWith(color: LumiTokens.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: LumiTokens.space4),
              LumiTextButton(
                onPressed: () => Navigator.pop(context, _changed),
                text: 'Done',
                color: LumiTokens.muted,
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildContent() {
    final status = _status;
    if (status == null) {
      return LumiPrimaryButton(
        onPressed: _loadStatus,
        text: 'Try again',
        color: widget.accentColor,
        isFullWidth: true,
      );
    }

    if (status.enabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusPanel(
            icon: Icons.verified_user_outlined,
            title: 'On',
            subtitle: status.phoneNumber == null
                ? 'A phone factor is enrolled.'
                : 'Codes go to ${status.phoneNumber}.',
            accentColor: widget.accentColor,
          ),
          const SizedBox(height: LumiTokens.space4),
          LumiPrimaryButton(
            onPressed: _disabling ? null : _disable,
            text: 'Turn off',
            color: LumiTokens.red,
            isLoading: _disabling,
            isFullWidth: true,
          ),
        ],
      );
    }

    if (status.hasPhonePrimary && !status.hasEmailPrimary) {
      return _StatusPanel(
        icon: Icons.sms_outlined,
        title: 'SMS sign-in',
        subtitle:
            'This account currently uses SMS as its main sign-in method.',
        accentColor: widget.accentColor,
      );
    }

    final hasCode = _verificationId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusPanel(
          icon: Icons.shield_outlined,
          title: 'Off',
          subtitle: 'Turn it on any time for an extra sign-in code.',
          accentColor: widget.accentColor,
        ),
        const SizedBox(height: LumiTokens.space4),
        LumiInput(
          accentColor: widget.accentColor,
          controller: _phoneController,
          hintText: '0400 000 000',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
          ],
          errorText: _phoneDigits.isNotEmpty && !_phoneValid
              ? 'Enter a 10-digit Australian mobile starting with 04'
              : null,
        ),
        const SizedBox(height: LumiTokens.space3),
        LumiPrimaryButton(
          onPressed: _phoneValid && !_sending ? _sendCode : null,
          text: hasCode ? 'Resend code' : 'Send code',
          color: widget.accentColor,
          isLoading: _sending,
          isFullWidth: true,
        ),
        if (hasCode) ...[
          const SizedBox(height: LumiTokens.space4),
          LumiInput(
            accentColor: widget.accentColor,
            controller: _codeController,
            hintText: '123456',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) {
              if (_codeValid && !_verifying) _verifyCode();
            },
          ),
          const SizedBox(height: LumiTokens.space3),
          LumiPrimaryButton(
            onPressed: _codeValid && !_verifying ? _verifyCode : null,
            text: 'Turn on',
            color: widget.accentColor,
            isLoading: _verifying,
            isFullWidth: true,
          ),
        ],
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;

  const _StatusPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LumiTokens.space4),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: LumiTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: LumiType.body.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: LumiType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
