import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../data/models/class_model.dart';
import '../../../services/firebase_service.dart';

/// Bottom-sheet editor for a class's comprehension prompt — the question asked
/// at the end of the parent's reading-log wizard. A single string, edited
/// anytime, so it doesn't warrant a full page.
///
/// Writes to `schools/{schoolId}/classes/{classId}.settings.comprehensionQuestion`.
/// When the text matches the default (or is empty) the field is deleted so reads
/// fall back through [ClassModel.comprehensionQuestion]'s default.
Future<void> showComprehensionQuestionSheet(
  BuildContext context, {
  required ClassModel classModel,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ComprehensionQuestionSheet(classModel: classModel),
  );
}

class _ComprehensionQuestionSheet extends StatefulWidget {
  final ClassModel classModel;

  const _ComprehensionQuestionSheet({required this.classModel});

  @override
  State<_ComprehensionQuestionSheet> createState() =>
      _ComprehensionQuestionSheetState();
}

class _ComprehensionQuestionSheetState
    extends State<_ComprehensionQuestionSheet> {
  static const int _maxLength = 200;

  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.classModel.comprehensionQuestion);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _useDefault() {
    setState(() {
      _controller.text = ClassModel.defaultComprehensionQuestion;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  Future<void> _save() async {
    final trimmed = _controller.text.trim();
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final ref = FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.classModel.schoolId)
          .collection('classes')
          .doc(widget.classModel.id);
      // Empty or unchanged-from-default → delete the field so reads fall back
      // to the shared default rather than persisting a redundant copy.
      final isDefault =
          trimmed == ClassModel.defaultComprehensionQuestion || trimmed.isEmpty;
      await ref.update({
        'settings.comprehensionQuestion':
            isDefault ? FieldValue.delete() : trimmed,
      });
      showLumiToast(
        message: isDefault
            ? 'Reset to the default question.'
            : 'Question updated.',
        type: LumiToastType.success,
        duration: const Duration(seconds: 2),
      );
      navigator.pop();
    } catch (e) {
      showLumiToast(
        message: 'Could not save: $e',
        type: LumiToastType.error,
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        LumiTokens.space4,
        LumiTokens.space3,
        LumiTokens.space4,
        bottomInset + LumiTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: LumiTokens.space3),
                decoration: BoxDecoration(
                  color: LumiTokens.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Comprehension question', style: LumiType.subhead),
            const SizedBox(height: 4),
            Text(
              'For ${widget.classModel.name} — asked at the end of the '
              "parent's logging, so the child can recap what they read.",
              style: LumiType.caption.copyWith(color: LumiTokens.muted),
            ),
            const SizedBox(height: LumiTokens.space4),
            TextField(
              controller: _controller,
              maxLines: 3,
              maxLength: _maxLength,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: LumiTokens.ink,
              style: LumiType.body,
              decoration: InputDecoration(
                hintText: 'e.g. What was the funniest part tonight?',
                filled: true,
                fillColor: LumiTokens.cream,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide:
                      const BorderSide(color: LumiTokens.green, width: 2),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : _useDefault,
                icon: const Icon(Icons.refresh_rounded,
                    size: 18, color: LumiTokens.muted),
                label: Text('Use default question',
                    style: LumiType.caption.copyWith(color: LumiTokens.muted)),
              ),
            ),
            const SizedBox(height: LumiTokens.space3),
            LumiPrimaryButton(
              onPressed: _saving ? null : _save,
              text: 'Save',
              icon: Icons.check_rounded,
              isFullWidth: true,
              isLoading: _saving,
              color: LumiTokens.green,
            ),
          ],
        ),
      ),
    );
  }
}
