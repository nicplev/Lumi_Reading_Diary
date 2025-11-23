import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_group_model.dart';
import '../../services/firebase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';

/// Screen for managing reading groups within a class
/// Allows teachers to organize students by ability level or interest
class ReadingGroupsScreen extends StatefulWidget {
  final ClassModel classModel;

  const ReadingGroupsScreen({
    super.key,
    required this.classModel,
  });

  @override
  State<ReadingGroupsScreen> createState() => _ReadingGroupsScreenState();
}

class _ReadingGroupsScreenState extends State<ReadingGroupsScreen> {
  bool _isLoading = true;
  List<ReadingGroupModel> _groups = [];
  List<StudentModel> _allStudents = [];
  List<StudentModel> _ungroupedStudents = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text(
          'Reading Groups',
          style: LumiTextStyles.h2(color: AppColors.white),
        ),
        backgroundColor: AppColors.rosePink,
        iconTheme: const IconThemeData(color: AppColors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
            color: AppColors.white,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.rosePink,
              ),
            )
          : RefreshIndicator(
              color: AppColors.rosePink,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: LumiPadding.allS,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildClassInfo(),
                    LumiGap.s,
                    if (_ungroupedStudents.isNotEmpty) ...[
                      _buildUngroupedStudentsCard(),
                      LumiGap.s,
                    ],
                    _buildGroupsList(),
                  ],
                ),
              ),
            ),
      floatingActionButton: LumiFab(
        onPressed: _createNewGroup,
        icon: Icons.add,
        label: 'New Group',
      ),
    );
  }

  Widget _buildClassInfo() {
    return LumiCard(
      padding: LumiPadding.allS,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.classModel.name,
            style: LumiTextStyles.h2(color: AppColors.charcoal),
          ),
          LumiGap.xs,
          Row(
            children: [
              _buildInfoChip(
                Icons.people,
                '${_allStudents.length} Students',
                AppColors.rosePink,
              ),
              LumiGap.xs,
              _buildInfoChip(
                Icons.group_work,
                '${_groups.length} Groups',
                AppColors.skyBlue,
              ),
              LumiGap.xs,
              _buildInfoChip(
                Icons.person_outline,
                '${_ungroupedStudents.length} Ungrouped',
                AppColors.warmOrange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: LumiBorders.medium,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: LumiSpacing.xxs),
          Text(
            label,
            style: LumiTextStyles.label(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildUngroupedStudentsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.warmOrange.withValues(alpha: 0.1),
        borderRadius: LumiBorders.large,
      ),
      child: LumiCard(
        padding: LumiPadding.allS,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_add, color: AppColors.warmOrange),
              LumiGap.xs,
              Text(
                'Ungrouped Students (${_ungroupedStudents.length})',
                style: LumiTextStyles.h3(color: AppColors.charcoal),
              ),
            ],
          ),
          LumiGap.xs,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ungroupedStudents.map((student) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: AppColors.warmOrange.withValues(alpha: 0.3),
                  child: Text(
                    student.firstName[0].toUpperCase(),
                    style: LumiTextStyles.bodySmall(color: AppColors.charcoal),
                  ),
                ),
                label: Text(student.fullName, style: LumiTextStyles.body(color: AppColors.charcoal)),
                onDeleted: () => _assignStudentToGroup(student),
                deleteIcon: const Icon(Icons.arrow_forward, size: 18),
              );
            }).toList(),
          ),
          LumiGap.xxs,
          Text(
            'Tap the arrow to assign students to groups',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildGroupsList() {
    if (_groups.isEmpty) {
      return LumiCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.group_work_outlined,
              size: 64,
              color: AppColors.charcoal.withValues(alpha: 0.3),
            ),
            LumiGap.s,
            Text(
              'No Reading Groups Yet',
              style: LumiTextStyles.h2(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            LumiGap.xxs,
            Text(
              'Create groups to organize students by ability level or interest',
              style: LumiTextStyles.body(
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            LumiGap.s,
            LumiPrimaryButton(
              text: 'Create First Group',
              icon: Icons.add,
              onPressed: _createNewGroup,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reading Groups',
          style: LumiTextStyles.h3(color: AppColors.charcoal),
        ),
        LumiGap.xs,
        ..._groups.map((group) => _buildGroupCard(group)),
      ],
    );
  }

  Widget _buildGroupCard(ReadingGroupModel group) {
    final studentsInGroup = _allStudents
        .where((student) => group.studentIds.contains(student.id))
        .toList();

    final color = group.color != null
        ? Color(int.parse(group.color!.replaceFirst('#', '0xFF')))
        : AppColors.rosePink;

    return Padding(
      padding: const EdgeInsets.only(bottom: LumiSpacing.xs),
      child: LumiCard(
        onTap: () => _viewGroupDetails(group, studentsInGroup),
        padding: LumiPadding.allS,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.name,
                                style: LumiTextStyles.h3(color: AppColors.charcoal),
                              ),
                            ),
                            if (group.readingLevel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha:0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: color.withValues(alpha:0.3),
                                  ),
                                ),
                                child: Text(
                                  'Level ${group.readingLevel}',
                                  style: LumiTextStyles.label(color: color),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 16,
                              color: AppColors.charcoal.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${studentsInGroup.length} students',
                              style: LumiTextStyles.bodySmall(
                                color: AppColors.charcoal.withValues(alpha: 0.6),
                              ),
                            ),
                            LumiGap.s,
                            Icon(
                              Icons.schedule,
                              size: 16,
                              color: AppColors.charcoal.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: LumiSpacing.xxs),
                            Text(
                              '${group.targetMinutes} min/day',
                              style: LumiTextStyles.bodySmall(
                                color: AppColors.charcoal.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Edit Group'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'students',
                        child: Row(
                          children: [
                            Icon(Icons.people, size: 20),
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
                              'Delete Group',
                              style: LumiTextStyles.body(color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editGroup(group);
                          break;
                        case 'students':
                          _manageGroupStudents(group, studentsInGroup);
                          break;
                        case 'delete':
                          _deleteGroup(group);
                          break;
                      }
                    },
                  ),
                ],
              ),
              if (group.description != null) ...[
                LumiGap.xxs,
                Text(
                  group.description!,
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.6),
                  ),
                ),
              ],
              if (studentsInGroup.isNotEmpty) ...[
                LumiGap.xs,
                const Divider(),
                LumiGap.xxs,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: studentsInGroup.take(5).map((student) {
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: color.withValues(alpha:0.2),
                        child: Text(
                          student.firstName[0].toUpperCase(),
                          style: LumiTextStyles.bodySmall(color: color),
                        ),
                      ),
                      label: Text(student.fullName),
                      labelStyle: LumiTextStyles.bodySmall(color: AppColors.charcoal),
                    );
                  }).toList(),
                ),
                if (studentsInGroup.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: LumiSpacing.xs),
                    child: Text(
                      '+${studentsInGroup.length - 5} more students',
                      style: LumiTextStyles.bodySmall(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ],
          ),
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      // Load students
      final studentDocs =
          await firebaseService.getStudentsInClass(widget.classModel.id);
      _allStudents =
          studentDocs.map((doc) => StudentModel.fromFirestore(doc)).toList();

      // Load groups
      final groupsSnapshot = await firebaseService.firestore
          .collection('readingGroups')
          .where('classId', isEqualTo: widget.classModel.id)
          .where('isActive', isEqualTo: true)
          .get();

      _groups = groupsSnapshot.docs
          .map((doc) => ReadingGroupModel.fromFirestore(doc))
          .toList();

      // Find ungrouped students
      final groupedStudentIds = <String>{};
      for (final group in _groups) {
        groupedStudentIds.addAll(group.studentIds);
      }

      _ungroupedStudents = _allStudents
          .where((student) => !groupedStudentIds.contains(student.id))
          .toList();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _createNewGroup() async {
    final result = await showDialog<ReadingGroupModel>(
      context: context,
      builder: (context) => _GroupFormDialog(
        classModel: widget.classModel,
      ),
    );

    if (result != null) {
      try {
        final firebaseService =
            Provider.of<FirebaseService>(context, listen: false);

        await firebaseService.firestore
            .collection('readingGroups')
            .add(result.toFirestore());

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating group: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _editGroup(ReadingGroupModel group) async {
    final result = await showDialog<ReadingGroupModel>(
      context: context,
      builder: (context) => _GroupFormDialog(
        classModel: widget.classModel,
        existingGroup: group,
      ),
    );

    if (result != null) {
      try {
        final firebaseService =
            Provider.of<FirebaseService>(context, listen: false);

        await firebaseService.firestore
            .collection('readingGroups')
            .doc(group.id)
            .update(result.toFirestore());

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating group: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteGroup(ReadingGroupModel group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text(
          'Are you sure you want to delete "${group.name}"? Students will be moved to ungrouped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final firebaseService =
            Provider.of<FirebaseService>(context, listen: false);

        await firebaseService.firestore
            .collection('readingGroups')
            .doc(group.id)
            .delete();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group deleted successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting group: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _viewGroupDetails(ReadingGroupModel group, List<StudentModel> students) {
    // Navigate to group details screen (to be implemented)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('View details for ${group.name}'),
      ),
    );
  }

  Future<void> _manageGroupStudents(
      ReadingGroupModel group, List<StudentModel> currentStudents) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _ManageStudentsDialog(
        group: group,
        allStudents: _allStudents,
        currentStudentIds: group.studentIds,
      ),
    );

    if (result != null) {
      try {
        final firebaseService =
            Provider.of<FirebaseService>(context, listen: false);

        await firebaseService.firestore
            .collection('readingGroups')
            .doc(group.id)
            .update({
          'studentIds': result,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Students updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating students: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _assignStudentToGroup(StudentModel student) async {
    if (_groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please create a group first'),
        ),
      );
      return;
    }

    final selectedGroup = await showDialog<ReadingGroupModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign to Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select a group for ${student.fullName}:'),
            LumiGap.s,
            ..._groups.map((group) {
              return ListTile(
                title: Text(group.name),
                subtitle: Text('${group.studentIds.length} students'),
                onTap: () => Navigator.of(context).pop(group),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedGroup != null) {
      try {
        final firebaseService =
            Provider.of<FirebaseService>(context, listen: false);

        final updatedStudentIds = [
          ...selectedGroup.studentIds,
          student.id,
        ];

        await firebaseService.firestore
            .collection('readingGroups')
            .doc(selectedGroup.id)
            .update({
          'studentIds': updatedStudentIds,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${student.fullName} added to ${selectedGroup.name}'),
            backgroundColor: AppColors.success,
          ),
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning student: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reading Groups Help', style: LumiTextStyles.h2(color: AppColors.charcoal)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'What are Reading Groups?',
                style: LumiTextStyles.h3(color: AppColors.charcoal),
              ),
              LumiGap.xs,
              Text(
                'Reading groups help you organize students by ability level, interest, or any other criteria. This makes it easier to:',
                style: LumiTextStyles.body(color: AppColors.charcoal),
              ),
              LumiGap.xs,
              Text('• Assign appropriate books', style: LumiTextStyles.body(color: AppColors.charcoal)),
              Text('• Set different reading targets', style: LumiTextStyles.body(color: AppColors.charcoal)),
              Text('• Track group progress', style: LumiTextStyles.body(color: AppColors.charcoal)),
              Text('• Run guided reading sessions', style: LumiTextStyles.body(color: AppColors.charcoal)),
              LumiGap.s,
              Text(
                'How to Use',
                style: LumiTextStyles.h3(color: AppColors.charcoal),
              ),
              LumiGap.xs,
              Text('1. Create groups with meaningful names', style: LumiTextStyles.body(color: AppColors.charcoal)),
              Text('2. Assign students to groups', style: LumiTextStyles.body(color: AppColors.charcoal)),
              Text('3. Set reading targets for each group', style: LumiTextStyles.body(color: AppColors.charcoal)),
              Text('4. Monitor group performance', style: LumiTextStyles.body(color: AppColors.charcoal)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}

// Dialog for creating/editing a group
class _GroupFormDialog extends StatefulWidget {
  final ClassModel classModel;
  final ReadingGroupModel? existingGroup;

  const _GroupFormDialog({
    required this.classModel,
    this.existingGroup,
  });

  @override
  State<_GroupFormDialog> createState() => _GroupFormDialogState();
}

class _GroupFormDialogState extends State<_GroupFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _readingLevelController;
  late TextEditingController _targetMinutesController;

  String? _selectedColor;

  final _colors = [
    '#2196F3', // Blue
    '#4CAF50', // Green
    '#FF9800', // Orange
    '#9C27B0', // Purple
    '#F44336', // Red
    '#00BCD4', // Cyan
    '#FFEB3B', // Yellow
    '#795548', // Brown
  ];

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existingGroup?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.existingGroup?.description ?? '');
    _readingLevelController =
        TextEditingController(text: widget.existingGroup?.readingLevel ?? '');
    _targetMinutesController = TextEditingController(
        text: widget.existingGroup?.targetMinutes.toString() ?? '20');
    _selectedColor = widget.existingGroup?.color ?? _colors[0];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _readingLevelController.dispose();
    _targetMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingGroup == null ? 'New Group' : 'Edit Group'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name *',
                  hintText: 'e.g., Advanced Readers',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              LumiGap.s,
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Brief description of this group',
                ),
                maxLines: 2,
              ),
              LumiGap.s,
              TextFormField(
                controller: _readingLevelController,
                decoration: const InputDecoration(
                  labelText: 'Reading Level (optional)',
                  hintText: 'e.g., A, B, C or 1, 2, 3',
                ),
              ),
              LumiGap.s,
              TextFormField(
                controller: _targetMinutesController,
                decoration: const InputDecoration(
                  labelText: 'Daily Target (minutes) *',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a target';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              LumiGap.s,
              Text(
                'Group Color',
                style: LumiTextStyles.bodySmall(color: AppColors.charcoal.withValues(alpha: 0.5)),
              ),
              LumiGap.xxs,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colors.map((color) {
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            Color(int.parse(color.replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveGroup,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _saveGroup() {
    if (_formKey.currentState!.validate()) {
      final group = ReadingGroupModel(
        id: widget.existingGroup?.id ?? '',
        classId: widget.classModel.id,
        schoolId: widget.classModel.schoolId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        readingLevel: _readingLevelController.text.trim().isEmpty
            ? null
            : _readingLevelController.text.trim(),
        studentIds: widget.existingGroup?.studentIds ?? [],
        color: _selectedColor,
        targetMinutes: int.parse(_targetMinutesController.text),
        createdAt: widget.existingGroup?.createdAt ?? DateTime.now(),
        createdBy: widget.existingGroup?.createdBy ?? '',
        updatedAt: DateTime.now(),
      );

      Navigator.of(context).pop(group);
    }
  }
}

// Dialog for managing students in a group
class _ManageStudentsDialog extends StatefulWidget {
  final ReadingGroupModel group;
  final List<StudentModel> allStudents;
  final List<String> currentStudentIds;

  const _ManageStudentsDialog({
    required this.group,
    required this.allStudents,
    required this.currentStudentIds,
  });

  @override
  State<_ManageStudentsDialog> createState() => _ManageStudentsDialogState();
}

class _ManageStudentsDialogState extends State<_ManageStudentsDialog> {
  late List<String> _selectedStudentIds;

  @override
  void initState() {
    super.initState();
    _selectedStudentIds = List.from(widget.currentStudentIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Manage Students - ${widget.group.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.allStudents.length,
          itemBuilder: (context, index) {
            final student = widget.allStudents[index];
            final isSelected = _selectedStudentIds.contains(student.id);

            return CheckboxListTile(
              title: Text(student.fullName),
              subtitle:
                  Text('Level: ${student.currentReadingLevel ?? "Not set"}'),
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedStudentIds.add(student.id);
                  } else {
                    _selectedStudentIds.remove(student.id);
                  }
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(_selectedStudentIds);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
