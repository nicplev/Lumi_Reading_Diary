import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/student_link_code_model.dart';
import '../../services/parent_linking_service.dart';

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

  List<StudentModel> _students = [];
  Map<String, StudentLinkCodeModel?> _studentCodes = {};
  bool _isLoading = false;
  bool _isGeneratingAll = false;
  String? _selectedClassId;

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
      final studentsSnapshot = await _firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('students')
          .where('isActive', isEqualTo: true)
          .get();

      final students = studentsSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Load codes for each student
      final codes = await _linkingService.getCodesForStudents(
        students.map((s) => s.id).toList(),
      );

      setState(() {
        _students = students;
        _studentCodes = codes;
      });
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

  Future<void> _exportAllCodes() async {
    final codesText = _students.map((student) {
      final code = _studentCodes[student.id];
      return '${student.fullName},${code?.code ?? "No code"}';
    }).join('\n');

    await Clipboard.setData(ClipboardData(text: 'Student Name,Link Code\n$codesText'));

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
                // Stats card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
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
                              AppColors.primary,
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
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
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
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Text(
                              student.firstName[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primary,
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
                                        color: AppColors.primary
                                            .withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.primary
                                              .withOpacity(0.3),
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
                                                  color: AppColors.primary,
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
                                            code.status.toString().split('.').last,
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

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
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
