import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/student_link_code_model.dart';
import '../../services/parent_linking_service.dart';
import '../../services/parent_link_export_service.dart';
import '../../services/analytics_service.dart';
import '../../services/crash_reporting_service.dart';
import '../../utils/firestore_debug.dart';

class ParentLinkingManagementScreen extends StatefulWidget {
  final UserModel user;

  const ParentLinkingManagementScreen({
    super.key,
    required this.user,
  });

  @override
  State<ParentLinkingManagementScreen> createState() =>
      _ParentLinkingManagementScreenState();
}

class _ParentLinkingManagementScreenState
    extends State<ParentLinkingManagementScreen> {
  final ParentLinkingService _linkingService = ParentLinkingService();
  final ParentLinkExportService _exportService = ParentLinkExportService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreDebug _firestoreDebug = FirestoreDebug();

  List<StudentModel> _students = [];
  Map<String, StudentLinkCodeModel?> _studentCodes = {};
  Map<String, String> _classNamesById = {};
  bool _isLoading = false;
  bool _isGeneratingAll = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('🔍 Loading students for school: ${widget.user.schoolId}');

      final studentsSnapshot = await _firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('students')
          .get();

      debugPrint('📊 Found ${studentsSnapshot.docs.length} student documents');

      final students = <StudentModel>[];
      for (final doc in studentsSnapshot.docs) {
        try {
          final student = StudentModel.fromFirestore(doc);
          students.add(student);
          debugPrint(
              '   ✓ Parsed student: ${student.firstName} ${student.lastName} (${doc.id})');
        } catch (e, stackTrace) {
          debugPrint('   ❌ Failed to parse student ${doc.id}: $e');
          debugPrint('   Document data: ${doc.data()}');
          debugPrint('   Stack trace: $stackTrace');
        }
      }

      debugPrint(
          '✅ Successfully parsed ${students.length} out of ${studentsSnapshot.docs.length} students');

      final classesSnapshot = await _firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('classes')
          .get();
      final classNamesById = <String, String>{
        for (final doc in classesSnapshot.docs)
          doc.id: (doc.data()['name'] as String?) ?? 'Unknown Class',
      };

      // Set students first, even if loading codes fails
      setState(() {
        _students = students;
        _classNamesById = classNamesById;
      });

      debugPrint('📈 Students set in state: ${_students.length} students');

      // Try to load codes for each student
      try {
        final codes = await _linkingService.getCodesForStudents(
          students.map((s) => s.id).toList(),
        );

        debugPrint('🔗 Loaded ${codes.length} link codes');

        setState(() {
          _studentCodes = codes;
        });
      } catch (codeError, codeStackTrace) {
        debugPrint(
            '⚠️ Failed to load link codes (students still displayed): $codeError');
        debugPrint('Stack trace: $codeStackTrace');
        // Students are already set, so they'll display without codes
      }

      debugPrint('📈 Final state: ${_students.length} students loaded');
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading students: $e');
      debugPrint('Stack trace: $stackTrace');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateCode(String studentId) async {
    try {
      final code = await _linkingService.createLinkCode(
        studentId: studentId,
        schoolId: widget.user.schoolId!,
        createdBy: widget.user.id,
      );

      setState(() {
        _studentCodes[studentId] = code;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link code generated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate code: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _generateAllCodes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate All Codes'),
        content: Text(
          'This will generate link codes for ${_students.where((s) => !_studentCodes.containsKey(s.id) || _studentCodes[s.id] == null).length} students. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.teacherPrimary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const SizedBox.shrink(),
            label: const Text('Generate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isGeneratingAll = true;
    });

    try {
      final studentsWithoutCodes = _students
          .where((s) =>
              !_studentCodes.containsKey(s.id) || _studentCodes[s.id] == null)
          .toList();

      final codes = await _linkingService.generateBulkCodes(
        studentIds: studentsWithoutCodes.map((s) => s.id).toList(),
        schoolId: widget.user.schoolId!,
        createdBy: widget.user.id,
      );

      setState(() {
        _studentCodes.addAll(codes);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${codes.length} codes successfully'),
            backgroundColor: AppColors.success,
            action: SnackBarAction(
              label: 'Export CSV',
              textColor: AppColors.white,
              onPressed: _exportAllCodes,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate codes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isGeneratingAll = false;
      });
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmRevokeCode(
    StudentModel student,
    StudentLinkCodeModel code,
  ) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        ),
        title: Text('Revoke Link Code', style: TeacherTypography.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Revoke code ${code.code} for ${student.fullName}?',
              style: TeacherTypography.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Sent to wrong parent',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TeacherTypography.bodyMedium
                  .copyWith(color: AppColors.teacherPrimary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const SizedBox.shrink(),
            label: const Text('Revoke'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _linkingService.revokeCode(
      codeId: code.id,
      revokedBy: widget.user.id,
      reason: reasonController.text.trim().isEmpty
          ? null
          : reasonController.text.trim(),
    );
    AnalyticsService.instance.logParentCodeRevoked();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code revoked successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }

    await _loadStudents();
  }

  Future<void> _confirmUnlinkParent(StudentModel student) async {
    if (student.parentIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No linked parents to unlink.'),
        ),
      );
      return;
    }

    String selectedParentId = student.parentIds.first;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          ),
          title: Text('Unlink Parent', style: TeacherTypography.h3),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select parent to unlink from ${student.fullName}.',
                style: TeacherTypography.bodyMedium,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedParentId,
                items: student.parentIds
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        child: Text(id),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedParentId = value);
                },
                decoration: const InputDecoration(
                  labelText: 'Parent ID',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g. Requested by family',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TeacherTypography.bodyMedium
                    .copyWith(color: AppColors.teacherPrimary),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const SizedBox.shrink(),
              label: const Text('Unlink'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    await _linkingService.unlinkParentFromStudent(
      schoolId: widget.user.schoolId!,
      studentId: student.id,
      parentUserId: selectedParentId,
      unlinkedBy: widget.user.id,
      reason: reasonController.text.trim().isEmpty
          ? null
          : reasonController.text.trim(),
    );
    AnalyticsService.instance.logParentUnlinked();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parent unlinked successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }

    await _loadStudents();
  }

  Future<void> _runDiagnostic() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Running diagnostic...'),
            ],
          ),
        ),
      ),
    );

    try {
      final result =
          await _firestoreDebug.runFullDiagnostic(widget.user.schoolId!);

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        // Show results
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Firestore Diagnostic Results'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDiagnosticSection(
                    'Students in Database',
                    result['students']['count'].toString(),
                    result['students']['success']
                        ? AppColors.success
                        : AppColors.error,
                  ),
                  if (result['students']['students'] != null &&
                      (result['students']['students'] as List).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Student List:',
                      style: TeacherTypography.bodySmall
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    ...(result['students']['students'] as List)
                        .map((s) => Padding(
                              padding:
                                  const EdgeInsets.only(left: 8.0, bottom: 2.0),
                              child: Text(
                                '• ${s['firstName']} ${s['lastName']} (${s['studentId']})',
                                style: TeacherTypography.bodySmall,
                              ),
                            )),
                  ],
                  const Divider(height: 24),
                  _buildDiagnosticSection(
                    'Classes in Database',
                    result['classes']['count'].toString(),
                    result['classes']['success']
                        ? AppColors.success
                        : AppColors.error,
                  ),
                  if (result['classes']['classes'] != null &&
                      (result['classes']['classes'] as List).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Class List:',
                      style: TeacherTypography.bodySmall
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    ...(result['classes']['classes'] as List)
                        .map((c) => Padding(
                              padding:
                                  const EdgeInsets.only(left: 8.0, bottom: 2.0),
                              child: Text(
                                '• ${c['name']} - ${c['studentCount']} students',
                                style: TeacherTypography.bodySmall,
                              ),
                            )),
                  ],
                  const Divider(height: 24),
                  _buildDiagnosticSection(
                    'Student References in Classes',
                    result['verification']['totalReferences'].toString(),
                    AppColors.info,
                  ),
                  _buildDiagnosticSection(
                    'Existing Student Documents',
                    result['verification']['existingCount'].toString(),
                    AppColors.success,
                  ),
                  _buildDiagnosticSection(
                    'Missing Student Documents',
                    result['verification']['missingCount'].toString(),
                    result['verification']['missingCount'] > 0
                        ? AppColors.error
                        : AppColors.success,
                  ),
                  if (result['verification']['missingCount'] > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(TeacherDimensions.radiusM),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⚠️ Data Integrity Issue',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Some class arrays reference student IDs that don\'t have corresponding documents.',
                            style: TeacherTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.teacherPrimary,
                  ),
                ),
              ),
              if (result['students']['count'] > 0)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _fixStudentData();
                  },
                  child: Text(
                    'Fix Student Data',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.teacherPrimary,
                    ),
                  ),
                ),
              if (result['classes']['count'] > result['students']['count'])
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _cleanupClasses();
                  },
                  child: Text(
                    'Clean Up Classes',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.teacherPrimary,
                    ),
                  ),
                ),
              if (result['students']['count'] == 0)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _createTestStudent();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create Test Student'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teacherPrimary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusM),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Diagnostic failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildDiagnosticSection(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TeacherTypography.bodyMedium.copyWith(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            ),
            child: Text(
              value,
              style: TeacherTypography.bodyMedium.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createTestStudent() async {
    // First, get a class ID
    final classesSnapshot = await _firestore
        .collection('schools')
        .doc(widget.user.schoolId)
        .collection('classes')
        .limit(1)
        .get();

    if (classesSnapshot.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No classes found. Please create a class first.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final classId = classesSnapshot.docs.first.id;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Creating test student...'),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await _firestoreDebug.createTestStudent(
        widget.user.schoolId!,
        classId,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Test student created successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          // Reload students
          _loadStudents();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Failed to create test student: ${result['error']}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _fixStudentData() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Fixing student data...'),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await _firestoreDebug.fixStudentActiveStatus(
        widget.user.schoolId!,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (result['success']) {
          final fixedCount = result['fixedCount'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                fixedCount > 0
                    ? 'Fixed $fixedCount student(s) - set isActive to true'
                    : 'All students already have correct isActive status',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          // Reload students to reflect changes
          _loadStudents();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to fix student data: ${result['error']}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _cleanupClasses() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Cleaning up classes...'),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await _firestoreDebug.cleanupNullClasses(
        widget.user.schoolId!,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (result['success']) {
          final deletedCount = result['deletedCount'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                deletedCount > 0
                    ? 'Deleted $deletedCount empty class(es) with null names'
                    : 'No empty null-named classes to clean up',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clean up classes: ${result['error']}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _exportAllCodes() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      final rows = _students.map((student) {
        final code = _studentCodes[student.id];
        return LinkCodeExportRow(
          studentName: student.fullName,
          studentId: student.studentId ?? student.id,
          className: _classNamesById[student.classId] ?? student.classId,
          code: code?.code ?? '',
          status: code?.status.name ?? 'not_generated',
          createdAt: code != null ? _formatDate(code.createdAt) : '',
          expiresAt: code != null ? _formatDate(code.expiresAt) : '',
          linkedParentCount: student.parentIds.length,
        );
      }).toList();

      final csv = _exportService.buildCsv(rows);
      final result = await _exportService.exportCsv(
        csvContent: csv,
        fileName:
            'parent_link_codes_${DateTime.now().toIso8601String().split('T').first}.csv',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor:
                result.success ? AppColors.success : AppColors.error,
          ),
        );
      }
      if (result.success) {
        AnalyticsService.instance.logParentCodesExported(rowCount: rows.length);
        CrashReportingService.instance
            .setCustomKey('parent_link_export_rows', rows.length);
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Parent Linking Codes',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Run Diagnostic',
              onPressed: _runDiagnostic,
            ),
          if (_students.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export All Codes',
              onPressed: _isExporting ? null : _exportAllCodes,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Debug info banner (only show if no students)
                if (_students.isEmpty && kDebugMode)
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusL),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.warning,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(
                                'No students found in database',
                                style: TeacherTypography.bodyMedium.copyWith(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Run the diagnostic to check your Firestore data structure, or import students via CSV.',
                          style: TeacherTypography.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _runDiagnostic,
                                icon: const Icon(Icons.bug_report),
                                label: const Text('Run Diagnostic'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.teacherPrimary,
                                  side: const BorderSide(
                                      color: AppColors.teacherPrimary,
                                      width: 2.0),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        TeacherDimensions.radiusM),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms),

                // Stats card
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusL),
                      boxShadow: TeacherDimensions.cardShadow,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatItem(
                                'Total Students',
                                _students.length.toString(),
                                Icons.people,
                                AppColors.teacherPrimary,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: AppColors.charcoal.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              child: _buildStatItem(
                                'Codes Generated',
                                _studentCodes.values
                                    .where((c) => c != null)
                                    .length
                                    .toString(),
                                Icons.qr_code,
                                AppColors.success,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: AppColors.charcoal.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              child: _buildStatItem(
                                'Parents Linked',
                                _students
                                    .where((s) => s.parentIds.isNotEmpty)
                                    .length
                                    .toString(),
                                Icons.link,
                                AppColors.info,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                _isGeneratingAll ? null : _generateAllCodes,
                            icon: _isGeneratingAll
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome),
                            label: const Text('Generate All Missing Codes'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.teacherPrimary,
                              foregroundColor: AppColors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusM),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 500.ms),

                // Student list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      final code = _studentCodes[student.id];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(
                                TeacherDimensions.radiusL),
                            boxShadow: TeacherDimensions.cardShadow,
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.teacherPrimary
                                  .withValues(alpha: 0.1),
                              child: Text(
                                student.firstName[0].toUpperCase(),
                                style: TeacherTypography.bodyMedium.copyWith(
                                  color: AppColors.teacherPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              student.fullName,
                              style: TeacherTypography.bodyMedium
                                  .copyWith(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              code != null
                                  ? 'Code: ${code.code} • ${student.parentIds.isEmpty ? "Not linked" : "${student.parentIds.length} parent(s) linked"}'
                                  : 'No code generated',
                              style: TeacherTypography.bodySmall.copyWith(
                                color: code != null
                                    ? AppColors.success
                                    : AppColors.charcoal.withValues(alpha: 0.6),
                              ),
                            ),
                            trailing: code != null
                                ? Icon(
                                    student.parentIds.isNotEmpty
                                        ? Icons.check_circle
                                        : Icons.pending,
                                    color: student.parentIds.isNotEmpty
                                        ? AppColors.success
                                        : AppColors.warning,
                                  )
                                : null,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (code != null) ...[
                                      // Code display
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.teacherPrimary
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                              TeacherDimensions.radiusL),
                                          border: Border.all(
                                            color: AppColors.teacherPrimary
                                                .withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              code.code,
                                              style:
                                                  TeacherTypography.h1.copyWith(
                                                color: AppColors.teacherPrimary,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 4,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Parent Link Code',
                                              style: TeacherTypography.bodySmall
                                                  .copyWith(
                                                color: AppColors.charcoal
                                                    .withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),

                                      // Code info
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildInfoChip(
                                              'Status',
                                              code.status
                                                  .toString()
                                                  .split('.')
                                                  .last,
                                              code.status ==
                                                      LinkCodeStatus.active
                                                  ? AppColors.success
                                                  : AppColors.charcoal
                                                      .withValues(alpha: 0.6),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Expanded(
                                            child: _buildInfoChip(
                                              'Created',
                                              _formatDate(code.createdAt),
                                              AppColors.info,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),

                                      // Actions
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _copyCode(code.code),
                                              icon: const Icon(Icons.copy),
                                              label: const Text('Copy'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.teacherPrimary,
                                                side: const BorderSide(
                                                    color: AppColors
                                                        .teacherPrimary,
                                                    width: 2.0),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          TeacherDimensions
                                                              .radiusM),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _shareCode(student, code),
                                              icon: const Icon(Icons.share),
                                              label: const Text('Share'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.teacherPrimary,
                                                side: const BorderSide(
                                                    color: AppColors
                                                        .teacherPrimary,
                                                    width: 2.0),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          TeacherDimensions
                                                              .radiusM),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _confirmRevokeCode(
                                                      student, code),
                                              icon: const Icon(Icons.block),
                                              label: const Text('Revoke'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.error,
                                                side: const BorderSide(
                                                    color: AppColors.error,
                                                    width: 2.0),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          TeacherDimensions
                                                              .radiusM),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: student
                                                      .parentIds.isEmpty
                                                  ? null
                                                  : () => _confirmUnlinkParent(
                                                      student),
                                              icon: const Icon(Icons.link_off),
                                              label:
                                                  const Text('Unlink Parent'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.teacherPrimary,
                                                side: const BorderSide(
                                                    color: AppColors
                                                        .teacherPrimary,
                                                    width: 2.0),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          TeacherDimensions
                                                              .radiusM),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else ...[
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () =>
                                              _generateCode(student.id),
                                          icon: const Icon(Icons.add),
                                          label: const Text('Generate Code'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppColors.teacherPrimary,
                                            foregroundColor: AppColors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      TeacherDimensions
                                                          .radiusM),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: (index * 50).ms);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TeacherTypography.h1.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TeacherTypography.bodySmall.copyWith(
            color: AppColors.charcoal.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TeacherTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: TeacherTypography.bodySmall.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _shareCode(StudentModel student, StudentLinkCodeModel code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        ),
        title: Text('Share Link Code', style: TeacherTypography.h2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student: ${student.fullName}',
                style: TeacherTypography.bodyMedium),
            const SizedBox(height: 4),
            Text(
              'Link Code: ${code.code}',
              style: TeacherTypography.bodyLarge
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code with the parent to link their account to this student.',
              style: TeacherTypography.bodySmall.copyWith(
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.teacherPrimary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _copyCode(code.code);
              Navigator.pop(context);
            },
            icon: const SizedBox.shrink(),
            label: const Text('Copy Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
