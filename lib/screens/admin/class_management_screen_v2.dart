import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../services/firebase_service_v2.dart';

class ClassManagementScreenV2 extends StatefulWidget {
  final UserModel adminUser;

  const ClassManagementScreenV2({
    super.key,
    required this.adminUser,
  });

  @override
  State<ClassManagementScreenV2> createState() => _ClassManagementScreenV2State();
}

class _ClassManagementScreenV2State extends State<ClassManagementScreenV2> {
  final FirebaseServiceV2 _firebaseService = FirebaseServiceV2.instance;
  String _searchQuery = '';

  Stream<QuerySnapshot> _getClassesStream() {
    // Using new nested structure - no need for where clause!
    return _firebaseService
        .classesCollection(schoolId: widget.adminUser.schoolId)
        .orderBy('name') // Now we can use orderBy without complex indexes
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddClassDialog,
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
      ),
      body: Column(
        children: [
          // Search Bar
          CommonWidgets.buildSearchBar(
            hintText: 'Search classes...',
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
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
                  return CommonWidgets.buildEmptyState(
                    icon: Icons.groups_outlined,
                    title: 'No classes found',
                    subtitle: 'Create your first class to get started',
                    action: ElevatedButton.icon(
                      onPressed: _showAddClassDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Create First Class'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                      ),
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
            if (classModel.yearLevel != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
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
            if (classModel.teacherId.isNotEmpty) ...[
              const SizedBox(width: 8),
              const Icon(Icons.person, size: 16, color: AppColors.gray),
              const SizedBox(width: 4),
              FutureBuilder<DocumentSnapshot>(
                future: _firebaseService
                    .usersCollection(schoolId: widget.adminUser.schoolId)
                    .doc(classModel.teacherId)
                    .get(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final teacher = UserModel.fromFirestore(snapshot.data!);
                    return Text(
                      teacher.fullName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.teacherColor,
                          ),
                    );
                  }
                  return Text(
                    'Loading...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray,
                        ),
                  );
                },
              ),
            ] else ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
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
              ),
            ],
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
        await _firebaseService.createClass(
          {
            'name': nameController.text,
            'yearLevel': yearLevelController.text.isNotEmpty ? yearLevelController.text : null,
            'teacherId': null,
            'studentIds': [],
            'isActive': true,
            'readingGoalMinutes': 20,
          },
          widget.adminUser.schoolId!,
        );

        if (mounted) {
          CommonWidgets.showSuccessSnackbar(context, 'Class added successfully');
        }
      } catch (e) {
        if (mounted) {
          CommonWidgets.showErrorSnackbar(context, 'Error adding class: $e');
        }
      }
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
        // TODO: Show teacher selection dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teacher assignment coming soon')),
        );
        break;
      case 'manage_students':
        // TODO: Navigate to student management
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student management coming soon')),
        );
        break;
      case 'delete':
        await _deleteClass(classModel);
        break;
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
        await _firebaseService.deleteClass(
          classModel.id,
          widget.adminUser.schoolId!,
        );

        if (mounted) {
          CommonWidgets.showSuccessSnackbar(context, 'Class deleted successfully');
        }
      } catch (e) {
        if (mounted) {
          CommonWidgets.showErrorSnackbar(context, 'Error deleting class: $e');
        }
      }
    }
  }
}