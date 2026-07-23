import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../theme/section_theme.dart';
import '../../core/tour/lumi_app_tour.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/allocation_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/reading_group_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/school_model.dart';
import '../../data/providers/comprehension_recordings_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/platform_config_service.dart';
import '../../services/reading_level_service.dart';
import '../../services/student_reading_level_service.dart';
import 'widgets/comprehension_question_sheet.dart';

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
  // Comprehension recording is gated by the school admin's setting and a
  // platform kill switch — hide the per-class question editor unless both are
  // on (it'd never reach parents otherwise).
  bool _comprehensionEnabled = false;

  // Group filtering
  List<ReadingGroupModel> _groups = [];
  // Multi-select group filter. Empty = All Groups. Contains group ids and/or the
  // reserved pseudo-id 'ungrouped'. A student matches if they are in ANY selected
  // group (union), so several groups can be combined.
  final Set<String> _selectedGroupIds = <String>{};

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseService.instance.firestore;
    _readingLevelService = widget.readingLevelService ??
        ReadingLevelService(firestore: _firestore);
    _loadReadingLevelOptions();
    _loadGroups();
    _loadComprehensionFlag();
  }

  @override
  void didUpdateWidget(covariant TeacherClassroomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teacher.schoolId != widget.teacher.schoolId) {
      _loadReadingLevelOptions(forceRefresh: true);
      _loadComprehensionFlag();
    }
    if (oldWidget.selectedClass?.id != widget.selectedClass?.id) {
      _loadGroups();
      _selectedGroupIds.clear();
      _searchQuery = '';
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Resolve whether comprehension recording is enabled (school admin setting
  /// AND the platform kill switch), gating the per-class question editor.
  Future<void> _loadComprehensionFlag() async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;
    try {
      // Platform kill switch fetched alongside; errors fail closed.
      final platformEnabledFuture = PlatformConfigService(firestore: _firestore)
          .isComprehensionRecordingEnabled();
      final doc = await _firestore.collection('schools').doc(schoolId).get();
      final platformEnabled = await platformEnabledFuture;
      if (!mounted || !doc.exists) return;
      final school = SchoolModel.fromFirestore(doc);
      final audioSettings = school.comprehensionRecordingSettings;
      setState(() {
        _comprehensionEnabled = platformEnabled &&
            audioSettings.enabled &&
            !audioSettings.previewOnly;
      });
    } catch (_) {
      // Default false; the button stays hidden.
    }
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
    // Prune ids for groups that no longer exist so a deleted group can't
    // silently widen the filter.
    final liveGroupIds = _groups.map((g) => g.id).toSet();
    _selectedGroupIds.removeWhere(
        (id) => id != 'ungrouped' && !liveGroupIds.contains(id));

    if (_selectedGroupIds.isEmpty) return students; // All Groups

    // Union of every selected group's members (plus ungrouped students if that
    // pseudo-group is selected).
    final allowed = <String>{};
    var includeUngrouped = false;
    for (final id in _selectedGroupIds) {
      if (id == 'ungrouped') {
        includeUngrouped = true;
        continue;
      }
      final group = _groups.where((g) => g.id == id).firstOrNull;
      if (group != null) allowed.addAll(group.studentIds);
    }
    final Set<String> groupedIds = includeUngrouped
        ? {for (final g in _groups) ...g.studentIds}
        : const {};
    return students.where((s) {
      if (allowed.contains(s.id)) return true;
      if (includeUngrouped && !groupedIds.contains(s.id)) return true;
      return false;
    }).toList();
  }

  void _toggleGroupFilter(String id) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_selectedGroupIds.contains(id)) {
        _selectedGroupIds.remove(id);
      } else {
        _selectedGroupIds.add(id);
      }
    });
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

  /// Days since the student last read, or null if they never have.
  int? _daysSinceLastRead(StudentModel student) {
    final lastRead = student.stats?.lastReadingDate;
    if (lastRead == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(lastRead.year, lastRead.month, lastRead.day);
    return today.difference(lastDay).inDays;
  }

  String _lastActivityLabel(StudentModel student) {
    final days = _daysSinceLastRead(student);
    if (days == null) return 'No reading logged';
    if (days <= 0) return 'Read today';
    if (days == 1) return 'Read yesterday';
    return 'Last read $days days ago';
  }

  /// Reading-status colour for the row's left bar: green (recent) → amber
  /// (becoming stale) → red (overdue) → grey (no data).
  Color _recencyColor(StudentModel student) {
    final days = _daysSinceLastRead(student);
    if (days == null) return LumiTokens.muted.withValues(alpha: 0.45);
    if (days <= 1) return LumiTokens.green;
    if (days <= 4) return LumiTokens.yellow;
    return LumiTokens.red.withValues(alpha: 0.8);
  }

  /// The student's first reading group, or null if ungrouped.
  ReadingGroupModel? _studentGroup(StudentModel student) {
    for (final g in _groups) {
      if (g.studentIds.contains(student.id)) return g;
    }
    return null;
  }

  // Memoized per class so rebuilds (and switching back to a class) reuse the
  // live Firestore subscriptions instead of re-subscribing every build.
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
      _studentsStreams = {};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
      _allocationsStreams = {};

  Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream(
      ClassModel classModel) {
    return _studentsStreams.putIfAbsent(
      classModel.id,
      () => _firestore
          .collection('schools')
          .doc(widget.teacher.schoolId)
          .collection('students')
          .where('classId', isEqualTo: classModel.id)
          .snapshots()
          .asBroadcastStream(),
    );
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
    return _allocationsStreams.putIfAbsent(
      classModel.id,
      () => _allocationsQuery(classModel).snapshots().asBroadcastStream(),
    );
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
      return Center(
        child: Text('No class selected', style: LumiType.bodyL),
      );
    }

    return LumiSectionScope(
      section: LumiSectionTheme.classScreen,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                      const SliverToBoxAdapter(child: SizedBox(height: 200)),
                    ],
                  ),
                  Positioned(
                    right: 16,
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Classroom kiosk: students self-scan on a shared iPad.
                        // An additional path to the same weekly allocations — the
                        // teacher Scan flow below is unchanged. White FAB needs an
                        // explicit green label colour (LumiType.button is white).
                        LumiTourTarget(
                          id: 'teacher.class.kioskScanIn',
                          child: FloatingActionButton.extended(
                            heroTag: 'kioskFab',
                            onPressed: () => _openKiosk(selectedClass),
                            backgroundColor: LumiTokens.paper,
                            foregroundColor: LumiTokens.green,
                            elevation: 2,
                            icon: const Icon(Icons.tablet_mac_rounded),
                            label: Text(
                              'Class scan-in',
                              style: LumiType.button
                                  .copyWith(color: LumiTokens.green),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        LumiTourTarget(
                          id: 'teacher.class.scanBooks',
                          child: FloatingActionButton.extended(
                            heroTag: 'scanFab',
                            onPressed: () =>
                                _showStudentScannerPicker(selectedClass),
                            backgroundColor: LumiTokens.green,
                            foregroundColor: LumiTokens.paper,
                            elevation: 4,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: Text('Scan', style: LumiType.button),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildClassOverviewCard(
    ClassModel selectedClass, {
    required List<StudentModel> students,
    required bool isLoading,
  }) {
    final totalStudents = students.length;
    final studentCountLabel =
        '$totalStudents ${totalStudents == 1 ? 'student' : 'students'}';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final usePhoneLayout =
                constraints.maxWidth < 560 || textScale > 1.3;

            final title = _buildClassTitle(selectedClass);
            final count = Text(
              studentCountLabel,
              key: const ValueKey('classroom_student_count'),
              style: LumiType.caption.copyWith(
                color: LumiTokens.muted,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              softWrap: false,
            );
            final actions = _buildClassHeaderActions(selectedClass);

            if (!usePhoneLayout) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        if (!isLoading) ...[
                          const SizedBox(height: LumiTokens.space1),
                          count,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: LumiTokens.space4),
                  Flexible(child: actions),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: LumiTokens.space1),
                if (!isLoading) count,
                const SizedBox(height: LumiTokens.space1),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildClassTitle(ClassModel selectedClass) {
    final canChangeClass = widget.classes.length > 1;
    return GestureDetector(
      key: const ValueKey('classroom_class_selector'),
      onTap:
          canChangeClass ? () => _showClassSelectorBottomSheet(context) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              selectedClass.name,
              key: const ValueKey('classroom_class_name'),
              style: LumiType.heading,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (canChangeClass) ...[
            const SizedBox(width: LumiTokens.space1),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: LumiTokens.muted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClassHeaderActions(ClassModel selectedClass) {
    return Wrap(
      key: const ValueKey('classroom_header_actions'),
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: LumiTokens.space1,
      runSpacing: LumiTokens.space1,
      children: [
        LumiTourTarget(
          id: 'teacher.class.assignBooks',
          child: GestureDetector(
            onTap: _openAllocationScreen,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumiTokens.space1,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: LumiTokens.green,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Assign books',
                    style: LumiType.caption.copyWith(
                      color: LumiTokens.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // These remain compact icon actions. Their tooltips and semantics carry
        // the full labels without taking space away from the class identity.
        if (_comprehensionEnabled) _buildComprehensionButton(selectedClass),
        if (_comprehensionEnabled)
          _buildComprehensionRecordingsButton(selectedClass),
      ],
    );
  }

  /// Class recording inbox with a compact unread-style badge. The badge shows
  /// only the number, capped at 99+, so it remains useful in the tight header.
  Widget _buildComprehensionRecordingsButton(ClassModel selectedClass) {
    final lookup = ComprehensionRecordingsLookup(
      schoolId: widget.teacher.schoolId ?? '',
      classId: selectedClass.id,
    );
    return Consumer(builder: (context, ref, _) {
      final count = ref
              .watch(unreviewedComprehensionRecordingCountProvider(lookup))
              .value ??
          0;
      return InkWell(
        onTap: () => context.push(
          '/teacher/comprehension-recordings',
          extra: {'teacher': widget.teacher, 'classModel': selectedClass},
        ),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        child: Tooltip(
          message: 'Comprehension recordings',
          child: Semantics(
            button: true,
            label: 'Comprehension recordings',
            value: count > 0 ? '$count to review' : 'No recordings to review',
            child: SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.graphic_eq_rounded,
                      size: 20, color: LumiTokens.blue),
                  if (count > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 17, minHeight: 17),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: LumiTokens.red,
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusPill),
                          border:
                              Border.all(color: LumiTokens.cream, width: 1.5),
                        ),
                        child: Text(
                          count >= 100 ? '99+' : '$count',
                          style: LumiType.caption.copyWith(
                            color: LumiTokens.paper,
                            fontSize: 9,
                            height: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  /// Header action that opens the comprehension-question editor sheet for the
  /// selected class. (The editor was previously an orphaned full page reachable
  /// only from the unused ClassDetailScreen.)
  Widget _buildComprehensionButton(ClassModel selectedClass) {
    return IconButton(
      onPressed: () =>
          showComprehensionQuestionSheet(context, classModel: selectedClass),
      icon: const Icon(Icons.quiz_outlined, size: 20, color: LumiTokens.green),
      tooltip: 'Comprehension question',
      visualDensity: VisualDensity.compact,
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
            // Selected when nothing else is — clears any chosen groups.
            selected: _selectedGroupIds.isEmpty,
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() => _selectedGroupIds.clear());
            },
          ),
          const SizedBox(width: 8),
          ..._groups.map((group) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ClassroomToolChip(
                  label: group.name,
                  selected: _selectedGroupIds.contains(group.id),
                  dotColor: _parseGroupColor(group.color),
                  onTap: () => _toggleGroupFilter(group.id),
                ),
              )),
          _ClassroomToolChip(
            label: 'Ungrouped',
            selected: _selectedGroupIds.contains('ungrouped'),
            onTap: () => _toggleGroupFilter('ungrouped'),
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
          style: LumiType.subhead.copyWith(letterSpacing: 0.3),
        ),
        const Spacer(),
        // Sort button — a bordered pill so it clearly reads as tappable.
        GestureDetector(
          key: const ValueKey('classroom_sort_button'),
          onTap: () {
            FocusScope.of(context).unfocus();
            _showSortByBottomSheet(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
              border: Border.all(color: LumiTokens.rule),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert_rounded,
                    size: 14, color: LumiTokens.muted),
                const SizedBox(width: 4),
                Text(
                  _sortChipLabel(),
                  style: LumiType.caption.copyWith(
                    color: LumiTokens.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 16, color: LumiTokens.muted),
              ],
            ),
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
            style: LumiType.caption.copyWith(
              color: LumiTokens.yellow,
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
                          style: LumiType.caption.copyWith(
                            fontSize: 10,
                            color: LumiTokens.muted,
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
              'Your school admin adds students to classes — through the school '
              'portal or a roster import. Once they\'re added, this page becomes '
              'your daily workspace.',
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
              color: LumiTokens.tintGreen,
              borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: LumiTokens.green,
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
                    color: LumiTokens.paper,
                    borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                    border: Border.all(color: LumiTokens.rule),
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
              color: LumiTokens.tintGreen,
              borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 34,
              color: LumiTokens.green,
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
            _selectedGroupIds.clear();
          }),
          icon: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: LumiTokens.tintGreen,
              borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            ),
            child: const Icon(
              Icons.filter_alt_off_rounded,
              size: 34,
              color: LumiTokens.green,
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

  Widget _buildStudentCard(
    StudentModel student, {
    required _StudentBookAssignmentState assignmentState,
  }) {
    final fullName = '${student.firstName} ${student.lastName}';
    final streak = _activeStreak(student.stats);
    final activityLabel = _lastActivityLabel(student);

    final bookStatusIcon = switch (assignmentState) {
      _StudentBookAssignmentState.assigned => Icons.menu_book_rounded,
      _StudentBookAssignmentState.unassigned => Icons.menu_book_outlined,
      _StudentBookAssignmentState.unknown => Icons.menu_book_outlined,
    };
    final bookStatusColor = switch (assignmentState) {
      _StudentBookAssignmentState.assigned => LumiTokens.green,
      _StudentBookAssignmentState.unassigned =>
        LumiTokens.muted.withValues(alpha: 0.55),
      _StudentBookAssignmentState.unknown =>
        LumiTokens.muted.withValues(alpha: 0.35),
    };
    final bookStatusLabel = switch (assignmentState) {
      _StudentBookAssignmentState.assigned => 'Books assigned',
      _StudentBookAssignmentState.unassigned => 'Needs books',
      _StudentBookAssignmentState.unknown => 'Assignment status unavailable',
    };

    // Build single-line meta: "Read yesterday · Test 1"
    final metaParts = <String>[];
    if (_levelsEnabled) {
      metaParts.add(_readingLevelLabel(student));
    }
    metaParts.add(activityLabel);

    // Group (with its colour dot) shown when viewing all groups — redundant
    // once a group filter is active.
    // Show each student's group label when unfiltered OR when several groups are
    // selected (so you can tell which student belongs to which).
    final showGroup = _groups.isNotEmpty &&
        (_selectedGroupIds.isEmpty || _selectedGroupIds.length > 1);
    final group = showGroup ? _studentGroup(student) : null;
    final groupName = showGroup ? (group?.name ?? 'Ungrouped') : null;
    final groupColor = group != null
        ? (_parseGroupColor(group.color) ?? LumiTokens.muted)
        : LumiTokens.muted.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      child: InkWell(
        onTap: () {
          // Drop any search/keyboard focus before navigating so it isn't
          // restored (cursor flashing on the search bar) when we pop back.
          FocusManager.instance.primaryFocus?.unfocus();
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
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        child: Ink(
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
            boxShadow: [
              BoxShadow(
                color: LumiTokens.ink.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // Clip to the card's own radius so the accent strip's outer edge
          // traces exactly the same curve as the card. Giving the strip its
          // own borderRadius cannot work: it is 4px wide, and Flutter scales
          // an RRect's radii down to fit the shape, so a 14px corner on a 4px
          // box renders as ~4px and reads as a mismatch against the card.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Reading-status bar (recency: green / amber / red / grey).
                  // Square by design — the ClipRRect above rounds it.
                  Container(
                    width: 4,
                    color: _recencyColor(student),
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
                                        style: LumiType.body.copyWith(
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
                                        color: LumiTokens.yellow,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '$streak',
                                        style: LumiType.caption.copyWith(
                                          color: LumiTokens.yellow,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        metaParts.join(' · '),
                                        style: LumiType.caption.copyWith(
                                          color: LumiTokens.muted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (showGroup) ...[
                                      Text('  ·  ',
                                          style: LumiType.caption.copyWith(
                                              color: LumiTokens.muted)),
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: groupColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          groupName!,
                                          style: LumiType.caption.copyWith(
                                            color: LumiTokens.muted,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
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
                                color: LumiTokens.muted.withValues(alpha: 0.4),
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
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
          border: Border.all(color: LumiTokens.rule),
          boxShadow: [
            BoxShadow(
              color: LumiTokens.ink.withValues(alpha: 0.04),
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
                style: LumiType.subhead,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: LumiType.body.copyWith(
                  color: LumiTokens.muted,
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

  void _openKiosk(ClassModel classModel) {
    context.push(
      '/teacher/kiosk',
      extra: {
        'teacher': widget.teacher,
        'classModel': classModel,
      },
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

    showLumiToast(
      message: scannedCount > 0
          ? 'Scanned $scannedCount book(s). ${student.firstName} now has $totalAssigned assigned this week.'
          : 'No ISBN scans captured.',
      type: scannedCount > 0 ? LumiToastType.success : LumiToastType.info,
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
        // Dedicated stream for this modal instance, created once per open.
        // _studentsStream(classModel) is memoized and shared with the
        // roster list below, which already has a live subscriber by the
        // time this sheet opens — as a broadcast stream it won't replay
        // the query's already-delivered initial snapshot to a late
        // subscriber, so reusing it here left the picker stuck on its
        // loading state forever. This stream is independent and gets its
        // own initial snapshot regardless of subscriber timing.
        final studentsStream = _firestore
            .collection('schools')
            .doc(widget.teacher.schoolId)
            .collection('students')
            .where('classId', isEqualTo: classModel.id)
            .snapshots();

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return _SheetSurface(
              height: MediaQuery.of(sheetContext).size.height * 0.78,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: LumiTokens.rule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Select Student to Scan', style: LumiType.subhead),
                  const SizedBox(height: 12),

                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: LumiTokens.cream,
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                    ),
                    child: TextField(
                      onChanged: (v) => setSheetState(() => pickerSearch = v),
                      style: LumiType.body,
                      decoration: InputDecoration(
                        hintText: 'Search students...',
                        hintStyle: LumiType.body.copyWith(
                          color: LumiTokens.muted.withValues(alpha: 0.6),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: LumiTokens.muted.withValues(alpha: 0.5),
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
                      stream: studentsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              "Couldn't load students. Please try again.",
                              style: LumiType.body.copyWith(
                                color: LumiTokens.muted,
                              ),
                            ),
                          );
                        }

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
                              style: LumiType.body.copyWith(
                                color: LumiTokens.muted,
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
                              color:
                                  LumiTokens.tintGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusMedium),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
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
                                          color: LumiTokens.green, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Scan All Students (Batch Mode)',
                                          style: LumiType.body.copyWith(
                                            color: LumiTokens.green,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios,
                                          color: LumiTokens.green, size: 14),
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
                                          LumiTokens.radiusMedium),
                                    ),
                                    tileColor: LumiTokens.cream,
                                    leading: StudentAvatar.fromStudent(student,
                                        size: 40),
                                    title: Text(student.fullName,
                                        style: LumiType.body.copyWith(
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
                                              color: LumiTokens.tintGreen
                                                  .withValues(alpha: 0.3),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      LumiTokens.radiusSmall),
                                            ),
                                            child: Text(
                                              _readingLevelLabel(student),
                                              style: LumiType.caption.copyWith(
                                                color: LumiTokens.green,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (isAssigned)
                                          Text(
                                            'Has books',
                                            style: LumiType.caption.copyWith(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          )
                                        else if (assignedStudentIds != null)
                                          Text(
                                            'Needs books',
                                            style: LumiType.caption.copyWith(
                                              color: LumiTokens.yellow,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: const Icon(
                                      Icons.qr_code_scanner,
                                      color: LumiTokens.green,
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

    showLumiToast(
      message: 'Assigned books to $studentsAssigned/$totalStudents students'
          '${skippedCount > 0 ? ' ($skippedCount skipped)' : ''}.',
      type: LumiToastType.success,
    );
  }

  /// Rotating palette of soft avatar colors per spec

  void _showClassSelectorBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SheetSurface(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: LumiTokens.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Select Class', style: LumiType.subhead),
            const SizedBox(height: 16),
            ...widget.classes.map((c) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                  tileColor: widget.selectedClass?.id == c.id
                      ? LumiTokens.tintGreen.withValues(alpha: 0.3)
                      : null,
                  title: Text(
                    c.name,
                    style: LumiType.bodyL.copyWith(
                      fontWeight: widget.selectedClass?.id == c.id
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: widget.selectedClass?.id == c.id
                          ? LumiTokens.green
                          : LumiTokens.ink,
                    ),
                  ),
                  subtitle: Text(
                    '${c.studentIds.length} students',
                    style: LumiType.caption,
                  ),
                  trailing: widget.selectedClass?.id == c.id
                      ? const Icon(Icons.check_circle, color: LumiTokens.green)
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
      builder: (context) => _SheetSurface(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: LumiTokens.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Sort Students by', style: LumiType.subhead),
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
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      tileColor:
          isSelected ? LumiTokens.tintGreen.withValues(alpha: 0.3) : null,
      leading: Icon(
        icon,
        color: isSelected ? LumiTokens.green : LumiTokens.muted,
      ),
      title: Text(
        label,
        style: LumiType.bodyL.copyWith(
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? LumiTokens.green : LumiTokens.ink,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: LumiTokens.green)
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
    const foregroundColor = LumiTokens.paper;
    const backgroundColor = LumiTokens.green;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
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
                  style: LumiType.body.copyWith(
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
    final foregroundColor = selected ? LumiTokens.paper : LumiTokens.ink;
    final backgroundColor = selected ? LumiTokens.green : LumiTokens.paper;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            border: Border.all(
              color: selected ? LumiTokens.green : LumiTokens.rule,
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
                    color: selected ? LumiTokens.paper : dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: LumiType.caption.copyWith(
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
      color: selected ? LumiTokens.green : LumiTokens.cream,
      borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: LumiType.caption.copyWith(
              color: selected ? Colors.white : LumiTokens.ink,
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
      Radius.circular(LumiTokens.radiusLarge),
    );

    return Container(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: borderRadius,
        border: Border.all(
          color: isActive
              ? LumiTokens.green.withValues(alpha: 0.45)
              : LumiTokens.rule,
        ),
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
                  color: LumiTokens.tintGreen.withValues(alpha: 0.3),
                ),
              ),
            ),
            TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.search,
              cursorColor: LumiTokens.green,
              style: LumiType.body.copyWith(
                fontWeight: FontWeight.w600,
                color: LumiTokens.green,
              ),
              decoration: InputDecoration(
                hintText: 'Find a student...',
                hintStyle: LumiType.body.copyWith(
                  color: LumiTokens.muted,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isActive
                      ? LumiTokens.green
                      : LumiTokens.muted.withValues(alpha: 0.58),
                ),
                suffixIcon: hasQuery
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: LumiTokens.muted,
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

/// The rounded white surface every bottom sheet on this screen sits on.
///
/// The transparent Material is load-bearing, not decoration. A ListTile paints
/// its tileColor and ink splashes onto the nearest Material ANCESTOR — without
/// one inside this surface, that ancestor sits below the white background,
/// which then hides both. The sort sheet's selected-option tint and the
/// student picker's cream tiles were invisible for exactly this reason.
///
/// Flutter 3.44 asserts on the shape ("ListTile background color or ink
/// splashes may be invisible"); 3.41 did not, which is how it went unnoticed.
/// Extracted so a fourth sheet cannot reintroduce it by copy-paste.
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({
    required this.child,
    required this.padding,
    this.height,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? height;

  static const BorderRadius _radius =
      BorderRadius.vertical(top: Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: _radius,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _radius,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
