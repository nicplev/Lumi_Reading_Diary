import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/lumi/student_avatar.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/isbn_assignment_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
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

  Future<void> _confirmExit() async {
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
