import 'package:flutter/material.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
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
      backgroundColor: AppColors.teacherBackground,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.charcoal,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: Text('Reading Groups', style: TeacherTypography.h3),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
            color: AppColors.textSecondary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.teacherPrimary,
              ),
            )
          : RefreshIndicator(
              color: AppColors.teacherPrimary,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildClassInfo(),
                    const SizedBox(height: 24),
                    if (_ungroupedStudents.isNotEmpty) ...[
                      _buildUngroupedStudentsCard(),
                      const SizedBox(height: 24),
                    ],
                    _buildGroupsList(),
                  ],
                ),
              ),
            ),
      floatingActionButton: _groups.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'fab_reading_groups',
              onPressed: _createNewGroup,
              icon: const Icon(Icons.add),
              label: Text('New Group', style: TeacherTypography.buttonText),
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: AppColors.white,
            )
          : null,
    );
  }

  Widget _buildClassInfo() {
    return Container(
      padding: const EdgeInsets.all(TeacherDimensions.paddingXL),
      decoration: TeacherDimensions.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.classModel.name, style: TeacherTypography.h2),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip(
                Icons.people,
                '${_allStudents.length} Students',
                AppColors.teacherPrimary,
              ),
              _buildInfoChip(
                Icons.group_work,
                '${_groups.length} Groups',
                AppColors.skyBlue,
              ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'UNGROUPED STUDENTS',
            style: TeacherTypography.sectionHeader.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(TeacherDimensions.paddingXL),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
            border:
                Border.all(color: AppColors.warmOrange.withValues(alpha: 0.3)),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_ungroupedStudents.length} students not in a group',
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.warmOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ungroupedStudents.map((student) {
                  return GestureDetector(
                    onTap: () => _assignStudentToGroup(student),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.warmOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                            TeacherDimensions.radiusRound),
                        border: Border.all(
                          color:
                              AppColors.warmOrange.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor:
                                AppColors.warmOrange.withValues(alpha: 0.2),
                            child: Text(
                              student.firstName[0].toUpperCase(),
                              style: TeacherTypography.caption.copyWith(
                                color: AppColors.warmOrange,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            student.fullName,
                            style: TeacherTypography.bodySmall.copyWith(
                              color: AppColors.charcoal,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 10,
                            color:
                                AppColors.warmOrange.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                'Tap a student to assign them to a group',
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupsList() {
    if (_groups.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'READING GROUPS',
              style: TeacherTypography.sectionHeader.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            decoration: TeacherDimensions.cardDecoration,
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.teacherPrimaryLight,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.group_work_outlined,
                      size: 40,
                      color: AppColors.teacherPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('No Reading Groups Yet', style: TeacherTypography.h2),
                const SizedBox(height: 8),
                Text(
                  'Create groups to organize students by ability level or interest',
                  style: TeacherTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _createNewGroup,
                  icon: const Icon(Icons.add),
                  label: Text('Create First Group',
                      style: TeacherTypography.buttonText),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teacherPrimary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          TeacherDimensions.radiusRound),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'READING GROUPS',
            style: TeacherTypography.sectionHeader.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _viewGroupDetails(group, studentsInGroup),
        child: Container(
          padding: const EdgeInsets.all(TeacherDimensions.paddingXL),
          decoration: TeacherDimensions.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color, color.withValues(alpha: 0.4)],
                      ),
                      borderRadius: BorderRadius.circular(3),
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
                Divider(
                  color: AppColors.teacherBorder,
                  height: 24,
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: studentsInGroup.take(5).map((student) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                            TeacherDimensions.radiusRound),
                        border: Border.all(
                            color: color.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor:
                                color.withValues(alpha: 0.15),
                            child: Text(
                              student.firstName[0].toUpperCase(),
                              style: TeacherTypography.caption.copyWith(
                                color: color,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            student.firstName,
                            style: TeacherTypography.caption.copyWith(
                              color: AppColors.charcoal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                if (studentsInGroup.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+${studentsInGroup.length - 5} more',
                      style: TeacherTypography.caption.copyWith(
                        color: color,
                      ),
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
          FirebaseService.instance;

      // Load students
      final studentSnapshot = await firebaseService.firestore
          .collection('schools')
          .doc(widget.classModel.schoolId)
          .collection('students')
          .where('classId', isEqualTo: widget.classModel.id)
          .get();
      _allStudents = studentSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Load groups
      final groupsSnapshot = await firebaseService.firestore
          .collection('schools')
          .doc(widget.classModel.schoolId)
          .collection('readingGroups')
          .where('classId', isEqualTo: widget.classModel.id)
          .where('isActive', isEqualTo: true)
          .get();

      _groups = groupsSnapshot.docs
          .map((doc) => ReadingGroupModel.fromFirestore(doc))
          .toList()
        ..sort((a, b) {
          final orderCmp = a.sortOrder.compareTo(b.sortOrder);
          return orderCmp != 0 ? orderCmp : a.name.compareTo(b.name);
        });

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
        levelOptions: _levelsEnabled ? _readingLevelOptions : const [],
        readingLevelService: _levelsEnabled ? _readingLevelService : null,
      ),
    );
    if (!mounted) return;

    if (result != null) {
      try {
        final firebaseService =
            FirebaseService.instance;

        await firebaseService.firestore
            .collection('schools')
            .doc(widget.classModel.schoolId)
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
        levelOptions: _levelsEnabled ? _readingLevelOptions : const [],
        readingLevelService: _levelsEnabled ? _readingLevelService : null,
      ),
    );
    if (!mounted) return;

    if (result != null) {
      try {
        final firebaseService =
            FirebaseService.instance;

        await firebaseService.firestore
            .collection('schools')
            .doc(widget.classModel.schoolId)
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
            FirebaseService.instance;

        await firebaseService.firestore
            .collection('schools')
            .doc(widget.classModel.schoolId)
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
    final groupColor = group.color != null
        ? Color(int.parse(group.color!.replaceFirst('#', '0xFF')))
        : AppColors.teacherPrimary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: groupColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(group.name,
                              style: TeacherTypography.h2),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          color: AppColors.textSecondary,
                          onPressed: () {
                            Navigator.pop(context);
                            _editGroup(group);
                          },
                        ),
                      ],
                    ),
                    if (group.description != null &&
                        group.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description!,
                        style: TeacherTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Info chips row
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (group.readingLevel != null &&
                            group.readingLevel!.isNotEmpty)
                          _detailChip(
                            Icons.auto_stories_outlined,
                            _formatReadingLevel(group.readingLevel),
                            groupColor,
                          ),
                        _detailChip(
                          Icons.timer_outlined,
                          '${group.targetMinutes} min/day',
                          AppColors.teacherPrimary,
                        ),
                        _detailChip(
                          Icons.people_outline,
                          '${students.length} students',
                          AppColors.teacherPrimary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Student list header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Text('Students',
                        style: TeacherTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _manageGroupStudents(group, students);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Manage'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.teacherPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Student list
              Expanded(
                child: students.isEmpty
                    ? Center(
                        child: Text(
                          'No students in this group yet',
                          style: TeacherTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: students.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final student = students[i];
                          final streak =
                              student.stats?.currentStreak ?? 0;
                          return Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    groupColor.withValues(alpha: 0.12),
                                child: Text(
                                  student.firstName.isNotEmpty
                                      ? student.firstName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: groupColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      student.fullName,
                                      style: TeacherTypography.bodyMedium,
                                    ),
                                    Row(
                                      children: [
                                        if (_levelsEnabled &&
                                            student.currentReadingLevel !=
                                                null) ...[
                                          Text(
                                            'Level: ${_formatReadingLevel(student.currentReadingLevel)}',
                                            style: TeacherTypography.caption
                                                .copyWith(
                                                    color: AppColors
                                                        .textSecondary),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        if (streak > 0) ...[
                                          Icon(
                                            Icons
                                                .local_fire_department_outlined,
                                            size: 14,
                                            color:
                                                AppColors.teacherPrimary,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '$streak day streak',
                                            style: TeacherTypography
                                                .caption
                                                .copyWith(
                                                    color: AppColors
                                                        .teacherPrimary),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TeacherTypography.caption.copyWith(color: color),
          ),
        ],
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
            FirebaseService.instance;

        await firebaseService.firestore
            .collection('schools')
            .doc(widget.classModel.schoolId)
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
            FirebaseService.instance;

        final updatedStudentIds = [
          ...selectedGroup.studentIds,
          student.id,
        ];

        await firebaseService.firestore
            .collection('schools')
            .doc(widget.classModel.schoolId)
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
  final ReadingLevelService? readingLevelService;

  const _GroupFormDialog({
    required this.classModel,
    this.levelOptions = const [],
    this.readingLevelService,
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
    _selectedReadingLevel = widget.readingLevelService?.normalizeLevel(
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
              if (widget.levelOptions.isNotEmpty) ...[
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
