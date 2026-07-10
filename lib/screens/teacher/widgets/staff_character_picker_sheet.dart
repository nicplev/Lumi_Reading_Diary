import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/characters/lumi_character.dart';
import '../../../core/characters/staff_lumi_character.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/theme/lumi_spacing.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../data/models/user_model.dart';
import '../../../services/firebase_service.dart';
import '../../parent/widgets/character_grid.dart';

/// Bottom sheet that lets a staff member choose their Lumi profile character.
///
/// The staff counterpart of `showCharacterPicker`. Shows the role-appropriate
/// catalogue (admins → `StaffLumiCharacters.admin`; teachers → the combined
/// `StaffLumiCharacters.teacher` grid). On save, writes [characterId] to the
/// staff member's user document and calls [onChanged] with the updated [UserModel].
Future<void> showStaffCharacterPicker(
  BuildContext context, {
  required UserModel user,
  required void Function(UserModel updated) onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StaffCharacterPickerSheet(user: user, onChanged: onChanged),
  );
}

class StaffCharacterPickerSheet extends StatefulWidget {
  final UserModel user;
  final void Function(UserModel updated) onChanged;

  const StaffCharacterPickerSheet({
    super.key,
    required this.user,
    required this.onChanged,
  });

  @override
  State<StaffCharacterPickerSheet> createState() => _StaffCharacterPickerSheetState();
}

class _StaffCharacterPickerSheetState extends State<StaffCharacterPickerSheet> {
  String? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.user.characterId;
  }

  List<LumiCharacter> get _options => widget.user.role == UserRole.schoolAdmin
      ? StaffLumiCharacters.admin
      : StaffLumiCharacters.teacher;

  Future<void> _save() async {
    final schoolId = widget.user.schoolId;
    if (_selected == null || _selected == widget.user.characterId || schoolId == null) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    try {
      // Targeted update (only characterId) so the self-update Firestore rule
      // allows it. Staff docs live in the per-school users subcollection.
      await FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('users')
          .doc(widget.user.id)
          .update({'characterId': _selected});

      widget.onChanged(widget.user.copyWith(characterId: _selected));

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showLumiToast(
          message: 'Failed to save. Please try again.',
          type: LumiToastType.error,
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
        !_saving && _selected != null && _selected != widget.user.characterId;

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
            'Choose your character',
            style: LumiTextStyles.h2(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LumiSpacing.xs),
          Text(
            'This shows on your profile.',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LumiSpacing.m),
          Flexible(
            child: SingleChildScrollView(
              child: CharacterGrid(
                characters: _options,
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
