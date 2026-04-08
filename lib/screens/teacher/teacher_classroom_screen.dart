import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi/reading_level_picker_sheet.dart';
import '../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/reading_group_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';
import '../../services/isbn_assignment_service.dart';
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

enum _ClassroomQuickFilter {
  all,
  needsLevel,
  onStreak,
  noReadingThisWeek,
}

class _TeacherClassroomScreenState extends State<TeacherClassroomScreen> {
  late final FirebaseFirestore _firestore;
  late final ReadingLevelService _readingLevelService;
  late final StudentReadingLevelService _studentReadingLevelService;
  String _sortBy = 'name';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<ReadingLevelOption> _readingLevelOptions = const [];
  bool _levelsEnabled = true;

  // Group filtering
  List<ReadingGroupModel> _groups = [];
  String? _selectedGroupFilter; // null = all, 'ungrouped' = ungrouped, else groupId
  _ClassroomQuickFilter _quickFilter = _ClassroomQuickFilter.all;

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseService.instance.firestore;
    _readingLevelService = widget.readingLevelService ??
        ReadingLevelService(firestore: _firestore);
    _studentReadingLevelService = widget.studentReadingLevelService ??
        StudentReadingLevelService(
          firestore: _firestore,
          readingLevelService: _readingLevelService,
        );
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
      _quickFilter = _ClassroomQuickFilter.all;
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
    final group = _groups.where((g) => g.id == _selectedGroupFilter).firstOrNull;
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

  Future<List<ReadingLevelOption>> _ensureReadingLevelOptionsLoaded() async {
    if (_readingLevelOptions.isNotEmpty) {
      return _readingLevelOptions;
    }

    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) {
      throw StateError('School ID not available');
    }

    final options = await _readingLevelService.loadSchoolLevels(schoolId);
    if (mounted) {
      setState(() => _readingLevelOptions = options);
    } else {
      _readingLevelOptions = options;
    }
    return options;
  }

  List<StudentModel> _sortStudents(List<StudentModel> students) {
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

  bool _isLevelUnset(StudentModel student) {
    final raw = student.currentReadingLevel?.trim();
    return raw == null || raw.isEmpty;
  }

  bool _isLevelUnresolved(StudentModel student) {
    if (_readingLevelOptions.isEmpty) return false;
    return _readingLevelService.hasUnresolvedLevel(
      student.currentReadingLevel,
      options: _readingLevelOptions,
    );
  }

  bool _needsLevelAttention(StudentModel student) {
    return _isLevelUnset(student) || _isLevelUnresolved(student);
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

  Color _activityBadgeColor(StudentModel student) {
    final label = _lastActivityLabel(student);
    if (label == 'Read today' || label == 'Read yesterday') {
      return AppColors.teacherPrimary;
    }
    if (label == 'Active this week') {
      return AppColors.success;
    }
    return AppColors.warmOrange;
  }

  List<StudentModel> _applyQuickFilter(List<StudentModel> students) {
    switch (_quickFilter) {
      case _ClassroomQuickFilter.all:
        return students;
      case _ClassroomQuickFilter.needsLevel:
        return students.where(_needsLevelAttention).toList();
      case _ClassroomQuickFilter.onStreak:
        return students.where((s) => _activeStreak(s.stats) > 0).toList();
      case _ClassroomQuickFilter.noReadingThisWeek:
        return students.where((s) => !_hasReadThisWeek(s.stats)).toList();
    }
  }

  String _quickFilterLabel(_ClassroomQuickFilter filter) {
    switch (filter) {
      case _ClassroomQuickFilter.all:
        return 'All';
      case _ClassroomQuickFilter.needsLevel:
        return 'Needs level';
      case _ClassroomQuickFilter.onStreak:
        return 'On streak';
      case _ClassroomQuickFilter.noReadingThisWeek:
        return 'No reading';
    }
  }

  String? _activeFilterSummary() {
    if (_quickFilter != _ClassroomQuickFilter.all) {
      return _quickFilterLabel(_quickFilter);
    }

    if (_selectedGroupFilter == 'ungrouped') return 'Ungrouped';
    if (_selectedGroupFilter != null) {
      final group = _groups.where((g) => g.id == _selectedGroupFilter).firstOrNull;
      return group?.name;
    }

    return null;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream(ClassModel classModel) {
    return _firestore
        .collection('schools')
        .doc(widget.teacher.schoolId)
        .collection('students')
        .where('classId', isEqualTo: classModel.id)
        .snapshots();
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildClassOverviewCard(selectedClass),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildActionStrip(selectedClass),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildSearchBar(),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
            child: _buildToolbelt(selectedClass),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: _buildStudentsHeader(selectedClass),
          ),
        ),

        _buildStudentList(selectedClass),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  /// Per spec: class name + student/book count, with class selector if multiple
  Widget _buildClassHeader(ClassModel selectedClass) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Class selector if multiple classes
            if (widget.classes.length > 1) ...[
              Material(
                color: AppColors.teacherPrimaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                  onTap: () => _showClassSelectorBottomSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedClass.name,
                          style: TeacherTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.teacherPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down,
                            size: 20, color: AppColors.teacherPrimary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(selectedClass.name, style: TeacherTypography.h1),
            const SizedBox(height: 4),
            Text(
              '${selectedClass.studentIds.length} Students',
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact scanner prompt card — horizontal layout
  Widget _buildScannerCard(ClassModel classModel) {
    return Material(
      color: AppColors.teacherPrimary,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
      child: InkWell(
        onTap: () => _showStudentScannerPicker(classModel),
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(
                      TeacherDimensions.radiusM),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 22,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan ISBN to Assign Books',
                      style: TeacherTypography.bodyMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select a student, then scan barcodes',
                      style: TeacherTypography.bodySmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupFilterChip(String label, String? filterValue, {String? color}) {
    final isSelected = _selectedGroupFilter == filterValue;
    final groupColor = color != null
        ? Color(int.parse(color.replaceFirst('#', '0xFF')))
        : null;
    return GestureDetector(
      onTap: () => setState(() => _selectedGroupFilter = filterValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.teacherPrimary
              : AppColors.teacherPrimaryLight,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
          border: Border.all(
            color: isSelected
                ? AppColors.teacherPrimary
                : AppColors.teacherBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (groupColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.white : groupColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TeacherTypography.caption.copyWith(
                color: isSelected ? AppColors.white : AppColors.charcoal,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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

  Widget _buildSortChip() {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: InkWell(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        onTap: () => _showSortByBottomSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                'Sort: ',
                style: TeacherTypography.bodySmall,
              ),
              Text(
                _sortBy == 'name'
                    ? 'Name'
                    : _sortBy == 'level'
                        ? 'Level'
                        : 'Streak',
                style: TeacherTypography.bodySmall.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: AppColors.teacherPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManageLevelsChip(ClassModel classModel) {
    return Material(
      color: AppColors.teacherPrimaryLight.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: InkWell(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        onTap: () => _openLevelManagement(classModel),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 16,
                color: AppColors.teacherPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                'Manage Levels',
                style: TeacherTypography.bodySmall.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentList(ClassModel classModel) {
    if (classModel.studentIds.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.people_outline,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No students in this class yet',
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Add student functionality coming soon')),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Add Student',
                    style: TeacherTypography.buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teacherPrimary,
                  foregroundColor: AppColors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.teacher.schoolId)
          .collection('students')
          .where('classId', isEqualTo: classModel.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: List.generate(
                  4,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      height: 72,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius:
                            BorderRadius.circular(TeacherDimensions.radiusM),
                        boxShadow: TeacherDimensions.cardShadow,
                      ),
                      child: Row(
                        children: [
                          const LumiSkeleton(
                              width: 40, height: 40, isCircular: true),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                LumiSkeleton(height: 14, width: 120),
                                SizedBox(height: 6),
                                LumiSkeleton(height: 12, width: 80),
                              ],
                            ),
                          ),
                          const LumiSkeleton(width: 32, height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final students = snapshot.data!.docs
            .map((doc) => StudentModel.fromFirestore(doc))
            .where((student) => student.isActive)
            .toList();
        final groupFiltered = _filterByGroup(students);
        final filtered = _filterStudents(groupFiltered);
        final sorted = _sortStudents(filtered);

        if (sorted.isEmpty && _searchQuery.isNotEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.search_off,
                      size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    'No students match "$_searchQuery"',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final student = sorted[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildStudentCard(student),
                ).animate().fadeIn(
                      delay: (index * 50).ms,
                      duration: 300.ms,
                      curve: Curves.easeOut,
                    );
              },
              childCount: sorted.length,
            ),
          ),
        );
      },
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

  /// Per spec: 40px avatar + name + books assigned + streak indicator
  Widget _buildStudentCard(StudentModel student) {
    final fullName = '${student.firstName} ${student.lastName}';
    final avatarColor = _avatarColorForName(fullName);
    final streak = _activeStreak(student.stats);

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      elevation: 0,
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: Row(
            children: [
              // Avatar (40x40 per spec)
              CircleAvatar(
                radius: 20,
                backgroundColor: avatarColor,
                child: Text(
                  student.firstName[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: TeacherTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_levelsEnabled) ...[
                      const SizedBox(height: 6),
                      TeacherReadingLevelPill(
                        label: _readingLevelLabel(student),
                        isUnset: _isLevelUnset(student),
                        isUnresolved: _isLevelUnresolved(student),
                        onTap: () => _showReadingLevelPicker(student),
                      ),
                    ],
                  ],
                ),
              ),

              // Streak indicator (per spec: fire emoji + softOrange, or "—")
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Scan ISBN for ${student.firstName}',
                    icon: const Icon(
                      Icons.qr_code_scanner,
                      color: AppColors.teacherPrimary,
                      size: 20,
                    ),
                    onPressed: widget.selectedClass == null
                        ? null
                        : () => _openScannerForStudent(student),
                  ),
                  if (streak > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          size: 18,
                          color: AppColors.warmOrange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$streak',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFCC80), // softOrange per spec
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '\u2014', // em dash
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReadingLevelPicker(StudentModel student) async {
    try {
      final options = await _ensureReadingLevelOptionsLoaded();
      if (!mounted) return;

      final currentLevelValue = _readingLevelService.normalizeLevel(
        student.currentReadingLevel,
        options: options,
      );
      final currentDisplayLabel = currentLevelValue == null
          ? null
          : _readingLevelService.formatLevelLabel(
              currentLevelValue,
              options: options,
            );

      final result = await ReadingLevelPickerSheet.show(
        context,
        studentName: student.fullName,
        levelSystemLabel: _readingLevelService.schemaDisplayName(options),
        options: options,
        currentLevelValue: currentLevelValue,
        currentDisplayLabel: currentDisplayLabel,
        rawStoredLevel: student.currentReadingLevel,
      );

      if (!mounted || result == null) return;

      final didUpdate = await _studentReadingLevelService.updateStudentLevel(
        actor: widget.teacher,
        student: student,
        options: options,
        newLevel: result.levelValue,
        reason: result.reason,
        source: StudentReadingLevelService.sourceTeacher,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            didUpdate
                ? 'Reading level updated for ${student.firstName}'
                : 'No reading level change saved',
          ),
          backgroundColor:
              didUpdate ? AppColors.success : AppColors.textSecondary,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update reading level: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _openLevelManagement(ClassModel classModel) {
    context.push(
      '/teacher/level-management',
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
                            final service = IsbnAssignmentService();
                            final schoolId = widget.teacher.schoolId;
                            if (schoolId != null && schoolId.isNotEmpty) {
                              service
                                  .getAssignedStudentIdsForWeek(
                                schoolId: schoolId,
                                classId: classModel.id,
                                referenceDate: DateTime.now(),
                              )
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
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseService.instance.firestore
                          .collection('schools')
                          .doc(widget.teacher.schoolId)
                          .collection('students')
                          .where('classId', isEqualTo: classModel.id)
                          .snapshots(),
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
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          _avatarColorForName(student.fullName),
                                      child: Text(
                                        student.firstName[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
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
  static const List<Color> _avatarColors = [
    Color(0xFFFFCDD2), // pink
    Color(0xFFBBDEFB), // blue
    Color(0xFFC8E6C9), // green
    Color(0xFFFFE0B2), // orange
    Color(0xFFE1BEE7), // purple
    Color(0xFFB2EBF2), // cyan
  ];

  Color _avatarColorForName(String name) {
    return _avatarColors[name.hashCode.abs() % _avatarColors.length];
  }

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
        color: AppColors.white,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.teacherBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
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
                  color:
                      AppColors.teacherPrimaryLight.withValues(alpha: 0.82),
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
