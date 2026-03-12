import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';
import '../../services/isbn_assignment_service.dart';

/// Teacher Classroom Screen (Tab 2)
///
/// Per Lumi_Teacher_UI_Spec: class header, ISBN scanner card (gradient),
/// sort dropdown, student list with avatar + name + books + streak.
class TeacherClassroomScreen extends StatefulWidget {
  final UserModel teacher;
  final ClassModel? selectedClass;
  final List<ClassModel> classes;
  final ValueChanged<ClassModel>? onClassChanged;

  const TeacherClassroomScreen({
    super.key,
    required this.teacher,
    this.selectedClass,
    this.classes = const [],
    this.onClassChanged,
  });

  @override
  State<TeacherClassroomScreen> createState() => _TeacherClassroomScreenState();
}

class _TeacherClassroomScreenState extends State<TeacherClassroomScreen> {
  String _sortBy = 'name';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StudentModel> _sortStudents(List<StudentModel> students) {
    final sorted = List<StudentModel>.from(students);
    switch (_sortBy) {
      case 'name':
        sorted.sort((a, b) => a.firstName.compareTo(b.firstName));
        break;
      case 'level':
        sorted.sort((a, b) => (a.currentReadingLevel ?? '')
            .compareTo(b.currentReadingLevel ?? ''));
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
        // Class header
        SliverToBoxAdapter(
          child: _buildClassHeader(selectedClass),
        ),

        // Scanner card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _buildScannerCard(selectedClass),
          ),
        ),

        // Search bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _buildSearchBar(),
          ),
        ),

        // Students header + sort
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Text('Students', style: TeacherTypography.h3),
                const Spacer(),
                _buildSortChip(),
              ],
            ),
          ),
        ),

        // Student list
        _buildStudentList(selectedClass),

        // Bottom padding for nav bar
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

  /// Per spec: gradient card with icon, title, description, white pill button
  Widget _buildScannerCard(ClassModel classModel) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.teacherGradient,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Circular icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_scanner,
                size: 28, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            'Scan ISBN to Assign Books',
            style: TeacherTypography.h3.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Quickly assign books to students by scanning the ISBN barcode',
            style: TeacherTypography.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // White pill button
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
            child: InkWell(
              onTap: () => _showStudentScannerPicker(classModel),
              borderRadius:
                  BorderRadius.circular(TeacherDimensions.radiusRound),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                child: Text(
                  'Open Scanner',
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.teacherPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Select a student, then scan multiple books in one view.',
            style: TeacherTypography.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: TeacherTypography.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Find a student...',
          hintStyle: TeacherTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: _searchQuery.isNotEmpty
                ? AppColors.teacherPrimary
                : AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.textSecondary,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
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
        final filtered = _filterStudents(students);
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

  /// Per spec: 40px avatar + name + books assigned + streak indicator
  Widget _buildStudentCard(StudentModel student) {
    final fullName = '${student.firstName} ${student.lastName}';
    final avatarColor = _avatarColorForName(fullName);
    final streak = student.stats?.currentStreak ?? 0;

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
                    const SizedBox(height: 2),
                    Text(
                      student.currentReadingLevel != null
                          ? student.currentReadingLevel!
                          : 'No level assigned',
                      style: TeacherTypography.bodySmall,
                    ),
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
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
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
                  Text('Select Student to Scan',
                      style: TeacherTypography.h3),
                  const SizedBox(height: 12),

                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(
                          TeacherDimensions.radiusM),
                    ),
                    child: TextField(
                      onChanged: (v) =>
                          setSheetState(() => pickerSearch = v),
                      style: TeacherTypography.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Search students...',
                        hintStyle: TeacherTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.6),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.5),
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
                        onTap: () =>
                            setSheetState(() => pickerFilter = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _PickerFilterChip(
                        label: 'Needs books',
                        selected: pickerFilter == 'unassigned',
                        onTap: () {
                          setSheetState(
                              () => pickerFilter = 'unassigned');
                          if (assignedStudentIds == null &&
                              !loadingAssigned) {
                            loadingAssigned = true;
                            final service = IsbnAssignmentService();
                            final schoolId = widget.teacher.schoolId;
                            if (schoolId != null &&
                                schoolId.isNotEmpty) {
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
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
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
                            .map((doc) =>
                                StudentModel.fromFirestore(doc))
                            .where((student) => student.isActive)
                            .toList();

                        if (students.isEmpty) {
                          return Center(
                            child: Text(
                              'No active students in this class.',
                              style:
                                  TeacherTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        }

                        // Apply search filter
                        if (pickerSearch.isNotEmpty) {
                          final q = pickerSearch.toLowerCase();
                          students = students.where((s) {
                            return s.fullName
                                .toLowerCase()
                                .contains(q);
                          }).toList();
                        }

                        // Sort: unassigned first when filter active
                        students.sort(
                            (a, b) => a.firstName.compareTo(b.firstName));
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
                                  final allStudents = snapshot
                                      .data!.docs
                                      .map((doc) =>
                                          StudentModel.fromFirestore(
                                              doc))
                                      .where(
                                          (student) => student.isActive)
                                      .toList();
                                  Navigator.pop(sheetContext);
                                  _openBatchScanner(
                                      classModel, allStudents);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.people,
                                          color:
                                              AppColors.teacherPrimary,
                                          size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Scan All Students (Batch Mode)',
                                          style: TeacherTypography
                                              .bodyMedium
                                              .copyWith(
                                            color: AppColors
                                                .teacherPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios,
                                          color:
                                              AppColors.teacherPrimary,
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
                                  final isAssigned =
                                      assignedStudentIds
                                              ?.contains(student.id) ??
                                          false;
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(
                                              TeacherDimensions
                                                  .radiusM),
                                    ),
                                    tileColor: AppColors.background,
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          _avatarColorForName(
                                              student.fullName),
                                      child: Text(
                                        student.firstName[0]
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    title: Text(student.fullName,
                                        style: TeacherTypography
                                            .bodyMedium
                                            .copyWith(
                                          fontWeight: FontWeight.w600,
                                        )),
                                    subtitle: Row(
                                      children: [
                                        if (student.currentReadingLevel !=
                                            null) ...[
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 6,
                                                vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors
                                                  .teacherPrimaryLight
                                                  .withValues(
                                                      alpha: 0.3),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      TeacherDimensions
                                                          .radiusS),
                                            ),
                                            child: Text(
                                              student.currentReadingLevel!,
                                              style: TeacherTypography
                                                  .caption
                                                  .copyWith(
                                                color: AppColors
                                                    .teacherPrimary,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (isAssigned)
                                          Text(
                                            'Has books',
                                            style: TeacherTypography
                                                .caption
                                                .copyWith(
                                              color: Colors.green,
                                              fontWeight:
                                                  FontWeight.w600,
                                            ),
                                          )
                                        else if (assignedStudentIds !=
                                            null)
                                          Text(
                                            'Needs books',
                                            style: TeacherTypography
                                                .caption
                                                .copyWith(
                                              color:
                                                  AppColors.warmOrange,
                                              fontWeight:
                                                  FontWeight.w600,
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

    final studentsAssigned =
        (result['studentsAssigned'] as num?)?.toInt() ?? 0;
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
            const SizedBox(height: 8),
            _buildSortOption(
                'level', 'Reading Level', Icons.signal_cellular_alt),
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
      color: selected
          ? AppColors.teacherPrimary
          : AppColors.background,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
      child: InkWell(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
