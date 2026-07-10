import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_group_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_level_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/lumi_toast.dart';

/// Neutral Lumi card surface shared by this screen's sections + dialogs.
/// Flat, bordered "bento" compartment — no drop shadow, defined by its rule.
BoxDecoration _lumiCard() => BoxDecoration(
      color: LumiTokens.paper,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      border: Border.all(color: LumiTokens.rule),
    );

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
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.paper,
        foregroundColor: LumiTokens.ink,
        surfaceTintColor: LumiTokens.paper,
        elevation: 0,
        title: Text('Reading Groups', style: LumiType.subhead),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
            color: LumiTokens.muted,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: LumiTokens.green,
              ),
            )
          : RefreshIndicator(
              color: LumiTokens.green,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
      floatingActionButton: _groups.isNotEmpty
          ? FloatingActionButton(
              heroTag: 'fab_reading_groups',
              onPressed: _createNewGroup,
              elevation: 0,
              highlightElevation: 0,
              backgroundColor: LumiTokens.green,
              foregroundColor: LumiTokens.paper,
              tooltip: 'New group',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildClassInfo() {
    final s = _allStudents.length;
    final g = _groups.length;
    final u = _ungroupedStudents.length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _lumiCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.classModel.name, style: LumiType.heading),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: LumiType.body.copyWith(color: LumiTokens.muted),
              children: [
                TextSpan(text: '$s ${s == 1 ? 'student' : 'students'}'),
                const TextSpan(text: '   ·   '),
                TextSpan(text: '$g ${g == 1 ? 'group' : 'groups'}'),
                const TextSpan(text: '   ·   '),
                TextSpan(
                  text: '$u ungrouped',
                  style: u == 0
                      ? null
                      : const TextStyle(
                          color: LumiTokens.ink,
                          fontWeight: FontWeight.w700,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Normal-case Lumi section heading (matches the dashboard/class screens).
  Widget _sectionHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: LumiType.subhead.copyWith(fontSize: 16),
      ),
    );
  }

  /// Overlapping member avatars on a group card, so groups feel populated.
  Widget _groupAvatarStrip(List<StudentModel> students) {
    const maxShown = 5;
    final shown = students.take(maxShown).toList();
    final overflow = students.length - shown.length;
    return Row(
      children: [
        SizedBox(
          height: 26,
          width: shown.length * 18.0 + 8,
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 18.0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: LumiTokens.paper,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: StudentAvatar.fromStudent(shown[i], size: 23),
                  ),
                ),
            ],
          ),
        ),
        if (overflow > 0)
          Text('+$overflow',
              style: LumiType.caption.copyWith(color: LumiTokens.muted)),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {bool danger = false}) {
    final c = danger ? LumiTokens.red : LumiTokens.ink;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: danger ? LumiTokens.red : LumiTokens.muted),
          const SizedBox(width: 10),
          Text(label, style: LumiType.body.copyWith(color: c)),
        ],
      ),
    );
  }

  Widget _buildUngroupedStudentsCard() {
    final n = _ungroupedStudents.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Ungrouped students'),
        Container(
          padding: const EdgeInsets.all(16),
          // Standard neutral card — consistent with the group cards. The amber
          // icon alone carries the gentle "needs attention" cue.
          decoration: _lumiCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.group_add_outlined,
                      size: 18, color: LumiTokens.yellow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$n ${n == 1 ? 'student' : 'students'} still need a group',
                      style: LumiType.body.copyWith(
                        color: LumiTokens.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (n > 1 && _groups.isNotEmpty)
                    TextButton.icon(
                      onPressed: _showBatchAssign,
                      style: TextButton.styleFrom(
                        foregroundColor: LumiTokens.green,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.checklist_rounded, size: 16),
                      label: Text('Bulk assign',
                          style: LumiType.caption.copyWith(
                            color: LumiTokens.green,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ..._ungroupedStudents.map(_ungroupedRow),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ungroupedRow(StudentModel student) {
    return InkWell(
      onTap: () => _assignStudentToGroup(student),
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            StudentAvatar.fromStudent(student, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                student.fullName,
                style: LumiType.body.copyWith(color: LumiTokens.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: LumiTokens.green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                border:
                    Border.all(color: LumiTokens.green.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Assign',
                    style: LumiType.caption.copyWith(
                      color: LumiTokens.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: LumiTokens.green),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsList() {
    if (_groups.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Reading groups'),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            decoration: _lumiCard(),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: LumiTokens.tintGreen,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.group_work_outlined,
                      size: 40,
                      color: LumiTokens.green,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('No Reading Groups Yet', style: LumiType.subhead),
                const SizedBox(height: 8),
                Text(
                  'Create groups to organise students by ability level or interest',
                  style: LumiType.body
                      .copyWith(color: LumiTokens.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _createNewGroup,
                  icon: const Icon(Icons.add),
                  label: Text('Create First Group',
                      style: LumiType.button),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LumiTokens.green,
                    foregroundColor: LumiTokens.paper,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          LumiTokens.radiusPill),
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
        _sectionHeading('Reading groups'),
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
        : LumiTokens.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _viewGroupDetails(group, studentsInGroup),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: _lumiCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color,
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
                                  Text(group.name, style: LumiType.subhead),
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
                                      LumiTokens.radiusMedium),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  _formatReadingLevel(group.readingLevel),
                                  style: LumiType.caption
                                      .copyWith(color: color),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.people,
                                size: 16, color: LumiTokens.muted),
                            const SizedBox(width: 4),
                            Text(
                              studentsInGroup.isEmpty
                                  ? 'No students yet'
                                  : '${studentsInGroup.length} ${studentsInGroup.length == 1 ? 'student' : 'students'}',
                              style: LumiType.caption,
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.schedule,
                                size: 16, color: LumiTokens.muted),
                            const SizedBox(width: 4),
                            Text(
                              '${group.targetMinutes} min/day',
                              style: LumiType.caption,
                            ),
                          ],
                        ),
                        if (studentsInGroup.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _groupAvatarStrip(studentsInGroup),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded,
                        color: LumiTokens.muted),
                    color: LumiTokens.paper,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                      side: const BorderSide(color: LumiTokens.rule),
                    ),
                    itemBuilder: (context) => [
                      _menuItem('edit', Icons.edit_outlined, 'Edit group'),
                      _menuItem(
                          'students', Icons.people_outline, 'Manage students'),
                      _menuItem('delete', Icons.delete_outline, 'Delete group',
                          danger: true),
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
                const SizedBox(height: 6),
                Text(
                  group.description!,
                  style: LumiType.caption,
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

      showLumiToast(
        message: 'Error loading data: $e',
        type: LumiToastType.error,
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

        showLumiToast(
          message: 'Group created successfully!',
          type: LumiToastType.success,
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        showLumiToast(
          message: 'Error creating group: $e',
          type: LumiToastType.error,
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

        showLumiToast(
          message: 'Group updated successfully!',
          type: LumiToastType.success,
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        showLumiToast(
          message: 'Error updating group: $e',
          type: LumiToastType.error,
        );
      }
    }
  }

  Future<void> _deleteGroup(ReadingGroupModel group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Delete group', style: LumiType.subhead),
        content: Text(
          'Are you sure you want to delete "${group.name}"? Students will be moved to ungrouped.',
          style: LumiType.body.copyWith(color: LumiTokens.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: LumiType.body
                    .copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: LumiTokens.red),
            child: Text('Delete',
                style: LumiType.body
                    .copyWith(color: LumiTokens.red)),
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

        showLumiToast(
          message: 'Group deleted successfully!',
          type: LumiToastType.success,
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        showLumiToast(
          message: 'Error deleting group: $e',
          type: LumiToastType.error,
        );
      }
    }
  }

  void _viewGroupDetails(ReadingGroupModel group, List<StudentModel> students) {
    final groupColor = group.color != null
        ? Color(int.parse(group.color!.replaceFirst('#', '0xFF')))
        : LumiTokens.green;

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
            color: LumiTokens.paper,
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
                  color: LumiTokens.rule,
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
                              style: LumiType.subhead),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          color: LumiTokens.muted,
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
                        style: LumiType.caption
                            .copyWith(color: LumiTokens.muted),
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
                          LumiTokens.green,
                        ),
                        _detailChip(
                          Icons.people_outline,
                          '${students.length} students',
                          LumiTokens.green,
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
                        style: LumiType.body.copyWith(
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
                        foregroundColor: LumiTokens.green,
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
                          style: LumiType.caption
                              .copyWith(color: LumiTokens.muted),
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
                              StudentAvatar.fromStudent(student, size: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      student.fullName,
                                      style: LumiType.body,
                                    ),
                                    Row(
                                      children: [
                                        if (_levelsEnabled &&
                                            student.currentReadingLevel !=
                                                null) ...[
                                          Text(
                                            'Level: ${_formatReadingLevel(student.currentReadingLevel)}',
                                            style: LumiType.caption.copyWith(
                                                color: LumiTokens.muted),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        if (streak > 0) ...[
                                          Icon(
                                            Icons
                                                .local_fire_department_outlined,
                                            size: 14,
                                            color:
                                                LumiTokens.green,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '$streak day streak',
                                            style: LumiType.caption.copyWith(
                                                color: LumiTokens.green),
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
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: LumiType.caption.copyWith(color: color),
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

        showLumiToast(
          message: 'Students updated successfully!',
          type: LumiToastType.success,
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        showLumiToast(
          message: 'Error updating students: $e',
          type: LumiToastType.error,
        );
      }
    }
  }

  Future<void> _assignStudentToGroup(StudentModel student) async {
    if (_groups.isEmpty) {
      showLumiToast(
        message: 'Please create a group first',
        type: LumiToastType.warning,
      );
      return;
    }

    final selectedGroup = await showDialog<ReadingGroupModel>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Assign to group', style: LumiType.subhead),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose a group for ${student.fullName}',
                style: LumiType.caption.copyWith(color: LumiTokens.muted)),
            const SizedBox(height: 12),
            ..._groups.map((group) {
              final c = group.color != null
                  ? Color(int.parse(group.color!.replaceFirst('#', '0xFF')))
                  : LumiTokens.muted;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  onTap: () => Navigator.of(context).pop(group),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: LumiTokens.paper,
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                      border: Border.all(color: LumiTokens.rule),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration:
                              BoxDecoration(color: c, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(group.name,
                              style: LumiType.body.copyWith(
                                  color: LumiTokens.ink,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text('${group.studentIds.length}',
                            style: LumiType.caption),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: LumiTokens.muted),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: LumiType.button.copyWith(color: LumiTokens.muted)),
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

        showLumiToast(
          message: '${student.fullName} added to ${selectedGroup.name}',
          type: LumiToastType.success,
        );

        _loadData();
      } catch (e) {
        if (!mounted) return;

        showLumiToast(
          message: 'Error assigning student: $e',
          type: LumiToastType.error,
        );
      }
    }
  }

  /// Batch-assign: select several ungrouped students and move them into a
  /// group in one go.
  void _showBatchAssign() {
    if (_groups.isEmpty) {
      showLumiToast(
        message: 'Please create a group first',
        type: LumiToastType.warning,
      );
      return;
    }
    final selected = <String>{};
    String? targetGroupId;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final all = _ungroupedStudents;
            final allSelected =
                all.isNotEmpty && selected.length == all.length;
            final canAssign = selected.isNotEmpty && targetGroupId != null;

            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: LumiTokens.paper,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(LumiTokens.radiusXL)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: LumiTokens.rule,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Assign students', style: LumiType.subhead),
                            const SizedBox(height: 2),
                            Text(
                              'Pick students, then choose a group',
                              style: LumiType.caption
                                  .copyWith(color: LumiTokens.muted),
                            ),
                          ],
                        ),
                      ),
                      // Select all
                      InkWell(
                        onTap: () => setSheet(() {
                          if (allSelected) {
                            selected.clear();
                          } else {
                            selected
                              ..clear()
                              ..addAll(all.map((s) => s.id));
                          }
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: Row(
                            children: [
                              Text('Select all',
                                  style: LumiType.body.copyWith(
                                      color: LumiTokens.ink,
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text('${selected.length} selected',
                                  style: LumiType.caption
                                      .copyWith(color: LumiTokens.muted)),
                              const SizedBox(width: 8),
                              Icon(
                                allSelected
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: allSelected
                                    ? LumiTokens.green
                                    : LumiTokens.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: LumiTokens.rule),
                      Expanded(
                        child: ListView(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          children: all.map((student) {
                            final isSel = selected.contains(student.id);
                            return InkWell(
                              borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusMedium),
                              onTap: () => setSheet(() {
                                if (isSel) {
                                  selected.remove(student.id);
                                } else {
                                  selected.add(student.id);
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                child: Row(
                                  children: [
                                    StudentAvatar.fromStudent(student,
                                        size: 32),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(student.fullName,
                                          style: LumiType.body.copyWith(
                                              color: LumiTokens.ink)),
                                    ),
                                    Icon(
                                      isSel
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: isSel
                                          ? LumiTokens.green
                                          : LumiTokens.muted,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const Divider(height: 1, color: LumiTokens.rule),
                      // Target group picker
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Move to',
                              style: LumiType.caption
                                  .copyWith(color: LumiTokens.muted)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _groups.map((group) {
                            final isTarget = targetGroupId == group.id;
                            final color = group.color != null
                                ? Color(int.parse(group.color!
                                    .replaceFirst('#', '0xFF')))
                                : LumiTokens.muted;
                            return GestureDetector(
                              onTap: () =>
                                  setSheet(() => targetGroupId = group.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isTarget
                                      ? LumiTokens.green.withValues(alpha: 0.1)
                                      : LumiTokens.paper,
                                  borderRadius: BorderRadius.circular(
                                      LumiTokens.radiusPill),
                                  border: Border.all(
                                    color: isTarget
                                        ? LumiTokens.green
                                        : LumiTokens.rule,
                                    width: isTarget ? 1.6 : 1.2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(group.name,
                                        style: LumiType.caption.copyWith(
                                          color: LumiTokens.ink,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: canAssign
                                  ? () {
                                      Navigator.pop(sheetCtx);
                                      _performBatchAssign(
                                          targetGroupId!, selected.toList());
                                    }
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: LumiTokens.green,
                                foregroundColor: LumiTokens.paper,
                                disabledBackgroundColor:
                                    LumiTokens.green.withValues(alpha: 0.35),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      LumiTokens.radiusPill),
                                ),
                              ),
                              child: Text(
                                selected.isEmpty
                                    ? 'Assign'
                                    : 'Assign ${selected.length} student${selected.length == 1 ? '' : 's'}',
                                style: LumiType.button,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _performBatchAssign(
      String groupId, List<String> studentIds) async {
    final group = _groups.firstWhere((g) => g.id == groupId);
    try {
      final updated = <String>{...group.studentIds, ...studentIds}.toList();
      await FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.classModel.schoolId)
          .collection('readingGroups')
          .doc(groupId)
          .update({
        'studentIds': updated,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showLumiToast(
        message:
            '${studentIds.length} student${studentIds.length == 1 ? '' : 's'} added to ${group.name}',
        type: LumiToastType.success,
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      showLumiToast(
        message: 'Error assigning students: $e',
        type: LumiToastType.error,
      );
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Reading groups help', style: LumiType.subhead),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('What are Reading Groups?', style: LumiType.subhead),
              const SizedBox(height: 8),
              Text(
                'Reading groups help you organise students by ability level, interest, or any other criteria. This makes it easier to:',
                style: LumiType.body,
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
                        Text('  \u2022  ', style: LumiType.body),
                        Expanded(
                            child: Text(item,
                                style: LumiType.body)),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              Text('How to Use', style: LumiType.subhead),
              const SizedBox(height: 8),
              ...[
                '1. Create groups with meaningful names',
                '2. Assign students to groups',
                '3. Set reading targets for each group',
                '4. Monitor group performance',
              ].map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(item, style: LumiType.body),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it!',
                style: LumiType.body
                    .copyWith(color: LumiTokens.green)),
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

  /// Clean Lumi field — soft cream fill, rule border, green focus.
  InputDecoration _fieldDecoration(String label, {String? hint}) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: LumiType.caption.copyWith(color: LumiTokens.muted),
      floatingLabelStyle: LumiType.caption.copyWith(color: LumiTokens.green),
      hintStyle: LumiType.body.copyWith(color: LumiTokens.muted),
      filled: true,
      fillColor: LumiTokens.cream,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: b(LumiTokens.rule, 1.2),
      enabledBorder: b(LumiTokens.rule, 1.2),
      focusedBorder: b(LumiTokens.green, 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LumiTokens.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
      title: Text(
        widget.existingGroup == null ? 'New Group' : 'Edit Group',
        style: LumiType.subhead,
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
                decoration: _fieldDecoration('Group name *',
                    hint: 'e.g. Advanced Readers'),
                style: LumiType.body.copyWith(color: LumiTokens.ink),
                cursorColor: LumiTokens.green,
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
                decoration: _fieldDecoration('Description (optional)',
                    hint: 'Brief description of this group'),
                style: LumiType.body.copyWith(color: LumiTokens.ink),
                cursorColor: LumiTokens.green,
                maxLines: 2,
              ),
              if (widget.levelOptions.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReadingLevel,
                  decoration: _fieldDecoration('Reading level (optional)'),
                  style: LumiType.body.copyWith(color: LumiTokens.ink),
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
                decoration: _fieldDecoration('Daily target (minutes) *'),
                style: LumiType.body.copyWith(color: LumiTokens.ink),
                cursorColor: LumiTokens.green,
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
              Text('Group colour',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colors.map((color) {
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color:
                            Color(int.parse(color.replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              isSelected ? LumiTokens.ink : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: LumiTokens.paper, size: 20)
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
              style: LumiType.body
                  .copyWith(color: LumiTokens.muted)),
        ),
        ElevatedButton(
          onPressed: _saveGroup,
          style: ElevatedButton.styleFrom(
            backgroundColor: LumiTokens.green,
            foregroundColor: LumiTokens.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
            ),
            elevation: 0,
          ),
          child: Text('Save', style: LumiType.button),
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
      backgroundColor: LumiTokens.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
      title: Text('Manage students · ${widget.group.name}',
          style: LumiType.subhead),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.allStudents.length,
          itemBuilder: (context, index) {
            final student = widget.allStudents[index];
            final isSelected = _selectedStudentIds.contains(student.id);
            final level = widget.readingLevelLabelBuilder
                    ?.call(student.currentReadingLevel) ??
                (student.currentReadingLevel ?? 'Not set');

            return InkWell(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              onTap: () => setState(() {
                if (isSelected) {
                  _selectedStudentIds.remove(student.id);
                } else {
                  _selectedStudentIds.add(student.id);
                }
              }),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    StudentAvatar.fromStudent(student, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.fullName,
                              style: LumiType.body
                                  .copyWith(color: LumiTokens.ink)),
                          Text('Level: $level', style: LumiType.caption),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: isSelected ? LumiTokens.green : LumiTokens.muted,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: LumiType.button.copyWith(color: LumiTokens.muted)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedStudentIds),
          style: FilledButton.styleFrom(
            backgroundColor: LumiTokens.green,
            foregroundColor: LumiTokens.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            ),
          ),
          child: Text('Save', style: LumiType.button),
        ),
      ],
    );
  }
}
