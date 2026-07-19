import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/characters/lumi_character.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/utils/image_decode.dart';

/// Teacher management for the two per-class reading awards:
///  • Top Reader — the weekly auto award (gold Lumi, most minutes). Teacher
///    toggles it on/off and renames it; the winner is chosen server-side.
///  • Special award — a manual award (special Lumi) the teacher assigns to one
///    student at a time and removes at will.
///
/// Config (names + the auto on/off switch) lives on the class doc under
/// `settings.awards`; the award *holder* lives on the student doc
/// (`autoAward` / `manualAward`), which is what makes the award character show
/// across the app via [StudentModel.displayCharacterId].
class AwardsScreen extends StatefulWidget {
  final ClassModel classModel;

  /// Injectable for tests; defaults to the app Firestore instance.
  final FirebaseFirestore? firestore;

  const AwardsScreen({super.key, required this.classModel, this.firestore});

  @override
  State<AwardsScreen> createState() => _AwardsScreenState();
}

class _AwardsScreenState extends State<AwardsScreen> {
  late final FirebaseFirestore _fs =
      widget.firestore ?? FirebaseService.instance.firestore;
  bool _busy = false;

  DocumentReference<Map<String, dynamic>> get _classRef => _fs
      .collection('schools')
      .doc(widget.classModel.schoolId)
      .collection('classes')
      .doc(widget.classModel.id);

  // Created once (late final) so rebuilds reuse the live Firestore
  // subscriptions — the former getters built a brand-new stream per build.
  late final Stream<ClassModel> _classStream =
      _classRef.snapshots().map(ClassModel.fromFirestore).asBroadcastStream();

  late final Stream<List<StudentModel>> _rosterStream = _fs
      .collection('schools')
      .doc(widget.classModel.schoolId)
      .collection('students')
      .where('classId', isEqualTo: widget.classModel.id)
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(StudentModel.fromFirestore).toList()
        ..sort((a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase())))
      .asBroadcastStream();

  void _snack(String msg) {
    showLumiToast(
      message: msg,
      type: LumiToastType.info,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _run(Future<void> Function() action, {String? failMsg}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack(failMsg ?? 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Config writes (class doc) ──────────────────────────────────────────

  Future<void> _setTopReaderEnabled(bool enabled) => _run(
        () => _classRef.update({'settings.awards.topReader.enabled': enabled}),
      );

  Future<void> _editName({
    required String field, // 'topReader' | 'special'
    required String current,
    required String defaultName,
    required String title,
  }) async {
    final value = await _promptForName(title: title, initial: current, defaultName: defaultName);
    if (value == null) return;
    final trimmed = value.trim();
    final isDefault = trimmed.isEmpty || trimmed == defaultName;
    await _run(() => _classRef.update({
          'settings.awards.$field.name':
              isDefault ? FieldValue.delete() : trimmed,
        }));
  }

  // ── Special award holder (student docs) ────────────────────────────────

  Future<void> _assignSpecial(
      StudentModel student, List<StudentModel> roster, String awardName) async {
    String uid = '';
    try {
      uid = FirebaseService.instance.currentUser?.uid ?? '';
    } catch (_) {
      // Firebase not ready (e.g. in tests) — awardedBy stays empty.
    }
    await _run(() async {
      final batch = _fs.batch();
      final studentsCol = _fs
          .collection('schools')
          .doc(widget.classModel.schoolId)
          .collection('students');
      // Single holder per class: clear any existing manual holder first.
      for (final s in roster) {
        if (s.manualAward != null && s.id != student.id) {
          batch.update(studentsCol.doc(s.id), {'manualAward': FieldValue.delete()});
        }
      }
      batch.update(studentsCol.doc(student.id), {
        'manualAward': {
          'characterId': LumiCharacters.specialLumiId,
          'name': awardName,
          'awardedBy': uid,
          'awardedAt': FieldValue.serverTimestamp(),
        },
      });
      await batch.commit();
    });
    _snack('${student.firstName} received "$awardName".');
  }

  Future<void> _removeSpecial(StudentModel holder) async {
    await _run(() => _fs
        .collection('schools')
        .doc(widget.classModel.schoolId)
        .collection('students')
        .doc(holder.id)
        .update({'manualAward': FieldValue.delete()}));
    _snack('Special award removed.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: LumiTokens.ink),
        title: Text('Awards', style: LumiType.subhead),
      ),
      body: SafeArea(
        child: StreamBuilder<ClassModel>(
          stream: _classStream,
          initialData: widget.classModel,
          builder: (context, classSnap) {
            final cls = classSnap.data ?? widget.classModel;
            return StreamBuilder<List<StudentModel>>(
              stream: _rosterStream,
              builder: (context, rosterSnap) {
                final roster = rosterSnap.data ?? const <StudentModel>[];
                final topReaderHolder = _firstAwardHolder(roster, auto: true);
                final specialHolder = _firstAwardHolder(roster, auto: false);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    Text(cls.name,
                        style: LumiType.caption.copyWith(color: LumiTokens.muted)),
                    const SizedBox(height: 4),
                    Text('Reading awards', style: LumiType.heading),
                    const SizedBox(height: 20),
                    _topReaderSection(cls, topReaderHolder),
                    const SizedBox(height: 16),
                    _specialSection(cls, roster, specialHolder),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  StudentModel? _firstAwardHolder(List<StudentModel> roster, {required bool auto}) {
    for (final s in roster) {
      if (auto ? s.autoAward != null : s.manualAward != null) return s;
    }
    return null;
  }

  // ── Top Reader section ─────────────────────────────────────────────────

  Widget _topReaderSection(ClassModel cls, StudentModel? holder) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _awardBadge(LumiCharacters.goldLumiId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cls.topReaderName, style: LumiType.subhead),
                    Text('Weekly · most reading minutes',
                        style: LumiType.caption.copyWith(color: LumiTokens.muted)),
                  ],
                ),
              ),
              Switch(
                value: cls.topReaderEnabled,
                activeThumbColor: LumiTokens.green,
                onChanged: _busy ? null : (v) => _setTopReaderEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _editRow(
            label: 'Award name',
            value: cls.topReaderName,
            onTap: () => _editName(
              field: 'topReader',
              current: cls.topReaderName,
              defaultName: ClassModel.defaultTopReaderName,
              title: 'Top Reader award name',
            ),
          ),
          const Divider(height: 20, color: LumiTokens.rule),
          if (!cls.topReaderEnabled)
            _hint('Turn on to have the gold Lumi go automatically to the student '
                'who reads the most minutes each week. Updates every Monday.')
          else if (holder != null)
            _holderRow(holder, 'Holds it this week', null)
          else
            _hint('No Top Reader yet — the first winner is chosen at the next '
                'weekly update (Mondays).'),
        ],
      ),
    );
  }

  // ── Special award section ──────────────────────────────────────────────

  Widget _specialSection(
      ClassModel cls, List<StudentModel> roster, StudentModel? holder) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _awardBadge(LumiCharacters.specialLumiId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cls.specialAwardName, style: LumiType.subhead),
                    Text('You choose who holds it',
                        style: LumiType.caption.copyWith(color: LumiTokens.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _editRow(
            label: 'Award name',
            value: cls.specialAwardName,
            onTap: () => _editName(
              field: 'special',
              current: cls.specialAwardName,
              defaultName: ClassModel.defaultSpecialAwardName,
              title: 'Special award name',
            ),
          ),
          const Divider(height: 20, color: LumiTokens.rule),
          if (holder != null)
            _holderRow(
              holder,
              'Holds "${cls.specialAwardName}"',
              TextButton(
                onPressed: _busy ? null : () => _removeSpecial(holder),
                child: Text('Remove',
                    style: LumiType.button.copyWith(color: LumiTokens.red)),
              ),
            )
          else
            _hint('No one holds this award yet.'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || roster.isEmpty
                  ? null
                  : () => _pickStudent(roster, cls.specialAwardName),
              style: FilledButton.styleFrom(
                backgroundColor: LumiTokens.ink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                ),
              ),
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: Text(holder == null ? 'Assign award' : 'Change holder',
                  style: LumiType.button.copyWith(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared bits ────────────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(LumiTokens.space4),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(color: LumiTokens.rule),
        ),
        child: child,
      );

  Widget _awardBadge(String characterId) {
    final c = LumiCharacters.findById(characterId);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      padding: const EdgeInsets.all(4),
      child: c == null
          ? const SizedBox.shrink()
          : Image.asset(
              c.assetPath,
              fit: BoxFit.contain,
              cacheWidth: decodeCacheSize(context, 48),
            ),
    );
  }

  Widget _editRow(
      {required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(label, style: LumiType.body.copyWith(color: LumiTokens.muted)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  style: LumiType.body.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 16, color: LumiTokens.muted),
          ],
        ),
      ),
    );
  }

  Widget _holderRow(StudentModel student, String subtitle, Widget? trailing) {
    return Row(
      children: [
        StudentAvatar.fromStudent(student, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(student.fullName,
                  style: LumiType.body.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: LumiType.caption.copyWith(color: LumiTokens.muted)),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _hint(String text) => Text(
        text,
        style: LumiType.caption.copyWith(color: LumiTokens.muted, height: 1.4),
      );

  // ── Dialogs / sheets ───────────────────────────────────────────────────

  Future<String?> _promptForName(
      {required String title,
      required String initial,
      required String defaultName}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumiTokens.radiusLarge)),
        title: Text(title, style: LumiType.subhead),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          cursorColor: LumiTokens.green,
          style: LumiType.body,
          decoration: InputDecoration(
            hintText: defaultName,
            hintStyle: LumiType.body.copyWith(color: LumiTokens.muted),
            filled: true,
            fillColor: LumiTokens.cream,
            counterStyle: LumiType.caption.copyWith(color: LumiTokens.muted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              borderSide: const BorderSide(color: LumiTokens.rule),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              borderSide: const BorderSide(color: LumiTokens.green, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: LumiType.button.copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Save',
                style: LumiType.button
                    .copyWith(color: LumiTokens.green, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStudent(List<StudentModel> roster, String awardName) async {
    final chosen = await showModalBottomSheet<StudentModel>(
      context: context,
      backgroundColor: LumiTokens.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusXL)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('Give "$awardName" to', style: LumiType.subhead),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: roster
                    .map((s) => ListTile(
                          leading: StudentAvatar.fromStudent(s, size: 40),
                          title: Text(s.fullName,
                              style: LumiType.body
                                  .copyWith(fontWeight: FontWeight.w600)),
                          trailing: s.manualAward != null
                              ? const Icon(Icons.check_circle,
                                  color: LumiTokens.green, size: 20)
                              : null,
                          onTap: () => Navigator.pop(ctx, s),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) {
      await _assignSpecial(chosen, roster, awardName);
    }
  }
}
