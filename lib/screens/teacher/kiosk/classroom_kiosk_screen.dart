import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
    _loadScannedThisWeek();
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
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.cream,
        elevation: 0,
        title: Text('${widget.classModel.name} • Scan-in', style: LumiType.subhead),
        actions: [
          IconButton(
            tooltip: 'Exit kiosk',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'Tap your name to scan your books for the week',
                style: LumiType.body,
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(child: _buildRoster()),
          ],
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

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.82,
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
        );
      },
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

  @override
  Widget build(BuildContext context) {
    return Material(
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
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  StudentAvatar.fromStudent(student, size: 72),
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
                student.firstName,
                style: LumiType.body.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
