import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/student_link_code_model.dart';
import '../../services/parent_linking_service.dart';
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreDebug _firestoreDebug = FirestoreDebug();

  List<StudentModel> _students = [];
  Map<String, StudentLinkCodeModel?> _studentCodes = {};
  bool _isLoading = false;
  bool _isGeneratingAll = false;

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
          debugPrint('   ✓ Parsed student: ${student.firstName} ${student.lastName} (${doc.id})');
        } catch (e, stackTrace) {
          debugPrint('   ❌ Failed to parse student ${doc.id}: $e');
          debugPrint('   Document data: ${doc.data()}');
          debugPrint('   Stack trace: $stackTrace');
        }
      }

      debugPrint('✅ Successfully parsed ${students.length} out of ${studentsSnapshot.docs.length} students');

      // Set students first, even if loading codes fails
      setState(() {
        _students = students;
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
        debugPrint('⚠️ Failed to load link codes (students still displayed): $codeError');
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
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

  Future<void> _runDiagnostic() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Running diagnostic...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await _firestoreDebug.runFullDiagnostic(widget.user.schoolId!);

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
                    result['students']['success'] ? AppColors.success : AppColors.error,
                  ),
                  if (result['students']['students'] != null && (result['students']['students'] as List).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Student List:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...(result['students']['students'] as List).map((s) => Padding(
                      padding: const EdgeInsets.only(left: 16.0, bottom: 4),
                      child: Text(
                        '• ${s['firstName']} ${s['lastName']} (${s['studentId']})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )),
                  ],
                  const Divider(height: 24),
                  _buildDiagnosticSection(
                    'Classes in Database',
                    result['classes']['count'].toString(),
                    result['classes']['success'] ? AppColors.success : AppColors.error,
                  ),
                  if (result['classes']['classes'] != null && (result['classes']['classes'] as List).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Class List:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...(result['classes']['classes'] as List).map((c) => Padding(
                      padding: const EdgeInsets.only(left: 16.0, bottom: 4),
                      child: Text(
                        '• ${c['name']} - ${c['studentCount']} students',
                        style: Theme.of(context).textTheme.bodySmall,
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
                    result['verification']['missingCount'] > 0 ? AppColors.error : AppColors.success,
                  ),
                  if (result['verification']['missingCount'] > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
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
                          const SizedBox(height: 4),
                          Text(
                            'Some class arrays reference student IDs that don\'t have corresponding documents.',
                            style: Theme.of(context).textTheme.bodySmall,
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
                child: const Text('Close'),
              ),
              if (result['students']['count'] > 0)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _fixStudentData();
                  },
                  icon: const Icon(Icons.build),
                  label: const Text('Fix Student Data'),
                ),
              if (result['classes']['count'] > result['students']['count'])
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _cleanupClasses();
                  },
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('Clean Up Classes'),
                ),
              if (result['students']['count'] == 0)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _createTestStudent();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create Test Student'),
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
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.gray,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Creating test student...'),
              ],
            ),
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
              content: Text('Failed to create test student: ${result['error']}'),
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
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Fixing student data...'),
              ],
            ),
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
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Cleaning up classes...'),
              ],
            ),
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
    final codesText = _students.map((student) {
      final code = _studentCodes[student.id];
      return '${student.fullName},${code?.code ?? "No code"}';
    }).join('\n');

    await Clipboard.setData(
        ClipboardData(text: 'Student Name,Link Code\n$codesText'));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All codes exported to clipboard as CSV'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Parent Linking Codes'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Run Diagnostic',
            onPressed: _runDiagnostic,
          ),
          if (_students.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export All Codes',
              onPressed: _exportAllCodes,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Debug info banner (only show if no students)
                if (_students.isEmpty)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No students found in database',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Run the diagnostic to check your Firestore data structure, or import students via CSV.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _runDiagnostic,
                                icon: const Icon(Icons.bug_report),
                                label: const Text('Run Diagnostic'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms),

                // Stats card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                              AppColors.primaryBlue,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: AppColors.lightGray,
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
                            color: AppColors.lightGray,
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
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isGeneratingAll ? null : _generateAllCodes,
                        icon: _isGeneratingAll
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: const Text('Generate All Missing Codes'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms),

                // Student list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      final code = _studentCodes[student.id];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primaryBlue.withValues(alpha: 0.1),
                            child: Text(
                              student.firstName[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            student.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            code != null
                                ? 'Code: ${code.code} • ${student.parentIds.isEmpty ? "Not linked" : "${student.parentIds.length} parent(s) linked"}'
                                : 'No code generated',
                            style: TextStyle(
                              color: code != null
                                  ? AppColors.success
                                  : AppColors.gray,
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
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (code != null) ...[
                                    // Code display
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryBlue
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.primaryBlue
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            code.code,
                                            style: Theme.of(context)
                                                .textTheme
                                                .displaySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primaryBlue,
                                                  letterSpacing: 4,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Parent Link Code',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppColors.gray,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),

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
                                            code.status == LinkCodeStatus.active
                                                ? AppColors.success
                                                : AppColors.gray,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildInfoChip(
                                            'Created',
                                            _formatDate(code.createdAt),
                                            AppColors.info,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Actions
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _copyCode(code.code),
                                            icon: const Icon(Icons.copy),
                                            label: const Text('Copy'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _shareCode(student, code),
                                            icon: const Icon(Icons.share),
                                            label: const Text('Share'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _generateCode(student.id),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Generate Code'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
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
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.gray,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
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
        title: const Text('Share Link Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student: ${student.fullName}'),
            const SizedBox(height: 8),
            Text(
              'Link Code: ${code.code}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share this code with the parent to link their account to this student.',
              style: TextStyle(fontSize: 12, color: AppColors.gray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              _copyCode(code.code);
              Navigator.pop(context);
            },
            child: const Text('Copy Code'),
          ),
        ],
      ),
    );
  }
}
