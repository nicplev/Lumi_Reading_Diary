import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/lumi/student_avatar.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/firebase_service.dart';
import '../../../services/isbn_assignment_service.dart';
import '../../../services/kiosk_pin_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'kiosk_pin_dialogs.dart';
import 'kiosk_scan_session_screen.dart';

/// In-classroom kiosk roster. A teacher launches this on a shared iPad for one
/// class; each student taps their own name to open a scan session, scans their
/// books for the week, and returns here. This is an *additional* way to build
/// the same weekly allocations the teacher scanner produces — it does not
/// replace any existing teacher allocation flow.
class ClassroomKioskScreen extends StatefulWidget {
  const ClassroomKioskScreen({
    super.key,
    required this.teacher,
    required this.classModel,
  });

  final UserModel teacher;
  final ClassModel classModel;

  @override
  State<ClassroomKioskScreen> createState() => _ClassroomKioskScreenState();
}

class _ClassroomKioskScreenState extends State<ClassroomKioskScreen> {
  final IsbnAssignmentService _service = IsbnAssignmentService();

  /// Student ids that already have a scan allocation for the current week —
  /// used to show a "done" tick on the roster.
  Set<String> _scannedThisWeek = <String>{};

  String get _schoolId => widget.teacher.schoolId ?? '';

  @override
  void initState() {
    super.initState();
    // The app is globally locked to portrait (main.dart); a classroom iPad on a
    // stand is usually landscape, so unlock all orientations while the kiosk is
    // open and restore portrait on exit.
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _loadScannedThisWeek();
    // Offer the optional exit PIN once, after the first frame (the teacher is
    // present at launch — that's the moment to lock the kiosk down).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferExitPin());
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    super.dispose();
  }

  String get _teacherId => widget.teacher.id;

  /// One-time launch offer to set an exit PIN (skippable; manageable later via
  /// the lock button in the app bar).
  Future<void> _maybeOfferExitPin() async {
    final pins = KioskPinService.instance;
    if (await pins.hasPin(_teacherId) || await pins.wasOffered(_teacherId)) {
      return;
    }
    await pins.markOffered(_teacherId);
    if (!mounted) return;

    final wantsPin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lock the kiosk with a PIN?', style: LumiType.subhead),
        content: Text(
          'Without a PIN, a student can tap Exit and land in your teacher '
          'account. A $kKioskPinLength-digit exit PIN keeps the kiosk locked '
          'to this screen. You can set or change it later with the lock '
          'button up top.',
          style: LumiType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Not now',
                style: LumiType.button.copyWith(color: LumiTokens.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Set PIN', style: LumiType.button),
          ),
        ],
      ),
    );
    if (wantsPin != true || !mounted) return;

    final pin = await showKioskPinSetupDialog(context);
    if (pin != null) {
      await pins.setPin(_teacherId, pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exit PIN set for this device')),
        );
      }
    }
  }

  /// Set / change / remove the exit PIN. Changing or removing always requires
  /// the current PIN first. (Setting a first PIN is deliberately open — the
  /// worst a mischievous student can do is lock the kiosk, which the teacher
  /// recovers from via Forgot PIN → sign out.)
  Future<void> _manageExitPin() async {
    final pins = KioskPinService.instance;
    final current = await pins.getPin(_teacherId);
    if (!mounted) return;

    if (current == null) {
      final pin = await showKioskPinSetupDialog(context);
      if (pin != null) {
        await pins.setPin(_teacherId, pin);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exit PIN set for this device')),
          );
        }
      }
      return;
    }

    final entry = await showKioskPinEntryDialog(
      context,
      correctPin: current,
      title: 'Enter current PIN',
      subtitle: 'Manage the exit PIN for this device.',
    );
    if (entry != KioskPinEntryResult.verified || !mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Exit PIN', style: LumiType.subhead),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'change'),
            child: Text('Change PIN', style: LumiType.body),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: Text('Remove PIN',
                style: LumiType.body.copyWith(color: LumiTokens.red)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: LumiType.body.copyWith(color: LumiTokens.muted)),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (action == 'change') {
      final pin = await showKioskPinSetupDialog(context);
      if (pin != null) await pins.setPin(_teacherId, pin);
    } else if (action == 'remove') {
      await pins.clearPin(_teacherId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exit PIN removed')),
        );
      }
    }
  }

  /// Forgot-PIN recovery: signing out is the only way past a lost PIN — safe,
  /// because signing back in needs the teacher's credentials.
  Future<void> _forgotPinSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out to reset?', style: LumiType.subhead),
        content: Text(
          "Signing out removes this device's exit PIN and returns to the "
          "login screen. You'll need your password to sign back in.",
          style: LumiType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: LumiType.button),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: LumiTokens.red,
              foregroundColor: LumiTokens.paper,
            ),
            child: Text('Sign Out', style: LumiType.button),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await KioskPinService.instance.clearPin(_teacherId);
    await FirebaseService.instance.signOut();
    if (mounted) context.go('/auth/login');
  }

  Future<void> _confirmExit() async {
    // With a PIN set, the PIN itself is the exit gate.
    final pin = await KioskPinService.instance.getPin(_teacherId);
    if (!mounted) return;
    if (pin != null) {
      final result = await showKioskPinEntryDialog(
        context,
        correctPin: pin,
        title: 'Enter PIN to exit',
        subtitle: 'This returns to the teacher app.',
        allowForgot: true,
      );
      if (!mounted) return;
      if (result == KioskPinEntryResult.verified) {
        Navigator.of(context).pop();
      } else if (result == KioskPinEntryResult.forgot) {
        await _forgotPinSignOut();
      }
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exit scan-in?', style: LumiType.subhead),
        content: Text(
          'This returns to the teacher app. Students should not normally leave '
          'this screen.',
          style: LumiType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Stay', style: LumiType.button),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: LumiTokens.red,
              foregroundColor: LumiTokens.paper,
            ),
            child: Text('Exit', style: LumiType.button),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _loadScannedThisWeek() async {
    if (_schoolId.isEmpty) return;
    try {
      final ids = await _service.getAssignedStudentIdsForWeek(
        schoolId: _schoolId,
        classId: widget.classModel.id,
        referenceDate: DateTime.now(),
      );
      if (mounted) setState(() => _scannedThisWeek = ids);
    } catch (_) {
      // Non-critical — the tick is a nicety, not required to scan.
    }
  }

  Future<void> _openSession(StudentModel student) async {
    await Navigator.of(context).push(
      MaterialPageRoute<int>(
        builder: (_) => KioskScanSessionScreen(
          teacher: widget.teacher,
          classModel: widget.classModel,
          student: student,
        ),
      ),
    );
    // Refresh ticks after returning from a session.
    await _loadScannedThisWeek();
  }

  @override
  Widget build(BuildContext context) {
    // Lock the kiosk in: intercept system back so students can't drop into the
    // teacher app by accident; exit goes through the confirm dialog.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: LumiTokens.cream,
        appBar: AppBar(
          backgroundColor: LumiTokens.cream,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text('${widget.classModel.name} • Scan-in',
              style: LumiType.subhead),
          actions: [
            IconButton(
              tooltip: 'Exit PIN',
              icon: const Icon(Icons.lock_outline_rounded),
              onPressed: _manageExitPin,
            ),
            IconButton(
              tooltip: 'Exit kiosk',
              icon: const Icon(Icons.close_rounded),
              onPressed: _confirmExit,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  children: [
                    Text(
                      'Find your name',
                      style: LumiType.heading,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap your photo to scan your books for the week',
                      style: LumiType.body.copyWith(color: LumiTokens.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildRoster()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoster() {
    if (_schoolId.isEmpty) {
      return Center(
        child: Text('Missing school for this teacher.', style: LumiType.caption),
      );
    }
    final query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolId)
        .collection('students')
        .where('classId', isEqualTo: widget.classModel.id);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load students.', style: LumiType.caption),
          );
        }
        final students = (snapshot.data?.docs ?? [])
            .map(StudentModel.fromFirestore)
            .where((s) => s.isActive)
            .toList()
          ..sort((a, b) => a.firstName
              .toLowerCase()
              .compareTo(b.firstName.toLowerCase()));

        if (students.isEmpty) {
          return Center(
            child: Text('No students in this class yet.',
                style: LumiType.caption),
          );
        }

        final doneCount =
            students.where((s) => _scannedThisWeek.contains(s.id)).length;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                _buildProgressHeader(doneCount, students.length),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final student = students[index];
                      return _StudentTile(
                        student: student,
                        scannedThisWeek: _scannedThisWeek.contains(student.id),
                        onTap: () => _openSession(student),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Teacher "who's left" summary: a count + progress bar for the week. Students
  /// who've scanned get a tick and are dimmed on the grid, so the names that
  /// still need to scan stand out.
  Widget _buildProgressHeader(int done, int total) {
    final remaining = total - done;
    final fraction = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$done of $total scanned this week',
                  style: LumiType.caption),
              Text(
                remaining == 0 ? 'All done 🎉' : '$remaining to go',
                style: LumiType.caption.copyWith(
                  color: remaining == 0 ? LumiTokens.green : LumiTokens.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: LumiTokens.rule,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(LumiTokens.green),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.student,
    required this.scannedThisWeek,
    required this.onTap,
  });

  final StudentModel student;
  final bool scannedThisWeek;
  final VoidCallback onTap;

  /// First name + last initial so two kids with the same first name (every
  /// class has two Jacks) can tell which tile is theirs.
  String get _displayName {
    final last = student.lastName.trim();
    return last.isEmpty ? student.firstName : '${student.firstName} ${last[0]}.';
  }

  @override
  Widget build(BuildContext context) {
    // Dim students who've already scanned so the names still to go stand out
    // (the teacher's "who's left" at a glance).
    return Opacity(
      opacity: scannedThisWeek ? 0.55 : 1.0,
      child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Material(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
              border: Border.all(
                color: scannedThisWeek ? LumiTokens.green : LumiTokens.rule,
                width: scannedThisWeek ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    StudentAvatar.fromStudent(student, size: 84),
                  if (scannedThisWeek)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: LumiTokens.green,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.check_rounded,
                            size: 16, color: LumiTokens.paper),
                      ),
                    ),
                ],
              ),
                const SizedBox(height: 10),
                Text(
                  _displayName,
                  style: LumiType.body.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
