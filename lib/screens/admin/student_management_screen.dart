import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../data/models/student_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import 'csv_import_dialog.dart';

class StudentManagementScreen extends StatefulWidget {
  final ClassModel classModel;
  final UserModel adminUser;

  const StudentManagementScreen({
    super.key,
    required this.classModel,
    required this.adminUser,
  });

  @override
  State<StudentManagementScreen> createState() => _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name', 'level', 'id'

  Stream<QuerySnapshot> _getStudentsStream() {
    return _firebaseService.firestore
        .collection('schools')
        .doc(widget.adminUser.schoolId)
        .collection('students')
        .where('classId', isEqualTo: widget.classModel.id)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  void _sortStudents(List<StudentModel> students) {
    switch (_sortBy) {
      case 'name':
        students.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case 'level':
        students.sort((a, b) {
          final aLevel = a.currentReadingLevel ?? '';
          final bLevel = b.currentReadingLevel ?? '';
          return aLevel.compareTo(bLevel);
        });
        break;
      case 'id':
        students.sort((a, b) {
          final aId = a.studentId ?? '';
          final bId = b.studentId ?? '';
          return aId.compareTo(bId);
        });
        break;
    }
  }

  List<StudentModel> _filterStudents(List<StudentModel> students) {
    if (_searchQuery.isEmpty) return students;

    return students.where((student) {
      final nameLower = student.fullName.toLowerCase();
      final idLower = student.studentId?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return nameLower.contains(query) || idLower.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: Text(
          '${widget.classModel.name} - Students',
          style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file, color: AppColors.white),
            onPressed: _showCSVImportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.person_add, color: AppColors.white),
            onPressed: _showAddStudentDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() => _sortBy = value);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'name' ? Icons.check : Icons.sort_by_alpha,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Name'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'id',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'id' ? Icons.check : Icons.numbers,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Student ID'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'level',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'level' ? Icons.check : Icons.bar_chart,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Reading Level'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or student ID...',
                hintStyle: TeacherTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TeacherTypography.bodyMedium,
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Student List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getStudentsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Error loading students',
                          style: TeacherTypography.h3,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          snapshot.error.toString(),
                          style: TeacherTypography.bodyMedium.copyWith(
                            color: AppColors.charcoal.withValues(alpha: 0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
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

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.teacherPrimary),
                  );
                }

                var students = snapshot.data!.docs
                    .map((doc) => StudentModel.fromFirestore(doc))
                    .toList();

                students = _filterStudents(students);
                _sortStudents(students);

                if (students.isEmpty) {
                  if (_searchQuery.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: AppColors.charcoal.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No results found',
                            style: TeacherTypography.h3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: TeacherTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 64,
                          color: AppColors.charcoal.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No students yet',
                          style: TeacherTypography.h3,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add students to ${widget.classModel.name} to get started',
                          style: TeacherTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _showAddStudentDialog,
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add Student'),
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

                return Column(
                  children: [
                    // Student Count Header
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: AppColors.white,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people,
                            color: AppColors.teacherPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${students.length} ${students.length == 1 ? 'Student' : 'Students'}',
                            style: TeacherTypography.bodyLarge.copyWith(color: AppColors.charcoal),
                          ),
                        ],
                      ),
                    ),

                    // Student List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          return _buildStudentCard(students[index]);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_student_management',
        onPressed: _showAddStudentDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Student'),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
      ),
    );
  }

  Widget _buildStudentCard(StudentModel student) {
    final initials = student.fullName.isNotEmpty
        ? student.fullName
            .split(' ')
            .take(2)
            .map((word) => word.isNotEmpty ? word[0].toUpperCase() : '')
            .join()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          boxShadow: TeacherDimensions.cardShadow,
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 25,
              backgroundColor: AppColors.teacherPrimary.withValues(alpha: 0.1),
              child: Text(
                initials,
                style: TextStyle(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 50 * 0.4,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Student Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.fullName,
                    style: TeacherTypography.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  if (student.studentId != null && student.studentId!.isNotEmpty)
                    Text(
                      'ID: ${student.studentId}',
                      style: TeacherTypography.bodyMedium.copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (student.currentReadingLevel != null &&
                          student.currentReadingLevel!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4.0,
                            vertical: 2.0,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.skyBlue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(TeacherDimensions.radiusS),
                            border: Border.all(
                              color: AppColors.skyBlue.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.book,
                                size: 14,
                                color: AppColors.skyBlue,
                              ),
                              const SizedBox(width: 2.0),
                              Text(
                                student.currentReadingLevel!,
                                style: TeacherTypography.bodySmall.copyWith(
                                  color: AppColors.skyBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (student.dateOfBirth != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          'Age: ${_calculateAge(student.dateOfBirth!)}',
                          style: TeacherTypography.bodySmall.copyWith(
                            color: AppColors.charcoal.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Actions Menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppColors.charcoal.withValues(alpha: 0.6)),
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    await _showEditStudentDialog(student);
                    break;
                  case 'change_level':
                    await _showChangeReadingLevelDialog(student);
                    break;
                  case 'remove':
                    await _removeStudentFromClass(student);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('Edit Details'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'change_level',
                  child: Row(
                    children: [
                      Icon(Icons.bar_chart, size: 20),
                      SizedBox(width: 8),
                      Text('Change Reading Level'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      const Icon(Icons.remove_circle_outline, size: 20, color: AppColors.error),
                      const SizedBox(width: 4.0),
                      Text(
                        'Remove from Class',
                        style: TeacherTypography.bodyMedium.copyWith(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Future<void> _showCSVImportDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CSVImportDialog(
        schoolId: widget.adminUser.schoolId!,
      ),
    );

    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Students imported successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddStudentDialog() async {
    final studentIdController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final readingLevelController = TextEditingController();
    DateTime? selectedDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Student'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: studentIdController,
                    decoration: const InputDecoration(
                      labelText: 'Student ID *',
                      hintText: 'e.g., S12345',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().subtract(const Duration(days: 365 * 8)),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date of Birth (Optional)',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        selectedDate != null
                            ? DateFormat('yyyy-MM-dd').format(selectedDate!)
                            : 'Select date...',
                        style: TeacherTypography.bodyMedium.copyWith(
                          color: selectedDate != null
                              ? AppColors.charcoal
                              : AppColors.charcoal.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: readingLevelController,
                    decoration: const InputDecoration(
                      labelText: 'Reading Level (Optional)',
                      hintText: 'e.g., Level 5, A, etc.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (studentIdController.text.trim().isEmpty ||
                    firstNameController.text.trim().isEmpty ||
                    lastNameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in all required fields'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teacherPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Student'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _createStudent(
        studentId: studentIdController.text.trim(),
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        dateOfBirth: selectedDate,
        readingLevel: readingLevelController.text.trim(),
      );
    }
  }

  Future<void> _createStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    DateTime? dateOfBirth,
    String? readingLevel,
  }) async {
    try {
      // Check for duplicate student ID
      final existingStudent = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('students')
          .where('studentId', isEqualTo: studentId)
          .where('isActive', isEqualTo: true)
          .get();

      if (existingStudent.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Student ID $studentId already exists'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Create student document
      final studentRef = _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('students')
          .doc();

      await studentRef.set({
        'studentId': studentId,
        'firstName': firstName,
        'lastName': lastName,
        'schoolId': widget.adminUser.schoolId,
        'classId': widget.classModel.id,
        'dateOfBirth': dateOfBirth != null ? Timestamp.fromDate(dateOfBirth) : null,
        'currentReadingLevel': readingLevel ?? '',
        'parentIds': [],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'enrolledAt': FieldValue.serverTimestamp(),
        'profileImageUrl': null,
        'additionalInfo': {},
        'levelHistory': [],
        'stats': {
          'totalMinutesRead': 0,
          'totalBooksRead': 0,
          'currentStreak': 0,
          'longestStreak': 0,
          'lastReadingDate': null,
        },
      });

      // Update class's studentIds array
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('classes')
          .doc(widget.classModel.id)
          .update({
        'studentIds': FieldValue.arrayUnion([studentRef.id]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Student $firstName $lastName added successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding student: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showEditStudentDialog(StudentModel student) async {
    final studentIdController = TextEditingController(text: student.studentId);
    final firstNameController = TextEditingController(text: student.firstName);
    final lastNameController = TextEditingController(text: student.lastName);
    final readingLevelController = TextEditingController(text: student.currentReadingLevel);
    DateTime? selectedDate = student.dateOfBirth;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Student'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: studentIdController,
                    decoration: const InputDecoration(
                      labelText: 'Student ID *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 8)),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date of Birth (Optional)',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        selectedDate != null
                            ? DateFormat('yyyy-MM-dd').format(selectedDate!)
                            : 'Select date...',
                        style: TeacherTypography.bodyMedium.copyWith(
                          color: selectedDate != null
                              ? AppColors.charcoal
                              : AppColors.charcoal.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: readingLevelController,
                    decoration: const InputDecoration(
                      labelText: 'Reading Level (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (studentIdController.text.trim().isEmpty ||
                    firstNameController.text.trim().isEmpty ||
                    lastNameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in all required fields'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teacherPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _updateStudent(
        student: student,
        studentId: studentIdController.text.trim(),
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        dateOfBirth: selectedDate,
        readingLevel: readingLevelController.text.trim(),
      );
    }
  }

  Future<void> _updateStudent({
    required StudentModel student,
    required String studentId,
    required String firstName,
    required String lastName,
    DateTime? dateOfBirth,
    String? readingLevel,
  }) async {
    try {
      // Check for duplicate student ID (if changed)
      if (studentId != student.studentId) {
        final existingStudent = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('students')
            .where('studentId', isEqualTo: studentId)
            .where('isActive', isEqualTo: true)
            .get();

        if (existingStudent.docs.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Student ID $studentId already exists'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('students')
          .doc(student.id)
          .update({
        'studentId': studentId,
        'firstName': firstName,
        'lastName': lastName,
        'dateOfBirth': dateOfBirth != null ? Timestamp.fromDate(dateOfBirth) : null,
        'currentReadingLevel': readingLevel ?? '',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student updated successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating student: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showChangeReadingLevelDialog(StudentModel student) async {
    final levelController = TextEditingController(
      text: student.currentReadingLevel ?? '',
    );
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change Reading Level - ${student.fullName}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: levelController,
                decoration: const InputDecoration(
                  labelText: 'New Reading Level',
                  hintText: 'e.g., Level 6, B, etc.',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (Optional)',
                  hintText: 'Why the level changed...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (levelController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a reading level'),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update Level'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _updateReadingLevel(
        student: student,
        newLevel: levelController.text.trim(),
        reason: reasonController.text.trim(),
      );
    }
  }

  Future<void> _updateReadingLevel({
    required StudentModel student,
    required String newLevel,
    String? reason,
  }) async {
    try {
      // Create level history entry
      final levelHistory = List<Map<String, dynamic>>.from(
        student.levelHistory.map((h) => {
          'level': h.level,
          'changedAt': Timestamp.fromDate(h.changedAt),
          'changedBy': h.changedBy,
          'reason': h.reason,
        }),
      );

      levelHistory.add({
        'level': newLevel,
        'changedAt': FieldValue.serverTimestamp(),
        'changedBy': widget.adminUser.id,
        'reason': reason?.isNotEmpty == true ? reason : null,
      });

      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('students')
          .doc(student.id)
          .update({
        'currentReadingLevel': newLevel,
        'levelHistory': levelHistory,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reading level updated to $newLevel'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating reading level: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeStudentFromClass(StudentModel student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Student from Class'),
        content: Text(
          'Are you sure you want to remove ${student.fullName} from ${widget.classModel.name}?\n\nThe student will remain in the system but will not be assigned to any class.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Update student's classId to null
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('students')
            .doc(student.id)
            .update({
          'classId': null,
        });

        // Remove from class's studentIds array
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('classes')
            .doc(widget.classModel.id)
            .update({
          'studentIds': FieldValue.arrayRemove([student.id]),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${student.fullName} removed from class'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error removing student: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }
}
