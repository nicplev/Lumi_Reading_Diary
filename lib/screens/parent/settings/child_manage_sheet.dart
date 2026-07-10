import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/lumi/student_avatar.dart';
import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../data/models/student_link_code_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/parent_linking_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../widgets/character_picker_sheet.dart';

const _accent = LumiTokens.green;

/// Opens the per-child management sheet: change reading character, see the
/// child's guardians, and invite another guardian. [onChanged] is called with
/// the updated student after a character change so the caller can refresh its
/// list / providers.
Future<void> showChildManageSheet(
  BuildContext context, {
  required UserModel user,
  required StudentModel child,
  required void Function(StudentModel updated) onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ChildManageSheet(user: user, child: child, onChanged: onChanged),
  );
}

class _ChildManageSheet extends StatefulWidget {
  final UserModel user;
  final StudentModel child;
  final void Function(StudentModel updated) onChanged;

  const _ChildManageSheet({
    required this.user,
    required this.child,
    required this.onChanged,
  });

  @override
  State<_ChildManageSheet> createState() => _ChildManageSheetState();
}

class _ChildManageSheetState extends State<_ChildManageSheet> {
  final _linkingService = ParentLinkingService();
  late StudentModel _child = widget.child;

  void _changeCharacter() {
    showCharacterPicker(
      context,
      student: _child,
      onChanged: (updated) {
        setState(() => _child = updated);
        widget.onChanged(updated);
      },
    );
  }

  Future<void> _inviteGuardian() async {
    StudentLinkCodeModel? code;
    Object? error;
    try {
      code = await _linkingService.createCoParentInviteCode(
        studentId: _child.id,
        schoolId: _child.schoolId,
        parentUserId: widget.user.id,
      );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;

    if (code == null) {
      showLumiToast(
        message: 'Could not create invite: $error',
        type: LumiToastType.error,
      );
      return;
    }

    final inviteCode = code.code;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Invite a guardian', style: LumiType.subhead),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this code with another guardian of ${_child.firstName}. '
              'They enter it when registering for the Lumi app.',
              style: LumiType.body,
            ),
            const SizedBox(height: LumiTokens.space4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LumiTokens.space4),
              decoration: BoxDecoration(
                color: LumiTokens.tintGreen,
                borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              ),
              child: Text(
                inviteCode,
                textAlign: TextAlign.center,
                style: LumiType.subhead.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: inviteCode));
              showLumiToast(
                message: 'Code copied',
                type: LumiToastType.success,
              );
            },
            child: Text('Copy code',
                style: LumiType.body.copyWith(
                    color: _accent, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done',
                style: LumiType.body.copyWith(
                    color: LumiTokens.ink, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guardians = _child.guardianProfiles.entries.toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiTokens.radiusXL),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Padding(
              padding: const EdgeInsets.only(top: LumiTokens.space2),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LumiTokens.rule,
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
              ),
            ),
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LumiTokens.space5,
                LumiTokens.space4,
                LumiTokens.space5,
                0,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _changeCharacter,
                    child: Stack(
                      children: [
                        StudentAvatar.fromStudent(_child, size: 52),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: LumiTokens.paper, width: 2),
                            ),
                            child: const Icon(Icons.edit,
                                size: 11, color: LumiTokens.paper),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: LumiTokens.space4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_child.fullName, style: LumiType.subhead),
                        const SizedBox(height: 2),
                        Text(
                          'Level: ${_child.currentReadingLevel ?? 'Not set'}',
                          style: LumiType.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LumiTokens.space4),
            const Divider(height: 1, color: LumiTokens.rule),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(LumiTokens.space5),
                children: [
                  _ActionRow(
                    icon: Icons.face_retouching_natural,
                    label: 'Change reading character',
                    onTap: _changeCharacter,
                  ),
                  const SizedBox(height: LumiTokens.space5),
                  const _Label('Guardians'),
                  const SizedBox(height: LumiTokens.space2),
                  if (guardians.isEmpty)
                    Text(
                      'No other guardians linked yet.',
                      style: LumiType.caption,
                    )
                  else
                    ...guardians.map((e) {
                      final isMe = e.key == widget.user.id;
                      final label = e.value.relationshipLabel;
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: LumiTokens.space2),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 18, color: LumiTokens.muted),
                            const SizedBox(width: LumiTokens.space2),
                            Expanded(
                              child: Text(
                                [
                                  e.value.name,
                                  if (label != null && label.isNotEmpty)
                                    '($label)',
                                  if (isMe) '— You',
                                ].join(' '),
                                style: LumiType.body,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: LumiTokens.space3),
                  _ActionRow(
                    icon: Icons.person_add_alt_1,
                    label: 'Invite another guardian',
                    accent: true,
                    onTap: _inviteGuardian,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? _accent : LumiTokens.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(LumiTokens.space4),
        decoration: BoxDecoration(
          color: LumiTokens.cream,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: LumiTokens.space3),
            Expanded(
              child: Text(
                label,
                style: LumiType.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: LumiTokens.muted),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: LumiType.caption.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: LumiTokens.muted,
      ),
    );
  }
}
