import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/theme/lumi_spacing.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../data/models/student_model.dart';
import '../../../services/firebase_service.dart';
import 'character_grid.dart';

/// Bottom sheet that lets a parent choose a Lumi character for their child.
///
/// Shows the full [LumiCharacters.all] catalogue via [CharacterGrid]. On save,
/// writes [characterId] to the student's Firestore document and calls
/// [onChanged] with the updated [StudentModel].
///
/// Usage:
/// ```dart
/// showCharacterPicker(context, student: child,
///   onChanged: (updated) => setState(() => _child = updated));
/// ```
Future<void> showCharacterPicker(
  BuildContext context, {
  required StudentModel student,
  required void Function(StudentModel updated) onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CharacterPickerSheet(
      student: student,
      onChanged: onChanged,
    ),
  );
}

class CharacterPickerSheet extends StatefulWidget {
  final StudentModel student;
  final void Function(StudentModel updated) onChanged;

  const CharacterPickerSheet({
    super.key,
    required this.student,
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
      // Student docs live in a per-school subcollection; source the schoolId
      // from the student itself so the write targets the right path.
      await FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.student.schoolId)
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
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final canSave =
        !_saving && _selected != null && _selected != widget.student.characterId;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
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
          // Drag handle
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
            "Choose ${widget.student.firstName}'s character",
            style: LumiTextStyles.h2(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LumiSpacing.xs),
          Text(
            'Your child will see this character in the app.',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LumiSpacing.m),
          // Character grid (scrolls within the sheet if it overflows)
          Flexible(
            child: SingleChildScrollView(
              child: CharacterGrid(
                selectedId: _selected,
                onSelect: (id) => setState(() => _selected = id),
              ),
            ),
          ),
          const SizedBox(height: LumiSpacing.m),
          LumiPrimaryButton(
            onPressed: canSave ? _save : null,
            text: 'Save character',
            isLoading: _saving,
            isFullWidth: true,
            color: LumiTokens.green,
          ),
        ],
      ),
    );
  }
}
