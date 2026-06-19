import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/exceptions/linking_exceptions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi/lumi_input.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../theme/lumi_tokens.dart';
import '../../data/models/student_link_code_model.dart';
import '../../data/models/user_model.dart';
import '../../data/providers/active_child_provider.dart';
import '../../services/firebase_service.dart';
import '../auth/link_code_scanner_screen.dart';
import 'widgets/character_grid.dart';

enum _LinkStage { code, confirm, character, success }

/// In-app flow that links another child to an already-signed-in parent.
///
/// Verifies an 8-character link code (typed or scanned), confirms the student,
/// then links via [ParentLinkingService]. On success the new child becomes the
/// active child and appears in the switcher — [parentChildrenProvider] streams
/// the parent doc, so the new link propagates without a manual refresh.
class LinkChildScreen extends ConsumerStatefulWidget {
  final UserModel user;

  const LinkChildScreen({super.key, required this.user});

  @override
  ConsumerState<LinkChildScreen> createState() => _LinkChildScreenState();
}

class _LinkChildScreenState extends ConsumerState<LinkChildScreen> {
  static final _codePattern = RegExp(r'^[A-Z0-9]{8}$');

  final _codeController = TextEditingController();

  _LinkStage _stage = _LinkStage.code;
  bool _busy = false;
  String? _errorMessage;
  StudentLinkCodeModel? _verifiedCode;
  String? _selectedCharacterId;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  bool get _codeValid =>
      _codePattern.hasMatch(_codeController.text.toUpperCase().trim());

  String get _studentName {
    final name = _verifiedCode?.metadata?['studentFullName'] as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return 'your child';
  }

  String get _studentFirstName {
    final first = _verifiedCode?.metadata?['studentFirstName'] as String?;
    if (first != null && first.trim().isNotEmpty) return first.trim();
    return 'child';
  }

  Future<void> _openScanner() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LinkCodeScannerScreen(),
      ),
    );
    if (!mounted || scanned == null) return;
    _codeController.text = scanned;
    await _verify();
  }

  Future<void> _verify() async {
    if (!_codeValid || _busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final code = await ref
          .read(parentLinkingServiceProvider)
          .verifyCode(_codeController.text.toUpperCase().trim());
      if (!mounted) return;
      setState(() {
        _verifiedCode = code;
        _stage = _LinkStage.confirm;
      });
    } on LinkingException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Something went wrong verifying the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() async {
    final code = _verifiedCode;
    if (code == null || _busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      try {
        await ref.read(parentLinkingServiceProvider).linkParentToStudent(
              code: code.code,
              parentUserId: widget.user.id,
              parentEmail: widget.user.email,
            );
      } on AlreadyLinkedException {
        // Already linked to this student — treat as success.
      }
      if (!mounted) return;
      // Make the newly linked child active. The children provider streams the
      // parent doc, so the new link surfaces on its own; invalidate as well so
      // the switcher updates immediately even on a flaky connection.
      ref.read(activeChildIdProvider.notifier).select(code.studentId);
      ref.invalidate(parentChildrenProvider);
      // Linked — let the parent pick a character before the success screen.
      setState(() => _stage = _LinkStage.character);
    } on LinkingException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _errorMessage = 'Could not link this child. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetToCode() {
    setState(() {
      _stage = _LinkStage.code;
      _errorMessage = null;
      _verifiedCode = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.charcoal),
        title: Text('Link a child', style: LumiTextStyles.h3()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: LumiPadding.allM,
          child: switch (_stage) {
            _LinkStage.code => _buildCodeStage(),
            _LinkStage.confirm => _buildConfirmStage(),
            _LinkStage.character => _buildCharacterStage(),
            _LinkStage.success => _buildSuccessStage(),
          },
        ),
      ),
    );
  }

  Widget _buildCodeStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumiGap.m,
        const Center(child: LumiMascot(variant: LumiVariant.parent, size: 120)),
        LumiGap.m,
        Text(
          'Add another child',
          style: LumiTextStyles.h2(color: AppColors.charcoal),
          textAlign: TextAlign.center,
        ),
        LumiGap.xs,
        Text(
          'Enter the 8-character code from your child\'s school, or scan '
          'the QR code from their welcome email.',
          style: LumiTextStyles.bodyLarge(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        LumiGap.l,
        LumiInput(
          controller: _codeController,
          hintText: 'e.g. ABC12345',
          autofocus: true,
          maxLength: 8,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          inputFormatters: [_UpperCaseTextFormatter()],
          prefixIcon: IconButton(
            onPressed: _busy ? null : _openScanner,
            tooltip: 'Scan QR code',
            icon: const Icon(Icons.qr_code_scanner, size: 22),
            color: AppColors.charcoal,
          ),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
        ),
        if (_errorMessage != null) ...[
          LumiGap.s,
          _ErrorBanner(message: _errorMessage!),
        ],
        LumiGap.l,
        LumiPrimaryButton(
          onPressed: _codeValid && !_busy ? _verify : null,
          text: 'Verify code',
          isLoading: _busy,
          isFullWidth: true,
          color: LumiTokens.green,
        ),
      ],
    );
  }

  Widget _buildConfirmStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumiGap.m,
        const Center(child: LumiMascot(variant: LumiVariant.parent, size: 120)),
        LumiGap.m,
        Text(
          'Is this your child?',
          style: LumiTextStyles.h2(color: AppColors.charcoal),
          textAlign: TextAlign.center,
        ),
        LumiGap.m,
        LumiCard(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: LumiTokens.tintGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.child_care, color: LumiTokens.green),
              ),
              LumiGap.horizontalS,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _studentName,
                      style: LumiTextStyles.h3(color: AppColors.charcoal),
                    ),
                    Text(
                      'Ready to link to your account',
                      style: LumiTextStyles.bodySmall(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          LumiGap.s,
          _ErrorBanner(message: _errorMessage!),
        ],
        LumiGap.l,
        LumiPrimaryButton(
          onPressed: _busy ? null : _link,
          text: 'Link $_studentFirstName',
          isLoading: _busy,
          isFullWidth: true,
          color: LumiTokens.green,
        ),
        LumiGap.xs,
        LumiTextButton(
          onPressed: _busy ? null : _resetToCode,
          text: 'Use a different code',
          color: LumiTokens.green,
        ),
      ],
    );
  }

  /// Persists the chosen character to the just-linked student, then advances
  /// to the success stage. Picking is optional — see [_skipCharacter].
  Future<void> _saveCharacter() async {
    final code = _verifiedCode;
    final selected = _selectedCharacterId;
    if (code == null || selected == null || _busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await FirebaseService.instance.firestore
          .collection('schools')
          .doc(code.schoolId)
          .collection('students')
          .doc(code.studentId)
          .update({'characterId': selected});
      if (!mounted) return;
      // Re-fetch children so the new character shows on the switcher/home.
      ref.invalidate(parentChildrenProvider);
      setState(() => _stage = _LinkStage.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Could not save the character. You can set it later from your profile.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _skipCharacter() {
    setState(() {
      _errorMessage = null;
      _stage = _LinkStage.success;
    });
  }

  Widget _buildCharacterStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumiGap.m,
        Text(
          'Pick a character for $_studentFirstName',
          style: LumiTextStyles.h2(color: AppColors.charcoal),
          textAlign: TextAlign.center,
        ),
        LumiGap.xs,
        Text(
          "They'll see this character in the app. You can change it anytime.",
          style: LumiTextStyles.bodyLarge(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        LumiGap.l,
        CharacterGrid(
          selectedId: _selectedCharacterId,
          onSelect: (id) => setState(() => _selectedCharacterId = id),
        ),
        if (_errorMessage != null) ...[
          LumiGap.s,
          _ErrorBanner(message: _errorMessage!),
        ],
        LumiGap.l,
        LumiPrimaryButton(
          onPressed:
              _busy || _selectedCharacterId == null ? null : _saveCharacter,
          text: 'Save & continue',
          isLoading: _busy,
          isFullWidth: true,
          color: LumiTokens.green,
        ),
        LumiGap.xs,
        LumiTextButton(
          onPressed: _busy ? null : _skipCharacter,
          text: 'Skip for now',
          color: LumiTokens.green,
        ),
      ],
    );
  }

  Widget _buildSuccessStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumiGap.l,
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 52,
              color: AppColors.success,
            ),
          ),
        ),
        LumiGap.m,
        Text(
          '$_studentName is linked!',
          style: LumiTextStyles.h2(color: AppColors.charcoal),
          textAlign: TextAlign.center,
        ),
        LumiGap.xs,
        Text(
          'You can now track their reading from your home screen.',
          style: LumiTextStyles.bodyLarge(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        LumiGap.l,
        LumiPrimaryButton(
          onPressed: () => context.pop(),
          text: 'Done',
          isFullWidth: true,
          color: LumiTokens.green,
        ),
      ],
    );
  }
}

/// Inline error banner shown beneath the code/confirm inputs.
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: LumiBorders.medium,
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: LumiTextStyles.bodySmall(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forces the link-code field to upper case as the user types.
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
