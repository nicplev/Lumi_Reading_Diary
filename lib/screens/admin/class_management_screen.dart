import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
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
        title: Text(
          'Class Management',
          style: LumiTextStyles.h3(color: AppColors.charcoal),
        ),
        iconTheme: const IconThemeData(color: AppColors.charcoal),
        actions: [
          Padding(
            padding: LumiPadding.allXS,
            child: LumiTextButton(
              onPressed: _showImportStudentsDialog,
              text: 'Import Students',
              icon: Icons.upload_file,
            ),
          ),
        ],
      ),
      floatingActionButton: LumiFab(
        onPressed: _showAddClassDialog,
        icon: Icons.add,
        label: 'Add Class',
        isExtended: true,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: AppColors.white,
            padding: LumiPadding.allS,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search classes...',
                hintStyle: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppColors.offWhite,
                border: OutlineInputBorder(
                  borderRadius: LumiBorders.large,
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
                      (classModel.yearLevel
                              ?.toLowerCase()
                              .contains(searchLower) ??
                          false);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.groups_outlined,
                          size: 100,
                          color: AppColors.charcoal.withValues(alpha: 0.3),
                        ),
                        LumiGap.s,
                        Text(
                          'No classes found',
                          style: LumiTextStyles.h3(
                            color: AppColors.charcoal.withValues(alpha: 0.6),
                          ),
                        ),
                        LumiGap.xs,
                        LumiPrimaryButton(
                          onPressed: _showAddClassDialog,
                          text: 'Create First Class',
                          icon: Icons.add,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: LumiPadding.allS,
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final classModel =
                        ClassModel.fromFirestore(filteredDocs[index]);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: LumiSpacing.xs),
      child: LumiCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.skyBlue.withValues(alpha: 0.3),
            child: Icon(
              Icons.groups,
              color: AppColors.skyBlue,
            ),
          ),
          title: Text(
            classModel.name,
            style: LumiTextStyles.bodyLarge(),
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: LumiSpacing.xs,
                  runSpacing: LumiSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (classModel.yearLevel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: LumiSpacing.xs, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.skyBlue.withValues(alpha: 0.2),
                          borderRadius: LumiBorders.small,
                        ),
                        child: Text(
                          classModel.yearLevel!,
                          style: LumiTextStyles.caption(
                            color: AppColors.skyBlue,
                          ),
                        ),
                      ),
                    Text(
                      '${classModel.studentIds.length} students',
                      style: LumiTextStyles.bodySmall(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: LumiSpacing.xs, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.teacherColor.withValues(alpha: 0.1),
                              borderRadius: LumiBorders.small,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person,
                                    size: 12, color: AppColors.teacherColor),
                                const SizedBox(width: LumiSpacing.xxs),
                                Text(
                                  validTeacherIds.length == 1
                                      ? '1 teacher'
                                      : '${validTeacherIds.length} teachers',
                                  style: LumiTextStyles.caption(
                                    color: AppColors.teacherColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: LumiSpacing.xs, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: LumiBorders.small,
                          ),
                          child: Text(
                            'No teacher assigned',
                            style: LumiTextStyles.caption(
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
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete, size: 20, color: AppColors.error),
                  const SizedBox(width: LumiSpacing.xs),
                  Text(
                    'Delete',
                    style: LumiTextStyles.body(color: AppColors.error),
                  ),
                ],
              ),
            ),
          ],
        ),
          children: [
            Padding(
              padding: LumiPadding.allS,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Class Details
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                          'Students', classModel.studentIds.length.toString()),
                      _buildStatItem('Reading Goal', '20 min'),
                      _buildStatItem(
                          'Status', classModel.isActive ? 'Active' : 'Inactive'),
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
                    LumiGap.s,
                    const Divider(),
                    LumiGap.xs,
                    Text(
                      'Assigned Teachers',
                      style: LumiTextStyles.bodyLarge(),
                    ),
                    LumiGap.xs,
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
                            final teacher =
                                UserModel.fromFirestore(snapshot.data!);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: LumiSpacing.xs),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.teacherColor
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                      teacher.fullName.isNotEmpty
                                          ? teacher.fullName[0].toUpperCase()
                                          : '?',
                                      style: LumiTextStyles.bodySmall(
                                        color: AppColors.teacherColor,
                                      ),
                                    ),
                                  ),
                                  LumiGap.xs,
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          teacher.fullName,
                                          style: LumiTextStyles.body(),
                                        ),
                                        Text(
                                          teacher.email,
                                          style: LumiTextStyles.bodySmall(
                                            color: AppColors.charcoal.withValues(alpha: 0.6),
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
                    LumiGap.s,
                    const Divider(),
                    LumiGap.xs,
                    Text(
                      'Recent Activity',
                      style: LumiTextStyles.bodyLarge(),
                    ),
                    LumiGap.xs,
                    Text(
                      'No recent activity to display',
                      style: LumiTextStyles.body(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: LumiTextStyles.h3(color: AppColors.charcoal),
        ),
        LumiGap.xxs,
        Text(
          label,
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.6),
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
        shape: LumiBorders.shapeLarge,
        title: Text('Add New Class', style: LumiTextStyles.h3()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: LumiTextStyles.body(),
              decoration: InputDecoration(
                labelText: 'Class Name',
                labelStyle: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
                hintText: 'e.g., Year 3A',
                hintStyle: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.4),
                ),
                border: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                  borderSide: const BorderSide(color: AppColors.rosePink, width: 2),
                ),
              ),
            ),
            LumiGap.s,
            TextField(
              controller: yearLevelController,
              style: LumiTextStyles.body(),
              decoration: InputDecoration(
                labelText: 'Year Level',
                labelStyle: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
                hintText: 'e.g., Year 3',
                hintStyle: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.4),
                ),
                border: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                  borderSide: const BorderSide(color: AppColors.rosePink, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiPrimaryButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'Add Class',
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
          'yearLevel': yearLevelController.text.isNotEmpty
              ? yearLevelController.text
              : null,
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
      setState(
          () {}); // This will trigger a rebuild and refresh the StreamBuilder
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
            content:
                Text('No active teachers found. Please add teachers first.'),
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
        shape: LumiBorders.shapeLarge,
        title: Text('Delete Class', style: LumiTextStyles.h3()),
        content: Text(
          'Are you sure you want to delete ${classModel.name}? This action cannot be undone.',
          style: LumiTextStyles.body(),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiTextButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'Delete',
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
      return teacher.fullName
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          teacher.email.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: LumiBorders.shapeLarge,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign Teachers to ${widget.classModel.name}',
            style: LumiTextStyles.h3(),
          ),
          LumiGap.xs,
          Text(
            '${_selectedTeacherIds.length} teacher(s) selected',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
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
              style: LumiTextStyles.body(),
              decoration: InputDecoration(
                hintText: 'Search teachers...',
                hintStyle: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppColors.offWhite,
                border: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                  borderSide: BorderSide.none,
                ),
                contentPadding: LumiPadding.allS,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            LumiGap.s,

            // Teachers list
            Expanded(
              child: _filteredTeachers.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No teachers available'
                            : 'No teachers match your search',
                        style: LumiTextStyles.body(
                          color: AppColors.charcoal.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredTeachers.length,
                      itemBuilder: (context, index) {
                        final teacher = _filteredTeachers[index];
                        final isSelected =
                            _selectedTeacherIds.contains(teacher.id);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: LumiSpacing.xs),
                          child: LumiCard(
                            showShadow: isSelected,
                            padding: EdgeInsets.zero,
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
                              tileColor: isSelected
                                  ? AppColors.teacherColor.withValues(alpha: 0.1)
                                  : AppColors.white,
                              title: Text(
                                teacher.fullName,
                                style: LumiTextStyles.body(),
                              ),
                              subtitle: Text(
                                teacher.email,
                                style: LumiTextStyles.bodySmall(
                                  color: AppColors.charcoal.withValues(alpha: 0.6),
                                ),
                              ),
                              secondary: CircleAvatar(
                                backgroundColor:
                                    AppColors.teacherColor.withValues(alpha: 0.2),
                                child: Text(
                                  teacher.fullName.isNotEmpty
                                      ? teacher.fullName[0].toUpperCase()
                                      : '?',
                                  style: LumiTextStyles.body(
                                    color: AppColors.teacherColor,
                                  ),
                                ),
                              ),
                              activeColor: AppColors.teacherColor,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        LumiTextButton(
          onPressed: () => Navigator.pop(context),
          text: 'Cancel',
        ),
        if (_selectedTeacherIds.isNotEmpty)
          LumiTextButton(
            onPressed: () {
              setState(() {
                _selectedTeacherIds.clear();
              });
            },
            text: 'Clear All',
          ),
        LumiPrimaryButton(
          onPressed: () {
            Navigator.pop(context, _selectedTeacherIds.toList());
          },
          text: 'Assign Teachers',
        ),
      ],
    );
  }
}
