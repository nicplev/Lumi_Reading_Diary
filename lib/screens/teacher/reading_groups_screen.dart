import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_group_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_level_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';

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
  final ReadingLevelService _readingLevelService = ReadingLevelService();
  bool _isLoading = true;
  List<ReadingGroupModel> _groups = [];
  List<StudentModel> _allStudents = [];
  List<StudentModel> _ungroupedStudents = [];
  List<ReadingLevelOption> _readingLevelOptions = const [];
  bool _levelsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadReadingLevelOptions();
    _loadData();
  }

  Future<void> _loadReadingLevelOptions({bool forceRefresh = false}) async {
    try {
      final options = await _readingLevelService.loadSchoolLevels(
        widget.classModel.schoolId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _readingLevelOptions = options;
        _levelsEnabled = options.isNotEmpty;
      });
    } catch (error) {
      debugPrint('Error loading reading group level options: $error');
    }
  }

  String _formatReadingLevel(String? value) {
    if (value == null || value.trim().isEmpty) return 'Not set';
    if (_readingLevelOptions.isEmpty) return value.trim();
    return _readingLevelService.formatLevelLabel(
      value,
      options: _readingLevelOptions,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Reading Groups',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: !_levelsEnabled
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline,
                        size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    Text(
                      'Reading levels are not enabled for your school',
                      style: TeacherTypography.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Contact your school admin to enable reading levels in school settings.',
                      style: TeacherTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.teacherPrimary,
              ),
            )
          : RefreshIndicator(
              color: AppColors.teacherPrimary,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildClassInfo(),
                    const SizedBox(height: 16),
                    if (_ungroupedStudents.isNotEmpty) ...[
                      _buildUngroupedStudentsCard(),
                      const SizedBox(height: 16),
                    ],
                    _buildGroupsList(),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_reading_groups',
        onPressed: _createNewGroup,
        icon: const Icon(Icons.add),
        label: Text('New Group', style: TeacherTypography.buttonText),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
      ),
    );
  }

  Widget _buildClassInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.classModel.name, style: TeacherTypography.h2),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildInfoChip(
                Icons.people,
                '${_allStudents.length} Students',
                AppColors.teacherPrimary,
              ),
              const SizedBox(width: 8),
              _buildInfoChip(
                Icons.group_work,
                '${_groups.length} Groups',
                AppColors.skyBlue,
              ),
              const SizedBox(width: 8),
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
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TeacherTypography.caption.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildUngroupedStudentsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warmOrange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        border: Border.all(color: AppColors.warmOrange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_add, color: AppColors.warmOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Ungrouped Students (${_ungroupedStudents.length})',
                style: TeacherTypography.h3,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ungroupedStudents.map((student) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: AppColors.warmOrange.withValues(alpha: 0.3),
                  child: Text(
                    student.firstName[0].toUpperCase(),
                    style: TeacherTypography.bodySmall
                        .copyWith(color: AppColors.charcoal),
                  ),
                ),
                label:
                    Text(student.fullName, style: TeacherTypography.bodySmall),
                onDeleted: () => _assignStudentToGroup(student),
                deleteIcon: const Icon(Icons.arrow_forward, size: 18),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the arrow to assign students to groups',
            style: TeacherTypography.bodySmall
                .copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsList() {
    if (_groups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          boxShadow: TeacherDimensions.cardShadow,
        ),
        child: Column(
          children: [
            Icon(
              Icons.group_work_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No Reading Groups Yet',
              style:
                  TeacherTypography.h2.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Create groups to organize students by ability level or interest',
              style: TeacherTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _createNewGroup,
              icon: const Icon(Icons.add),
              label: Text('Create First Group',
                  style: TeacherTypography.buttonText),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teacherPrimary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reading Groups', style: TeacherTypography.h3),
        const SizedBox(height: 8),
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
        : AppColors.teacherPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _viewGroupDetails(group, studentsInGroup),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            boxShadow: TeacherDimensions.cardShadow,
          ),
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
                              child:
                                  Text(group.name, style: TeacherTypography.h3),
                            ),
                            if (group.readingLevel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(
                                      TeacherDimensions.radiusM),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  _formatReadingLevel(group.readingLevel),
                                  style: TeacherTypography.caption
                                      .copyWith(color: color),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.people,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              '${studentsInGroup.length} students',
                              style: TeacherTypography.bodySmall,
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.schedule,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              '${group.targetMinutes} min/day',
                              style: TeacherTypography.bodySmall,
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
                            const Icon(Icons.delete,
                                size: 20, color: AppColors.error),
                            const SizedBox(width: 8),
                            Text(
                              'Delete Group',
                              style: TeacherTypography.bodyMedium
                                  .copyWith(color: AppColors.error),
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
                const SizedBox(height: 4),
                Text(
                  group.description!,
                  style: TeacherTypography.bodySmall,
                ),
              ],
              if (studentsInGroup.isNotEmpty) ...[
                const SizedBox(height: 8),
                Divider(color: AppColors.divider),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: studentsInGroup.take(5).map((student) {
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.2),
                        child: Text(
                          student.firstName[0].toUpperCase(),
                          style: TeacherTypography.bodySmall
                              .copyWith(color: color),
                        ),
                      ),
                      label: Text(student.fullName),
                      labelStyle: TeacherTypography.bodySmall,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TeacherDimensions.radiusM),
                      ),
                    );
                  }).toList(),
                ),
                if (studentsInGroup.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+${studentsInGroup.length - 5} more students',
                      style: TeacherTypography.bodySmall,
                    ),
                  ),
              ],
            ],
          ),
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
        levelOptions: _readingLevelOptions,
        readingLevelService: _readingLevelService,
      ),
    );
    if (!mounted) return;

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
        levelOptions: _readingLevelOptions,
        readingLevelService: _readingLevelService,
      ),
    );
    if (!mounted) return;

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        ),
        title: Text('Delete Group', style: TeacherTypography.h3),
        content: Text(
          'Are you sure you want to delete "${group.name}"? Students will be moved to ungrouped.',
          style: TeacherTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TeacherTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('Delete',
                style: TeacherTypography.bodyMedium
                    .copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (!mounted) return;

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
        readingLevelLabelBuilder: _formatReadingLevel,
      ),
    );
    if (!mounted) return;

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        ),
        title: Text('Assign to Group', style: TeacherTypography.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select a group for ${student.fullName}:',
                style: TeacherTypography.bodyMedium),
            const SizedBox(height: 12),
            ..._groups.map((group) {
              return ListTile(
                title: Text(group.name, style: TeacherTypography.bodyMedium),
                subtitle: Text('${group.studentIds.length} students',
                    style: TeacherTypography.bodySmall),
                onTap: () => Navigator.of(context).pop(group),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: TeacherTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
    if (!mounted) return;

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        ),
        title: Text('Reading Groups Help', style: TeacherTypography.h2),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('What are Reading Groups?', style: TeacherTypography.h3),
              const SizedBox(height: 8),
              Text(
                'Reading groups help you organize students by ability level, interest, or any other criteria. This makes it easier to:',
                style: TeacherTypography.bodyMedium,
              ),
              const SizedBox(height: 8),
              ...[
                'Assign appropriate books',
                'Set different reading targets',
                'Track group progress',
                'Run guided reading sessions',
              ].map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('  \u2022  ', style: TeacherTypography.bodyMedium),
                        Expanded(
                            child: Text(item,
                                style: TeacherTypography.bodyMedium)),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              Text('How to Use', style: TeacherTypography.h3),
              const SizedBox(height: 8),
              ...[
                '1. Create groups with meaningful names',
                '2. Assign students to groups',
                '3. Set reading targets for each group',
                '4. Monitor group performance',
              ].map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(item, style: TeacherTypography.bodyMedium),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it!',
                style: TeacherTypography.bodyMedium
                    .copyWith(color: AppColors.teacherPrimary)),
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
  final List<ReadingLevelOption> levelOptions;
  final ReadingLevelService readingLevelService;

  const _GroupFormDialog({
    required this.classModel,
    required this.levelOptions,
    required this.readingLevelService,
    this.existingGroup,
  });

  @override
  State<_GroupFormDialog> createState() => _GroupFormDialogState();
}

class _GroupFormDialogState extends State<_GroupFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _targetMinutesController;

  String? _selectedColor;
  String? _selectedReadingLevel;

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
    _targetMinutesController = TextEditingController(
        text: widget.existingGroup?.targetMinutes.toString() ?? '20');
    _selectedColor = widget.existingGroup?.color ?? _colors[0];
    _selectedReadingLevel = widget.readingLevelService.normalizeLevel(
      widget.existingGroup?.readingLevel,
      options: widget.levelOptions,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _targetMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
      ),
      title: Text(
        widget.existingGroup == null ? 'New Group' : 'Edit Group',
        style: TeacherTypography.h3,
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Group Name *',
                  hintText: 'e.g., Advanced Readers',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                    borderSide: BorderSide(color: AppColors.teacherPrimary),
                  ),
                ),
                style: TeacherTypography.bodyMedium,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Brief description of this group',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                    borderSide: BorderSide(color: AppColors.teacherPrimary),
                  ),
                ),
                style: TeacherTypography.bodyMedium,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedReadingLevel,
                decoration: InputDecoration(
                  labelText: 'Reading Level (optional)',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                    borderSide: BorderSide(color: AppColors.teacherPrimary),
                  ),
                ),
                items: widget.levelOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.value,
                        child: Text(option.displayLabel),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  setState(() => _selectedReadingLevel = value);
                },
              ),
              if (_selectedReadingLevel != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() => _selectedReadingLevel = null);
                    },
                    child: const Text('Clear level'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _targetMinutesController,
                decoration: InputDecoration(
                  labelText: 'Daily Target (minutes) *',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                    borderSide: BorderSide(color: AppColors.teacherPrimary),
                  ),
                ),
                style: TeacherTypography.bodyMedium,
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
              const SizedBox(height: 12),
              Text('Group Color', style: TeacherTypography.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colors.map((color) {
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
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
          child: Text('Cancel',
              style: TeacherTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _saveGroup,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teacherPrimary,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
            ),
            elevation: 0,
          ),
          child: Text('Save', style: TeacherTypography.buttonText),
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
        readingLevel: _selectedReadingLevel,
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
  final String Function(String?)? readingLevelLabelBuilder;

  const _ManageStudentsDialog({
    required this.group,
    required this.allStudents,
    required this.currentStudentIds,
    this.readingLevelLabelBuilder,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
      ),
      title: Text('Manage Students - ${widget.group.name}',
          style: TeacherTypography.h3),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.allStudents.length,
          itemBuilder: (context, index) {
            final student = widget.allStudents[index];
            final isSelected = _selectedStudentIds.contains(student.id);

            return CheckboxListTile(
              title:
                  Text(student.fullName, style: TeacherTypography.bodyMedium),
              subtitle: Text(
                  'Level: ${widget.readingLevelLabelBuilder?.call(student.currentReadingLevel) ?? (student.currentReadingLevel ?? "Not set")}',
                  style: TeacherTypography.bodySmall),
              value: isSelected,
              activeColor: AppColors.teacherPrimary,
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
          child: Text('Cancel',
              style: TeacherTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selectedStudentIds),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teacherPrimary,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
            ),
            elevation: 0,
          ),
          child: Text('Save', style: TeacherTypography.buttonText),
        ),
      ],
    );
  }
}
