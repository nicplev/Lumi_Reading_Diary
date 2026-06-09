import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../data/models/class_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';

/// Teacher-facing editor for the per-class comprehension prompt asked at the
/// end of the parent's reading-log wizard. Single string, edited anytime —
/// teachers can swap it weekly or per term for a different focus.
///
/// Writes to `schools/{schoolId}/classes/{classId}.settings.comprehensionQuestion`.
/// When the text matches the default, the field is deleted from the doc so
/// reads fall back through [ClassModel.comprehensionQuestion]'s default.
class ClassComprehensionQuestionScreen extends StatefulWidget {
  final ClassModel classModel;
  final UserModel teacher;

  const ClassComprehensionQuestionScreen({
    super.key,
    required this.classModel,
    required this.teacher,
  });

  @override
  State<ClassComprehensionQuestionScreen> createState() =>
      _ClassComprehensionQuestionScreenState();
}

class _ClassComprehensionQuestionScreenState
    extends State<ClassComprehensionQuestionScreen> {
  static const int _maxLength = 200;

  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.classModel.comprehensionQuestion);
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
    setState(() => _saving = true);
    try {
      final ref = FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.classModel.schoolId)
          .collection('classes')
          .doc(widget.classModel.id);
      final isDefault =
          trimmed == ClassModel.defaultComprehensionQuestion || trimmed.isEmpty;
      await ref.update({
        'settings.comprehensionQuestion':
            isDefault ? FieldValue.delete() : trimmed,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDefault
              ? 'Reset to the default question.'
              : 'Question updated.'),
          duration: const Duration(seconds: 2),
        ),
      );
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Comprehension Question', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LumiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.classModel.name,
                      style: LumiTextStyles.label(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The question your students will be asked at the end of '
                      'logging — a chance for them to recap what they read.',
                      style: LumiTextStyles.bodyMedium(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      maxLines: 3,
                      maxLength: _maxLength,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'e.g. What was the funniest part tonight?',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving ? null : _useDefault,
                        icon: const Icon(Icons.refresh_rounded,
                            color: AppColors.charcoal, size: 18),
                        label: Text(
                          'Use default question',
                          style: LumiTextStyles.bodyMedium(
                              color: AppColors.charcoal),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              LumiPrimaryButton(
                onPressed: _saving ? null : _save,
                text: 'Save',
                icon: Icons.check_rounded,
                isFullWidth: true,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
