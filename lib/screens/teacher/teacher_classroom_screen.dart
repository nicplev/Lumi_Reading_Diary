import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/allocation_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/reading_group_model.dart';
import '../../data/models/achievement_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_level_service.dart';
import '../../services/student_reading_level_service.dart';

/// Teacher Classroom Screen (Tab 2)
///
/// Per Lumi_Teacher_UI_Spec: class header, ISBN scanner card (gradient),
/// sort dropdown, student list with avatar + name + books + streak.
class TeacherClassroomScreen extends StatefulWidget {
  final UserModel teacher;
  final ClassModel? selectedClass;
  final List<ClassModel> classes;
  final ValueChanged<ClassModel>? onClassChanged;
  final FirebaseFirestore? firestore;
  final ReadingLevelService? readingLevelService;
  final StudentReadingLevelService? studentReadingLevelService;

  const TeacherClassroomScreen({
    super.key,
    required this.teacher,
    this.selectedClass,
    this.classes = const [],
    this.onClassChanged,
    this.firestore,
    this.readingLevelService,
    this.studentReadingLevelService,
  });

  @override
  State<TeacherClassroomScreen> createState() => _TeacherClassroomScreenState();
}

enum _StudentBookAssignmentState {
  assigned,
  unassigned,
  unknown,
}

class _ClassroomAssignmentStatus {
  const _ClassroomAssignmentStatus._({
    required this.assignedStudentIds,
    required this.isLoaded,
  });

  const _ClassroomAssignmentStatus.unknown()
      : this._(assignedStudentIds: null, isLoaded: false);

  const _ClassroomAssignmentStatus.loaded(Set<String> assignedStudentIds)
      : this._(assignedStudentIds: assignedStudentIds, isLoaded: true);

  final Set<String>? assignedStudentIds;
  final bool isLoaded;

  _StudentBookAssignmentState stateFor(String studentId) {
    final ids = assignedStudentIds;
    if (!isLoaded || ids == null) {
      return _StudentBookAssignmentState.unknown;
    }
    return ids.contains(studentId)
        ? _StudentBookAssignmentState.assigned
        : _StudentBookAssignmentState.unassigned;
  }
}

class _TeacherClassroomScreenState extends State<TeacherClassroomScreen> {
  late final FirebaseFirestore _firestore;
  late final ReadingLevelService _readingLevelService;
  String _sortBy = 'name';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<ReadingLevelOption> _readingLevelOptions = const [];
  bool _levelsEnabled = true;

  // Group filtering
  List<ReadingGroupModel> _groups = [];
  String?
      _selectedGroupFilter; // null = all, 'ungrouped' = ungrouped, else groupId

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseService.instance.firestore;
    _readingLevelService = widget.readingLevelService ??
        ReadingLevelService(firestore: _firestore);
    _loadReadingLevelOptions();
    _loadGroups();
  }

  @override
  void didUpdateWidget(covariant TeacherClassroomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teacher.schoolId != widget.teacher.schoolId) {
      _loadReadingLevelOptions(forceRefresh: true);
    }
    if (oldWidget.selectedClass?.id != widget.selectedClass?.id) {
      _loadGroups();
      _selectedGroupFilter = null;
      _searchQuery = '';
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final classModel = widget.selectedClass;
    if (classModel == null) return;

    try {
      final snapshot = await _firestore
          .collection('schools')
          .doc(widget.teacher.schoolId)
          .collection('readingGroups')
          .where('classId', isEqualTo: classModel.id)
          .where('isActive', isEqualTo: true)
          .get();

      if (!mounted) return;
      setState(() {
        _groups = snapshot.docs
            .map((doc) => ReadingGroupModel.fromFirestore(doc))
            .toList()
          ..sort((a, b) {
            final orderCmp = a.sortOrder.compareTo(b.sortOrder);
            return orderCmp != 0 ? orderCmp : a.name.compareTo(b.name);
          });
      });
    } catch (e) {
      debugPrint('Error loading reading groups: $e');
    }
  }

  List<StudentModel> _filterByGroup(List<StudentModel> students) {
    if (_selectedGroupFilter == null) return students;
    if (_selectedGroupFilter == 'ungrouped') {
      final allGroupedIds = <String>{};
      for (final group in _groups) {
        allGroupedIds.addAll(group.studentIds);
      }
      return students.where((s) => !allGroupedIds.contains(s.id)).toList();
    }
    final group =
        _groups.where((g) => g.id == _selectedGroupFilter).firstOrNull;
    if (group == null) return students;
    return students.where((s) => group.studentIds.contains(s.id)).toList();
  }

  Future<void> _loadReadingLevelOptions({bool forceRefresh = false}) async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;

    try {
      final options = await _readingLevelService.loadSchoolLevels(
        schoolId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _readingLevelOptions = options;
        _levelsEnabled = options.isNotEmpty;
      });
    } catch (error) {
      debugPrint('Error loading reading level options: $error');
    }
  }

  List<StudentModel> _sortStudents(
    List<StudentModel> students, {
    Set<String>? assignedStudentIds,
  }) {
    final sorted = List<StudentModel>.from(students);
    switch (_sortBy) {
      case 'name':
        sorted.sort((a, b) => a.firstName.compareTo(b.firstName));
        break;
      case 'level':
        if (_readingLevelOptions.isNotEmpty) {
          sorted.sort(
            (a, b) => _readingLevelService.compareLevels(
              a.currentReadingLevel,
              b.currentReadingLevel,
              options: _readingLevelOptions,
            ),
          );
        } else {
          sorted.sort(
            (a, b) => (a.currentReadingLevel ?? '')
                .compareTo(b.currentReadingLevel ?? ''),
          );
        }
        break;
      case 'streak':
        sorted.sort((a, b) => (b.stats?.currentStreak ?? 0)
            .compareTo(a.stats?.currentStreak ?? 0));
        break;
      case 'needsBooks':
        final ids = assignedStudentIds;
        if (ids == null) {
          sorted.sort((a, b) => a.firstName.compareTo(b.firstName));
        } else {
          sorted.sort((a, b) {
            final aAssigned = ids.contains(a.id);
            final bAssigned = ids.contains(b.id);
            if (aAssigned != bAssigned) {
              return aAssigned ? 1 : -1;
            }

            final firstNameCompare = a.firstName.compareTo(b.firstName);
            if (firstNameCompare != 0) return firstNameCompare;
            return a.lastName.compareTo(b.lastName);
          });
        }
        break;
    }
    return sorted;
  }

  List<StudentModel> _filterStudents(List<StudentModel> students) {
    if (_searchQuery.isEmpty) return students;
    final query = _searchQuery.toLowerCase();
    return students.where((s) {
      final fullName = '${s.firstName} ${s.lastName}'.toLowerCase();
      return fullName.contains(query);
    }).toList();
  }

  String _readingLevelLabel(StudentModel student) {
    if (_readingLevelOptions.isEmpty) {
      final raw = student.currentReadingLevel?.trim();
      return raw == null || raw.isEmpty ? 'Needs level' : raw;
    }

    return _readingLevelService.formatCompactLabel(
      student.currentReadingLevel,
      options: _readingLevelOptions,
    );
  }

  DateTime _startOfWeek([DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  bool _hasReadThisWeek(StudentStats? stats) {
    final lastRead = stats?.lastReadingDate;
    if (lastRead == null) return false;
    return !DateTime(
      lastRead.year,
      lastRead.month,
      lastRead.day,
    ).isBefore(_startOfWeek());
  }

  String _lastActivityLabel(StudentModel student) {
    final lastRead = student.stats?.lastReadingDate;
    if (lastRead == null) return 'No reading yet';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastDay = DateTime(lastRead.year, lastRead.month, lastRead.day);

    if (lastDay.isAtSameMomentAs(today)) return 'Read today';
    if (lastDay.isAtSameMomentAs(yesterday)) return 'Read yesterday';
    if (_hasReadThisWeek(student.stats)) return 'Active this week';

    return 'No reading this week';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream(
      ClassModel classModel) {
    return _firestore
        .collection('schools')
        .doc(widget.teacher.schoolId)
        .collection('students')
        .where('classId', isEqualTo: classModel.id)
        .snapshots();
  }

  Query<Map<String, dynamic>> _allocationsQuery(ClassModel classModel) {
    return _firestore
        .collection('schools')
        .doc(widget.teacher.schoolId)
        .collection('allocations')
        .where('classId', isEqualTo: classModel.id);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _allocationsStream(
      ClassModel classModel) {
    return _allocationsQuery(classModel).snapshots();
  }

  Set<String> _assignedStudentIdsFromAllocationDocs({
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required Iterable<String> candidateStudentIds,
  }) {
    final now = DateTime.now();
    final validStudentIds = candidateStudentIds.toSet();
    final assignedStudentIds = <String>{};

    for (final doc in docs) {
      try {
        final allocation = AllocationModel.fromFirestore(doc);
        final withinWindow = !allocation.startDate.isAfter(now) &&
            !allocation.endDate.isBefore(now);

        if (!allocation.isActive ||
            !withinWindow ||
            allocation.type != AllocationType.byTitle) {
          continue;
        }

        final applicableStudentIds = allocation.isForWholeClass
            ? validStudentIds
            : allocation.studentIds
                .where((studentId) => validStudentIds.contains(studentId))
                .toSet();

        for (final studentId in applicableStudentIds) {
          final items =
              allocation.effectiveAssignmentItemsForStudent(studentId);
          if (items.isNotEmpty) {
            assignedStudentIds.add(studentId);
          }
        }
      } catch (error) {
        debugPrint(
          'TeacherClassroomScreen: skipping malformed allocation ${doc.id}: '
          '$error',
        );
      }
    }

    return assignedStudentIds;
  }

  _ClassroomAssignmentStatus _assignmentStatusForClass({
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    required Iterable<String> candidateStudentIds,
  }) {
    if (!snapshot.hasData) {
      return const _ClassroomAssignmentStatus.unknown();
    }

    return _ClassroomAssignmentStatus.loaded(
      _assignedStudentIdsFromAllocationDocs(
        docs: snapshot.data!.docs,
        candidateStudentIds: candidateStudentIds,
      ),
    );
  }

  Future<Set<String>> _loadAssignedStudentIdsForClass(
    ClassModel classModel,
  ) async {
    final snapshot = await _allocationsQuery(classModel).get();
    return _assignedStudentIdsFromAllocationDocs(
      docs: snapshot.docs,
      candidateStudentIds: classModel.studentIds,
    );
  }

  void _openAllocationScreen() {
    final classModel = widget.selectedClass;
    if (classModel == null) return;

    context.push(
      '/teacher/allocation',
      extra: {
        'teacher': widget.teacher,
        'selectedClass': classModel,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedClass = widget.selectedClass;

    if (selectedClass == null) {
      return const Center(
        child: Text('No class selected', style: TeacherTypography.bodyLarge),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _studentsStream(selectedClass),
      builder: (context, snapshot) {
        final allStudents = snapshot.hasData
            ? snapshot.data!.docs
                .map(StudentModel.fromFirestore)
                .where((student) => student.isActive)
                .toList()
            : const <StudentModel>[];

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _allocationsStream(selectedClass),
          builder: (context, allocationSnapshot) {
            final assignmentStatus = _assignmentStatusForClass(
              snapshot: allocationSnapshot,
              candidateStudentIds: allStudents.map((student) => student.id),
            );
            final groupScopedStudents = snapshot.hasData
                ? _filterByGroup(allStudents)
                : const <StudentModel>[];
            final searchFilteredStudents = snapshot.hasData
                ? _filterStudents(groupScopedStudents)
                : const <StudentModel>[];
            final visibleStudents = snapshot.hasData
                ? _sortStudents(
                    searchFilteredStudents,
                    assignedStudentIds: assignmentStatus.assignedStudentIds,
                  )
                : const <StudentModel>[];

            return Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildClassOverviewCard(
                        selectedClass,
                        students: allStudents,
                        isLoading: !snapshot.hasData,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _buildSearchBar(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
                        child: _buildToolbelt(
                          selectedClass,
                          students: groupScopedStudents,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: _buildStudentsHeader(),
                      ),
                    ),
                    if (snapshot.hasData)
                      SliverToBoxAdapter(
                        child: _buildAttentionRow(allStudents),
                      ),
                    _buildStudentList(
                      classModel: selectedClass,
                      snapshot: snapshot,
                      allStudents: allStudents,
                      visibleStudents: visibleStudents,
                      assignmentStatus: assignmentStatus,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 20,
                  child: FloatingActionButton(
                    onPressed: () => _showStudentScannerPicker(selectedClass),
                    backgroundColor: AppColors.teacherPrimary,
                    elevation: 4,
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildClassOverviewCard(
    ClassModel selectedClass, {
    required List<StudentModel> students,
    required bool isLoading,
  }) {
    final totalStudents = students.length;
    final summaryParts = <String>[
      '$totalStudents students',
    ];

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        child: Row(
          children: [
            // Class name + optional dropdown
            GestureDetector(
              onTap: widget.classes.length > 1
                  ? () => _showClassSelectorBottomSheet(context)
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedClass.name,
                    style: TeacherTypography.h2,
                  ),
                  if (widget.classes.length > 1) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            // Inline summary stats
            if (!isLoading)
              Text(
                summaryParts.join(' · '),
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _openAllocationScreen,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.teacherSurfaceTint,
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusRound),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 14, color: AppColors.teacherPrimary),
                    const SizedBox(width: 5),
                    Text(
                      'Allocate',
                      style: TeacherTypography.caption.copyWith(
                        color: AppColors.teacherPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return _ClassroomSearchBar(
      controller: _searchController,
      query: _searchQuery,
      onChanged: (value) => setState(() => _searchQuery = value),
      onClear: () {
        _searchController.clear();
        setState(() => _searchQuery = '');
      },
    );
  }

  Widget _buildToolbelt(
    ClassModel classModel, {
    required List<StudentModel> students,
  }) {
    // Only show group filter chips when groups exist
    if (_groups.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          _ClassroomToolChip(
            label: 'All Groups',
            selected: _selectedGroupFilter == null,
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() => _selectedGroupFilter = null);
            },
          ),
          const SizedBox(width: 8),
          ..._groups.map((group) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ClassroomToolChip(
                  label: group.name,
                  selected: _selectedGroupFilter == group.id,
                  dotColor: _parseGroupColor(group.color),
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _selectedGroupFilter = group.id);
                  },
                ),
              )),
          _ClassroomToolChip(
            label: 'Ungrouped',
            selected: _selectedGroupFilter == 'ungrouped',
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() => _selectedGroupFilter = 'ungrouped');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsHeader() {
    return Row(
      children: [
        Text(
          'Students',
          style: TeacherTypography.h3.copyWith(
            letterSpacing: 0.3,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        // Sort button
        GestureDetector(
          key: const ValueKey('classroom_sort_button'),
          onTap: () {
            FocusScope.of(context).unfocus();
            _showSortByBottomSheet(context);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert_rounded,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                _sortChipLabel(),
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

  String _sortChipLabel() {
    switch (_sortBy) {
      case 'needsBooks':
        return 'Needs Books';
      case 'level':
        return 'Level';
      case 'streak':
        return 'Streak';
      case 'name':
      default:
        return 'Name';
    }
  }

  Color? _parseGroupColor(String? color) {
    if (color == null || color.trim().isEmpty) return null;
    try {
      return Color(int.parse(color.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  Widget _buildAttentionRow(List<StudentModel> allStudents) {
    final needsAttention = allStudents.where((s) {
      return !_hasReadThisWeek(s.stats);
    }).toList()
      ..sort((a, b) => a.firstName.compareTo(b.firstName));

    if (needsAttention.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Needs attention',
            style: TeacherTypography.caption.copyWith(
              color: AppColors.warmOrange,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: needsAttention.map((student) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      context.push(
                        '/teacher/student-detail/${student.id}',
                        extra: {
                          'teacher': widget.teacher,
                          'student': student,
                          if (widget.selectedClass != null)
                            'classModel': widget.selectedClass,
                        },
                      );
                    },
                    child: Column(
                      children: [
                        StudentAvatar.fromStudent(student, size: 36),
                        const SizedBox(height: 4),
                        Text(
                          student.firstName,
                          style: TeacherTypography.caption.copyWith(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList({
    required ClassModel classModel,
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    required List<StudentModel> allStudents,
    required List<StudentModel> visibleStudents,
    required _ClassroomAssignmentStatus assignmentStatus,
  }) {
    if (classModel.studentIds.isEmpty ||
        (snapshot.hasData && allStudents.isEmpty)) {
      return SliverToBoxAdapter(
        child: _buildEmptyStateCard(
          title: 'No students in this class yet',
          message:
              'This page becomes your daily workspace once students are added to the class.',
          actionLabel:
              widget.classes.length > 1 ? 'Choose Another Class' : 'Refresh',
          onAction: () {
            if (widget.classes.length > 1) {
              _showClassSelectorBottomSheet(context);
            } else {
              setState(() {});
            }
          },
          icon: const LumiMascot(
            variant: LumiVariant.teacher,
            size: 76,
            animate: false,
          ),
        ),
      );
    }

    if (snapshot.hasError) {
      return SliverToBoxAdapter(
        child: _buildEmptyStateCard(
          title: 'Could not load students',
          message: 'Pull to refresh or reopen the class to try again.',
          actionLabel: 'Retry',
          onAction: () => setState(() {}),
          icon: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.teacherPrimaryLight,
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.teacherPrimary,
            ),
          ),
        ),
      );
    }

    if (!snapshot.hasData) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: List.generate(
              4,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  height: 98,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusL),
                    border: Border.all(color: AppColors.teacherBorder),
                  ),
                  child: Row(
                    children: [
                      const LumiSkeleton(
                        width: 44,
                        height: 44,
                        isCircular: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            LumiSkeleton(height: 15, width: 130),
                            SizedBox(height: 10),
                            LumiSkeleton(height: 28, width: 170),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const LumiSkeleton(height: 36, width: 36),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (visibleStudents.isEmpty && _searchQuery.isNotEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyStateCard(
          title: 'No students found',
          message:
              'Nothing matched "$_searchQuery". Try a shorter search or clear it to see the full class.',
          actionLabel: 'Clear Search',
          onAction: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
          icon: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.teacherSurfaceTint,
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 34,
              color: AppColors.teacherPrimary,
            ),
          ),
        ),
      );
    }

    if (visibleStudents.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyStateCard(
          title: 'No students in this view',
          message:
              'No students match the current group filter. Reset to see the full class.',
          actionLabel: 'Show All Students',
          onAction: () => setState(() {
            _selectedGroupFilter = null;
          }),
          icon: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.teacherSurfaceTint,
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
            ),
            child: const Icon(
              Icons.filter_alt_off_rounded,
              size: 34,
              color: AppColors.teacherPrimary,
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final student = visibleStudents[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildStudentCard(
                student,
                assignmentState: assignmentStatus.stateFor(student.id),
              ),
            ).animate().fadeIn(
                  delay: (index * 50).ms,
                  duration: 280.ms,
                  curve: Curves.easeOut,
                );
          },
          childCount: visibleStudents.length,
        ),
      ),
    );
  }

  /// Returns the current streak only if the student read today or yesterday.
  /// If the last reading was 2+ days ago the streak is broken — return 0.
  int _activeStreak(StudentStats? stats) {
    if (stats == null) return 0;
    final stored = stats.currentStreak;
    if (stored <= 0) return 0;
    final lastRead = stats.lastReadingDate;
    if (lastRead == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastDay = DateTime(lastRead.year, lastRead.month, lastRead.day);
    if (lastDay.isAtSameMomentAs(today) ||
        lastDay.isAtSameMomentAs(yesterday)) {
      return stored;
    }
    return 0;
  }

  Color _statusAccentColor(StudentModel student) {
    final label = _lastActivityLabel(student);
    switch (label) {
      case 'Read today':
        return AppColors.success;
      case 'Read yesterday':
      case 'Active this week':
        return AppColors.teacherPrimary;
      case 'No reading yet':
        return AppColors.error.withValues(alpha: 0.6);
      default:
        return AppColors.warmOrange;
    }
  }

  Widget _buildStudentCard(
    StudentModel student, {
    required _StudentBookAssignmentState assignmentState,
  }) {
    final fullName = '${student.firstName} ${student.lastName}';
    final streak = _activeStreak(student.stats);
    final activityLabel = _lastActivityLabel(student);
    final accentColor = _statusAccentColor(student);

    final bookStatusIcon = switch (assignmentState) {
      _StudentBookAssignmentState.assigned => Icons.menu_book_rounded,
      _StudentBookAssignmentState.unassigned => Icons.menu_book_outlined,
      _StudentBookAssignmentState.unknown => Icons.menu_book_outlined,
    };
    final bookStatusColor = switch (assignmentState) {
      _StudentBookAssignmentState.assigned => AppColors.teacherPrimary,
      _StudentBookAssignmentState.unassigned =>
        AppColors.textSecondary.withValues(alpha: 0.55),
      _StudentBookAssignmentState.unknown =>
        AppColors.textSecondary.withValues(alpha: 0.35),
    };
    final bookStatusLabel = switch (assignmentState) {
      _StudentBookAssignmentState.assigned => 'Books assigned',
      _StudentBookAssignmentState.unassigned => 'Needs books',
      _StudentBookAssignmentState.unknown => 'Assignment status unavailable',
    };

    // Build single-line meta: "Level 3 · Read yesterday"
    final metaParts = <String>[];
    if (_levelsEnabled) {
      metaParts.add(_readingLevelLabel(student));
    }
    metaParts.add(activityLabel);

    // Next achievement goal for this student
    final stats = student.stats;
    String? nextAchievementLabel;
    if (stats != null) {
      final nearest = AchievementTemplates.nearestUnearned(
        currentStreak: stats.currentStreak,
        totalBooksRead: stats.totalBooksRead,
        totalMinutesRead: stats.totalMinutesRead,
        totalReadingDays: stats.totalReadingDays,
        earnedAchievementIds: const [],
        minProgress: 0.0,
      );
      if (nearest != null) {
        final int current;
        switch (nearest.achievement.requirementType) {
          case 'streak':  current = stats.currentStreak;    break;
          case 'books':   current = stats.totalBooksRead;   break;
          case 'minutes': current = stats.totalMinutesRead; break;
          case 'days':    current = stats.totalReadingDays; break;
          default:        current = nearest.achievement.requiredValue;
        }
        final remaining = nearest.achievement.requiredValue - current;
        if (remaining > 0) {
          final unit = switch (nearest.achievement.requirementType) {
            'books'   => remaining == 1 ? 'book'   : 'books',
            'minutes' => remaining == 1 ? 'minute' : 'minutes',
            _         => remaining == 1 ? 'day'    : 'days',
          };
          nextAchievementLabel =
              '$remaining more $unit to earn "${nearest.achievement.name}"';
        }
      }
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: InkWell(
        onTap: () {
          context.push(
            '/teacher/student-detail/${student.id}',
            extra: {
              'teacher': widget.teacher,
              'student': student,
              if (widget.selectedClass != null)
                'classModel': widget.selectedClass,
            },
          );
        },
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Traffic-light accent bar
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                    child: Row(
                      children: [
                        StudentAvatar.fromStudent(student, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      fullName,
                                      style:
                                          TeacherTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (streak > 0) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.local_fire_department_rounded,
                                      size: 14,
                                      color: AppColors.warmOrange,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '$streak',
                                      style: TeacherTypography.caption.copyWith(
                                        color: AppColors.warmOrange,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                metaParts.join(' · '),
                                style: TeacherTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (nextAchievementLabel != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  nextAchievementLabel,
                                  style: TeacherTypography.caption.copyWith(
                                    color: const Color(0xFF7C3AED),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              label: bookStatusLabel,
                              child: Icon(
                                key: ValueKey(
                                    'student_book_status_${student.id}'),
                                bookStatusIcon,
                                size: 18,
                                color: bookStatusColor,
                                semanticLabel: bookStatusLabel,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard({
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    required Widget icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
          border: Border.all(color: AppColors.teacherBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.charcoal.withValues(alpha: 0.04),
              blurRadius: 18,
              spreadRadius: -8,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            children: [
              icon,
              const SizedBox(height: 18),
              Text(
                title,
                style: TeacherTypography.h3,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              _ClassroomActionButton(
                label: actionLabel,
                icon: Icons.arrow_forward_rounded,
                onTap: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openScannerForStudent(StudentModel student) async {
    final classModel = widget.selectedClass;
    if (classModel == null) return;

    final result = await context.push(
      '/teacher/isbn-scanner',
      extra: {
        'teacher': widget.teacher,
        'student': student,
        'classModel': classModel,
      },
    );

    if (!mounted || result == null) return;
    if (result is! Map<String, dynamic>) return;

    final scannedCount = (result['scannedCount'] as num?)?.toInt() ?? 0;
    final totalAssigned = (result['totalAssignedBooks'] as num?)?.toInt() ?? 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          scannedCount > 0
              ? 'Scanned $scannedCount book(s). ${student.firstName} now has $totalAssigned assigned this week.'
              : 'No ISBN scans captured.',
        ),
      ),
    );
  }

  void _showStudentScannerPicker(ClassModel classModel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        String pickerSearch = '';
        String pickerFilter = 'all'; // 'all' or 'unassigned'
        Set<String>? assignedStudentIds;
        bool loadingAssigned = false;

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.78,
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Select Student to Scan', style: TeacherTypography.h3),
                  const SizedBox(height: 12),

                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusM),
                    ),
                    child: TextField(
                      onChanged: (v) => setSheetState(() => pickerSearch = v),
                      style: TeacherTypography.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Search students...',
                        hintStyle: TeacherTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary.withValues(alpha: 0.6),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Filter chips
                  Row(
                    children: [
                      _PickerFilterChip(
                        label: 'All',
                        selected: pickerFilter == 'all',
                        onTap: () => setSheetState(() => pickerFilter = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _PickerFilterChip(
                        label: 'Needs books',
                        selected: pickerFilter == 'unassigned',
                        onTap: () {
                          setSheetState(() => pickerFilter = 'unassigned');
                          if (assignedStudentIds == null && !loadingAssigned) {
                            loadingAssigned = true;
                            _loadAssignedStudentIdsForClass(classModel)
                                .then((ids) {
                              setSheetState(() {
                                assignedStudentIds = ids;
                                loadingAssigned = false;
                              });
                            }).catchError((_) {
                              setSheetState(() {
                                assignedStudentIds = <String>{};
                                loadingAssigned = false;
                              });
                            });
                          }
                        },
                      ),
                      const Spacer(),
                      if (loadingAssigned)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Student list
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _studentsStream(classModel),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        var students = snapshot.data!.docs
                            .map((doc) => StudentModel.fromFirestore(doc))
                            .where((student) => student.isActive)
                            .toList();

                        if (students.isEmpty) {
                          return Center(
                            child: Text(
                              'No active students in this class.',
                              style: TeacherTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        }

                        // Apply search filter
                        if (pickerSearch.isNotEmpty) {
                          final q = pickerSearch.toLowerCase();
                          students = students.where((s) {
                            return s.fullName.toLowerCase().contains(q);
                          }).toList();
                        }

                        // Sort: unassigned first when filter active
                        students
                            .sort((a, b) => a.firstName.compareTo(b.firstName));
                        if (pickerFilter == 'unassigned' &&
                            assignedStudentIds != null) {
                          students = students.where((s) {
                            return !assignedStudentIds!.contains(s.id);
                          }).toList();
                        }

                        // "Scan All Students" button at top
                        return Column(
                          children: [
                            // Scan All button
                            Material(
                              color: AppColors.teacherPrimaryLight
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusM),
                                onTap: () {
                                  final allStudents = snapshot.data!.docs
                                      .map((doc) =>
                                          StudentModel.fromFirestore(doc))
                                      .where((student) => student.isActive)
                                      .toList();
                                  Navigator.pop(sheetContext);
                                  _openBatchScanner(classModel, allStudents);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.people,
                                          color: AppColors.teacherPrimary,
                                          size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Scan All Students (Batch Mode)',
                                          style: TeacherTypography.bodyMedium
                                              .copyWith(
                                            color: AppColors.teacherPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios,
                                          color: AppColors.teacherPrimary,
                                          size: 14),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Individual student list
                            Expanded(
                              child: ListView.separated(
                                itemCount: students.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final student = students[index];
                                  final isAssigned = assignedStudentIds
                                          ?.contains(student.id) ??
                                      false;
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          TeacherDimensions.radiusM),
                                    ),
                                    tileColor: AppColors.background,
                                    leading: StudentAvatar.fromStudent(student,
                                        size: 40),
                                    title: Text(student.fullName,
                                        style: TeacherTypography.bodyMedium
                                            .copyWith(
                                          fontWeight: FontWeight.w600,
                                        )),
                                    subtitle: Row(
                                      children: [
                                        if (_levelsEnabled &&
                                            student.currentReadingLevel !=
                                                null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors
                                                  .teacherPrimaryLight
                                                  .withValues(alpha: 0.3),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      TeacherDimensions
                                                          .radiusS),
                                            ),
                                            child: Text(
                                              _readingLevelLabel(student),
                                              style: TeacherTypography.caption
                                                  .copyWith(
                                                color: AppColors.teacherPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (isAssigned)
                                          Text(
                                            'Has books',
                                            style: TeacherTypography.caption
                                                .copyWith(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          )
                                        else if (assignedStudentIds != null)
                                          Text(
                                            'Needs books',
                                            style: TeacherTypography.caption
                                                .copyWith(
                                              color: AppColors.warmOrange,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: const Icon(
                                      Icons.qr_code_scanner,
                                      color: AppColors.teacherPrimary,
                                    ),
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      _openScannerForStudent(student);
                                    },
                                  );
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
            );
          },
        );
      },
    );
  }

  Future<void> _openBatchScanner(
      ClassModel classModel, List<StudentModel> students) async {
    final result = await context.push(
      '/teacher/isbn-scanner',
      extra: {
        'teacher': widget.teacher,
        'studentQueue': students,
        'classModel': classModel,
      },
    );

    if (!mounted || result == null) return;
    if (result is! Map<String, dynamic>) return;

    final studentsAssigned = (result['studentsAssigned'] as num?)?.toInt() ?? 0;
    final skippedCount = (result['skippedCount'] as num?)?.toInt() ?? 0;
    final totalStudents = (result['totalStudents'] as num?)?.toInt() ?? 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Assigned books to $studentsAssigned/$totalStudents students'
          '${skippedCount > 0 ? ' ($skippedCount skipped)' : ''}.',
        ),
      ),
    );
  }

  /// Rotating palette of soft avatar colors per spec

  void _showClassSelectorBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Select Class', style: TeacherTypography.h3),
            const SizedBox(height: 16),
            ...widget.classes.map((c) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  tileColor: widget.selectedClass?.id == c.id
                      ? AppColors.teacherPrimaryLight.withValues(alpha: 0.3)
                      : null,
                  title: Text(
                    c.name,
                    style: TeacherTypography.bodyLarge.copyWith(
                      fontWeight: widget.selectedClass?.id == c.id
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: widget.selectedClass?.id == c.id
                          ? AppColors.teacherPrimary
                          : AppColors.charcoal,
                    ),
                  ),
                  subtitle: Text(
                    '${c.studentIds.length} students',
                    style: TeacherTypography.bodySmall,
                  ),
                  trailing: widget.selectedClass?.id == c.id
                      ? const Icon(Icons.check_circle,
                          color: AppColors.teacherPrimary)
                      : null,
                  onTap: () {
                    if (widget.onClassChanged != null) {
                      widget.onClassChanged!(c);
                    }
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showSortByBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Sort Students by', style: TeacherTypography.h3),
            const SizedBox(height: 16),
            _buildSortOption('name', 'First Name', Icons.sort_by_alpha),
            const SizedBox(height: 8),
            _buildSortOption(
              'needsBooks',
              'Needs Books',
              Icons.menu_book_outlined,
            ),
            if (_levelsEnabled) ...[
              const SizedBox(height: 8),
              _buildSortOption(
                  'level', 'Reading Level', Icons.signal_cellular_alt),
            ],
            const SizedBox(height: 8),
            _buildSortOption(
                'streak', 'Current Streak', Icons.local_fire_department),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return ListTile(
      key: ValueKey('classroom_sort_option_$value'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      ),
      tileColor: isSelected
          ? AppColors.teacherPrimaryLight.withValues(alpha: 0.3)
          : null,
      leading: Icon(
        icon,
        color: isSelected ? AppColors.teacherPrimary : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TeacherTypography.bodyLarge.copyWith(
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? AppColors.teacherPrimary : AppColors.charcoal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.teacherPrimary)
          : null,
      onTap: () {
        setState(() => _sortBy = value);
        Navigator.pop(context);
      },
    );
  }
}

class _ClassroomActionButton extends StatelessWidget {
  const _ClassroomActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const foregroundColor = AppColors.white;
    const backgroundColor = AppColors.teacherPrimary;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
      child: InkWell(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassroomToolChip extends StatelessWidget {
  const _ClassroomToolChip({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.dotColor,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? AppColors.white : AppColors.charcoal;
    final backgroundColor =
        selected ? AppColors.teacherPrimary : AppColors.white;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
      child: InkWell(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
            border: Border.all(
              color:
                  selected ? AppColors.teacherPrimary : AppColors.teacherBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.white : dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TeacherTypography.bodySmall.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerFilterChip extends StatelessWidget {
  const _PickerFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.teacherPrimary : AppColors.background,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
      child: InkWell(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TeacherTypography.bodySmall.copyWith(
              color: selected ? Colors.white : AppColors.charcoal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassroomSearchBar extends StatefulWidget {
  const _ClassroomSearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_ClassroomSearchBar> createState() => _ClassroomSearchBarState();
}

class _ClassroomSearchBarState extends State<_ClassroomSearchBar>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode;
  late final AnimationController _fillController;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _fillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _fillController.value = _focusNode.hasFocus ? 1.0 : 0.0;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _fillController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final targetValue = _focusNode.hasFocus ? 1.0 : 0.0;

    if (MediaQuery.of(context).disableAnimations) {
      _fillController.value = targetValue;
    } else if (_focusNode.hasFocus) {
      _fillController.forward();
    } else {
      _fillController.reverse();
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.query.isNotEmpty;
    final isActive = _focusNode.hasFocus || hasQuery;
    const borderRadius = BorderRadius.all(
      Radius.circular(TeacherDimensions.radiusL),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.teacherSurfaceTint.withValues(alpha: 0.6),
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _fillController,
                builder: (context, child) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _fillController.value.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: child,
                    ),
                  );
                },
                child: ColoredBox(
                  color: AppColors.teacherPrimaryLight.withValues(alpha: 0.82),
                ),
              ),
            ),
            TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.rosePink,
              style: TeacherTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Find a student...',
                hintStyle: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary.withValues(alpha: 0.65),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isActive
                      ? AppColors.teacherPrimary
                      : AppColors.textSecondary.withValues(alpha: 0.58),
                ),
                suffixIcon: hasQuery
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.textSecondary,
                        onPressed: widget.onClear,
                      )
                    : null,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
