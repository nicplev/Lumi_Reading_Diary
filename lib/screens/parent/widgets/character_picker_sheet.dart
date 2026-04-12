import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/characters/lumi_character.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/theme/lumi_spacing.dart';
import '../../../data/models/student_model.dart';
import '../../../services/firebase_service.dart';

/// Bottom sheet that lets a parent choose a Lumi character for their child.
///
/// Shows the full [LumiCharacters.all] catalogue as a 4-column grid.
/// On selection, writes [characterId] to the student's Firestore document and
/// calls [onChanged] with the updated [StudentModel].
///
/// Usage:
/// ```dart
/// showCharacterPicker(context, student: child, schoolId: schoolId,
///   onChanged: (updated) => setState(() => _child = updated));
/// ```
Future<void> showCharacterPicker(
  BuildContext context, {
  required StudentModel student,
  required String schoolId,
  required void Function(StudentModel updated) onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CharacterPickerSheet(
      student: student,
      schoolId: schoolId,
      onChanged: onChanged,
    ),
  );
}

class CharacterPickerSheet extends StatefulWidget {
  final StudentModel student;
  final String schoolId;
  final void Function(StudentModel updated) onChanged;

  const CharacterPickerSheet({
    super.key,
    required this.student,
    required this.schoolId,
    required this.onChanged,
  });

  @override
  State<CharacterPickerSheet> createState() => _CharacterPickerSheetState();
}

class _CharacterPickerSheetState extends State<CharacterPickerSheet> {
  String? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.student.characterId;
  }

  Future<void> _save() async {
    if (_selected == null || _selected == widget.student.characterId) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    try {
      await FirebaseService.instance.firestore
          .collection('students')
          .doc(widget.student.id)
          .update({'characterId': _selected});

      final updated = widget.student.copyWith(characterId: _selected);
      widget.onChanged(updated);

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          LumiSpacing.m, LumiSpacing.s, LumiSpacing.m, bottomPadding + LumiSpacing.m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: LumiSpacing.s),
              decoration: BoxDecoration(
                color: AppColors.charcoal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Choose a character for ${widget.student.firstName}',
            style: LumiTextStyles.h3(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LumiSpacing.s),
          Text(
            'Your child will see this character in the app.',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LumiSpacing.m),
          // Character grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: LumiCharacters.all.length,
            itemBuilder: (context, index) {
              final character = LumiCharacters.all[index];
              final isSelected = _selected == character.id;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selected = character.id);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.rosePink
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.rosePink.withValues(alpha: 0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: SvgPicture.asset(character.assetPath),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: LumiSpacing.m),
          // Save button
          FilledButton(
            onPressed: _saving || _selected == null ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.rosePink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Save',
                    style: LumiTextStyles.bodyMedium(color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }
}
