import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Outcome of a PIN entry prompt.
enum KioskPinEntryResult { verified, cancelled, forgot }

const int kKioskPinLength = 4;

InputDecoration _pinDecoration({String? errorText}) => InputDecoration(
      counterText: '',
      hintText: '••••',
      errorText: errorText,
      filled: true,
      fillColor: LumiTokens.cream,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

TextStyle get _pinStyle => LumiType.heading.copyWith(letterSpacing: 12);

/// Two-step "choose a PIN → confirm it" dialog. Returns the chosen PIN, or
/// null if cancelled.
Future<String?> showKioskPinSetupDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _PinSetupDialog(),
  );
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _firstEntry;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    if (value.length != kKioskPinLength) {
      setState(() => _error = 'Enter $kKioskPinLength digits');
      return;
    }
    if (_firstEntry == null) {
      setState(() {
        _firstEntry = value;
        _error = null;
        _controller.clear();
      });
      return;
    }
    if (value != _firstEntry) {
      setState(() {
        _firstEntry = null;
        _error = "Those PINs didn't match — start again";
        _controller.clear();
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _firstEntry != null;
    return AlertDialog(
      title: Text(
        confirming ? 'Confirm the PIN' : 'Choose an exit PIN',
        style: LumiType.subhead,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            confirming
                ? 'Type the same $kKioskPinLength digits once more.'
                : 'Leaving the kiosk will need this $kKioskPinLength-digit PIN.',
            style: LumiType.body.copyWith(color: LumiTokens.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: kKioskPinLength,
            textAlign: TextAlign.center,
            style: _pinStyle,
            decoration: _pinDecoration(errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: LumiType.button.copyWith(color: LumiTokens.muted)),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(confirming ? 'Save PIN' : 'Next', style: LumiType.button),
        ),
      ],
    );
  }
}

/// Prompt for an existing PIN. Wrong entries show an inline error and let the
/// user retry; [allowForgot] adds a "Forgot PIN?" escape hatch.
Future<KioskPinEntryResult> showKioskPinEntryDialog(
  BuildContext context, {
  required String correctPin,
  required String title,
  String? subtitle,
  bool allowForgot = false,
}) async {
  final result = await showDialog<KioskPinEntryResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PinEntryDialog(
      correctPin: correctPin,
      title: title,
      subtitle: subtitle,
      allowForgot: allowForgot,
    ),
  );
  return result ?? KioskPinEntryResult.cancelled;
}

class _PinEntryDialog extends StatefulWidget {
  const _PinEntryDialog({
    required this.correctPin,
    required this.title,
    this.subtitle,
    required this.allowForgot,
  });

  final String correctPin;
  final String title;
  final String? subtitle;
  final bool allowForgot;

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == widget.correctPin) {
      Navigator.pop(context, KioskPinEntryResult.verified);
      return;
    }
    setState(() {
      _error = 'Wrong PIN — try again';
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: LumiType.subhead),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              style: LumiType.body.copyWith(color: LumiTokens.muted),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: kKioskPinLength,
            textAlign: TextAlign.center,
            style: _pinStyle,
            decoration: _pinDecoration(errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.allowForgot)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(context, KioskPinEntryResult.forgot),
                child: Text(
                  'Forgot PIN?',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, KioskPinEntryResult.cancelled),
          child: Text('Cancel',
              style: LumiType.button.copyWith(color: LumiTokens.muted)),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text('Unlock', style: LumiType.button),
        ),
      ],
    );
  }
}
