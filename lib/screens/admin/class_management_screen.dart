import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../services/firebase_service.dart';
import 'csv_import_dialog.dart';

class ClassManagementScreen extends StatefulWidget {
  final UserModel adminUser;

  const ClassManagementScreen({
    super.key,
    required this.adminUser,
  });

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  String _searchQuery = '';

  Stream<QuerySnapshot> _getClassesStream() {
    // Using nested structure - no need for schoolId filter!
    return _firebaseService.firestore
        .collection('schools')
        .doc(widget.adminUser.schoolId)
        .collection('classes')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Class Management',
          style: TextStyle(color: AppColors.darkGray),
        ),
        iconTheme: const IconThemeData(color: AppColors.darkGray),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _showImportStudentsDialog,
              icon: const Icon(Icons.upload_file, color: AppColors.primaryBlue),
              label: const Text(
                'Import Students',
                style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'class_management_fab',
        onPressed: _showAddClassDialog,
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search classes...',
                prefixIcon: const Icon(Icons.search, color: AppColors.gray),
                filled: true,
                fillColor: AppColors.offWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          // Classes List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getClassesStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                final filteredDocs = docs.where((doc) {
                  final classModel = ClassModel.fromFirestore(doc);
                  final searchLower = _searchQuery.toLowerCase();
                  return classModel.name.toLowerCase().contains(searchLower) ||
                      (classModel.yearLevel?.toLowerCase().contains(searchLower) ?? false);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.groups_outlined,
                          size: 100,
                          color: AppColors.gray.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No classes found',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppColors.gray,
                              ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _showAddClassDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Create First Class'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final classModel = ClassModel.fromFirestore(filteredDocs[index]);
                    return _buildClassCard(classModel);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassCard(ClassModel classModel) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.secondaryPurple.withOpacity(0.2),
          child: const Icon(
            Icons.groups,
            color: AppColors.secondaryPurple,
          ),
        ),
        title: Text(
          classModel.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (classModel.yearLevel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        classModel.yearLevel!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  Text(
                    '${classModel.studentIds.length} students',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray,
                        ),
                  ),
                  // Display assigned teachers
                  Builder(
                    builder: (context) {
                      // Filter out empty teacher IDs
                      final validTeacherIds = classModel.teacherIds
                          .where((id) => id.isNotEmpty)
                          .toList();

                      if (validTeacherIds.isNotEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.teacherColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person, size: 12, color: AppColors.teacherColor),
                              const SizedBox(width: 4),
                              Text(
                                validTeacherIds.length == 1
                                    ? '1 teacher'
                                    : '${validTeacherIds.length} teachers',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.teacherColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'No teacher assigned',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleClassAction(value, classModel),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'assign_teacher',
              child: Row(
                children: [
                  Icon(Icons.person_add, size: 20),
                  SizedBox(width: 8),
                  Text('Assign Teacher'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'manage_students',
              child: Row(
                children: [
                  Icon(Icons.group, size: 20),
                  SizedBox(width: 8),
                  Text('Manage Students'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Class Details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('Students', classModel.studentIds.length.toString()),
                    _buildStatItem('Reading Goal', '20 min'),
                    _buildStatItem('Status', classModel.isActive ? 'Active' : 'Inactive'),
                  ],
                ),

                // Assigned Teachers Section
                ...(() {
                  // Filter out empty teacher IDs
                  final validTeacherIds = classModel.teacherIds
                      .where((id) => id.isNotEmpty)
                      .toList();

                  if (validTeacherIds.isEmpty) {
                    return <Widget>[];
                  }

                  return <Widget>[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Assigned Teachers',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...validTeacherIds.map((teacherId) {
                      return FutureBuilder<DocumentSnapshot>(
                        future: _firebaseService.firestore
                            .collection('schools')
                            .doc(widget.adminUser.schoolId)
                            .collection('users')
                            .doc(teacherId)
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final teacher = UserModel.fromFirestore(snapshot.data!);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.teacherColor.withValues(alpha: 0.2),
                                    child: Text(
                                      teacher.fullName.isNotEmpty
                                          ? teacher.fullName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: AppColors.teacherColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          teacher.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          teacher.email,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.gray,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    }),
                  ];
                }()),

                if (classModel.studentIds.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Recent Activity',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No recent activity to display',
                    style: TextStyle(color: AppColors.gray),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.darkGray,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.gray,
          ),
        ),
      ],
    );
  }

  Future<void> _showAddClassDialog() async {
    final nameController = TextEditingController();
    final yearLevelController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Class'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Class Name',
                hintText: 'e.g., Year 3A',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: yearLevelController,
              decoration: const InputDecoration(
                labelText: 'Year Level',
                hintText: 'e.g., Year 3',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Add Class'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('classes')
            .add({
          'name': nameController.text,
          'yearLevel': yearLevelController.text.isNotEmpty ? yearLevelController.text : null,
          'teacherId': '',
          'studentIds': [],
          'isActive': true,
          'readingGoalMinutes': 20,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Class added successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding class: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _showImportStudentsDialog() async {
    if (widget.adminUser.schoolId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: School ID not found'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CSVImportDialog(
        schoolId: widget.adminUser.schoolId!,
      ),
    );

    // Refresh the class list if students were imported
    if (result == true && mounted) {
      setState(() {}); // This will trigger a rebuild and refresh the StreamBuilder
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Students imported successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _handleClassAction(String action, ClassModel classModel) async {
    switch (action) {
      case 'edit':
        // TODO: Navigate to edit class screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Edit functionality coming soon')),
        );
        break;
      case 'assign_teacher':
        await _showAssignTeacherDialog(classModel);
        break;
      case 'manage_students':
        context.push('/admin/student-management', extra: widget.adminUser);
        break;
      case 'delete':
        await _deleteClass(classModel);
        break;
    }
  }

  Future<void> _showAssignTeacherDialog(ClassModel classModel) async {
    // Fetch all teachers in the school
    final teachersSnapshot = await _firebaseService.firestore
        .collection('schools')
        .doc(widget.adminUser.schoolId)
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('isActive', isEqualTo: true)
        .get();

    final teachers = teachersSnapshot.docs
        .map((doc) => UserModel.fromFirestore(doc))
        .toList();

    if (teachers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active teachers found. Please add teachers first.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    // Show dialog with multi-select for teachers
    final selectedTeachers = await showDialog<List<String>>(
      context: context,
      builder: (context) => _AssignTeachersDialog(
        classModel: classModel,
        teachers: teachers,
        currentTeacherIds: classModel.teacherIds,
      ),
    );

    if (selectedTeachers != null) {
      try {
        // Update the class with new teacher assignments
        final updatedClass = classModel.copyWith(
          teacherIds: selectedTeachers,
          teacherId: selectedTeachers.isNotEmpty ? selectedTeachers.first : '',
        );

        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('classes')
            .doc(classModel.id)
            .update(updatedClass.toFirestore());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                selectedTeachers.isEmpty
                    ? 'Teachers removed from ${classModel.name}'
                    : '${selectedTeachers.length} teacher(s) assigned to ${classModel.name}',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error assigning teachers: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteClass(ClassModel classModel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Class'),
        content: Text('Are you sure you want to delete ${classModel.name}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('classes')
            .doc(classModel.id)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Class deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting class: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

// Teacher Assignment Dialog Widget
class _AssignTeachersDialog extends StatefulWidget {
  final ClassModel classModel;
  final List<UserModel> teachers;
  final List<String> currentTeacherIds;

  const _AssignTeachersDialog({
    required this.classModel,
    required this.teachers,
    required this.currentTeacherIds,
  });

  @override
  State<_AssignTeachersDialog> createState() => _AssignTeachersDialogState();
}

class _AssignTeachersDialogState extends State<_AssignTeachersDialog> {
  late Set<String> _selectedTeacherIds;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedTeacherIds = Set<String>.from(widget.currentTeacherIds);
  }

  List<UserModel> get _filteredTeachers {
    if (_searchQuery.isEmpty) return widget.teachers;
    return widget.teachers.where((teacher) {
      return teacher.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          teacher.email.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assign Teachers to ${widget.classModel.name}'),
          const SizedBox(height: 8),
          Text(
            '${_selectedTeacherIds.length} teacher(s) selected',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray,
                ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // Search bar
            TextField(
              decoration: InputDecoration(
                hintText: 'Search teachers...',
                prefixIcon: const Icon(Icons.search, color: AppColors.gray),
                filled: true,
                fillColor: AppColors.offWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Teachers list
            Expanded(
              child: _filteredTeachers.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No teachers available'
                            : 'No teachers match your search',
                        style: const TextStyle(color: AppColors.gray),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredTeachers.length,
                      itemBuilder: (context, index) {
                        final teacher = _filteredTeachers[index];
                        final isSelected = _selectedTeacherIds.contains(teacher.id);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: isSelected ? 2 : 0,
                          color: isSelected
                              ? AppColors.teacherColor.withValues(alpha: 0.1)
                              : AppColors.white,
                          child: CheckboxListTile(
                            value: isSelected,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  _selectedTeacherIds.add(teacher.id);
                                } else {
                                  _selectedTeacherIds.remove(teacher.id);
                                }
                              });
                            },
                            title: Text(
                              teacher.fullName,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              teacher.email,
                              style: const TextStyle(fontSize: 12),
                            ),
                            secondary: CircleAvatar(
                              backgroundColor:
                                  AppColors.teacherColor.withValues(alpha: 0.2),
                              child: Text(
                                teacher.fullName.isNotEmpty
                                    ? teacher.fullName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: AppColors.teacherColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            activeColor: AppColors.teacherColor,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_selectedTeacherIds.isNotEmpty)
          TextButton(
            onPressed: () {
              setState(() {
                _selectedTeacherIds.clear();
              });
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear All'),
          ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, _selectedTeacherIds.toList());
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teacherColor,
          ),
          child: const Text('Assign Teachers'),
        ),
      ],
    );
  }
}