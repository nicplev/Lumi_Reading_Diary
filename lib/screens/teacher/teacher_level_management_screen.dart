import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/reading_level_picker_sheet.dart';
import '../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../data/models/class_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_level_service.dart';
import '../../services/student_reading_level_service.dart';

class TeacherLevelManagementScreen extends StatefulWidget {
  const TeacherLevelManagementScreen({
    super.key,
    required this.teacher,
    required this.classModel,
  });

  final UserModel teacher;
  final ClassModel classModel;

  @override
  State<TeacherLevelManagementScreen> createState() =>
      _TeacherLevelManagementScreenState();
}

class _TeacherLevelManagementScreenState
    extends State<TeacherLevelManagementScreen> {
  final ReadingLevelService _readingLevelService = ReadingLevelService();
  final StudentReadingLevelService _studentReadingLevelService =
      StudentReadingLevelService();
  final TextEditingController _searchController = TextEditingController();

  List<ReadingLevelOption> _readingLevelOptions = const [];
  bool _levelsEnabled = true;
  List<StudentModel> _currentStudents = const [];
  Set<String> _selectedStudentIds = <String>{};
  bool _showNeedsLevelOnly = false;
  bool _isApplying = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadReadingLevelOptions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    if (_readingLevelOptions.isNotEmpty) return _readingLevelOptions;
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

  String _readingLevelCompactLabel(StudentModel student) {
    if (_readingLevelOptions.isEmpty) {
      final raw = student.currentReadingLevel?.trim();
      return (raw == null || raw.isEmpty) ? 'Needs level' : raw;
    }

    return _readingLevelService.formatCompactLabel(
      student.currentReadingLevel,
      options: _readingLevelOptions,
    );
  }

  String _readingLevelDisplayLabel(StudentModel student) {
    if (_readingLevelOptions.isEmpty) {
      final raw = student.currentReadingLevel?.trim();
      return (raw == null || raw.isEmpty) ? 'Needs level' : raw;
    }

    return _readingLevelService.formatLevelLabel(
      student.currentReadingLevel,
      options: _readingLevelOptions,
    );
  }

  List<StudentModel> _filterStudents(List<StudentModel> students) {
    var filtered = students.where((student) => student.isActive).toList();

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((student) {
        final studentId = student.studentId?.toLowerCase() ?? '';
        return student.fullName.toLowerCase().contains(query) ||
            studentId.contains(query);
      }).toList();
    }

    if (_showNeedsLevelOnly) {
      filtered = filtered
          .where((student) =>
              _isLevelUnset(student) || _isLevelUnresolved(student))
          .toList();
    }

    filtered.sort((a, b) {
      final compare = _readingLevelOptions.isEmpty
          ? (a.currentReadingLevel ?? '').compareTo(b.currentReadingLevel ?? '')
          : _readingLevelService.compareLevels(
              a.currentReadingLevel,
              b.currentReadingLevel,
              options: _readingLevelOptions,
            );
      if (compare != 0) return compare;
      return a.fullName.compareTo(b.fullName);
    });

    return filtered;
  }

  Map<String, int> _buildDistribution(List<StudentModel> students) {
    final counts = <String, int>{};
    for (final student in students) {
      final label = _isLevelUnset(student) || _isLevelUnresolved(student)
          ? 'Needs level'
          : _readingLevelCompactLabel(student);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }

  List<StudentModel> _selectedStudentsFrom(List<StudentModel> students) {
    return students
        .where((student) => _selectedStudentIds.contains(student.id))
        .toList(growable: false);
  }

  String? _sharedSelectedLevelValue(List<StudentModel> students) {
    if (students.isEmpty || _readingLevelOptions.isEmpty) return null;

    String? shared;
    for (final student in students) {
      final normalized = _readingLevelService.normalizeLevel(
        student.currentReadingLevel,
        options: _readingLevelOptions,
      );
      if (shared == null) {
        shared = normalized;
        continue;
      }
      if (shared != normalized) {
        return null;
      }
    }
    return shared;
  }

  Future<void> _showBulkLevelPicker() async {
    final options = await _ensureReadingLevelOptionsLoaded();
    final selectedStudents = _selectedStudentsFrom(_currentStudents);
    if (selectedStudents.isEmpty || !mounted) return;

    final sharedLevel = _sharedSelectedLevelValue(selectedStudents);
    final currentDisplayLabel = sharedLevel == null
        ? null
        : _readingLevelService.formatLevelLabel(
            sharedLevel,
            options: options,
          );

    final result = await ReadingLevelPickerSheet.show(
      context,
      studentName:
          '${selectedStudents.length} ${selectedStudents.length == 1 ? 'student' : 'students'} selected',
      levelSystemLabel: _readingLevelService.schemaDisplayName(options),
      options: options,
      currentLevelValue: sharedLevel,
      currentDisplayLabel: currentDisplayLabel,
      rawStoredLevel: null,
    );

    if (!mounted || result == null) return;

    await _applyBulkLevelChange(
      newLevel: result.levelValue,
      reason: result.reason,
    );
  }

  Future<void> _applyBulkLevelChange({
    required String? newLevel,
    String? reason,
  }) async {
    final selectedStudents = _selectedStudentsFrom(_currentStudents);
    if (selectedStudents.isEmpty) return;

    final options = await _ensureReadingLevelOptionsLoaded();
    setState(() => _isApplying = true);

    try {
      final updatedCount =
          await _studentReadingLevelService.bulkUpdateStudentLevels(
        actor: widget.teacher,
        students: selectedStudents,
        options: options,
        newLevel: newLevel,
        reason: reason,
        source: StudentReadingLevelService.sourceBulkTeacher,
      );

      if (!mounted) return;
      if (updatedCount > 0) {
        setState(() => _selectedStudentIds.clear());
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedCount > 0
                ? 'Updated reading levels for $updatedCount student${updatedCount == 1 ? '' : 's'}'
                : 'No reading level changes were needed',
          ),
          backgroundColor:
              updatedCount > 0 ? AppColors.success : AppColors.textSecondary,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update reading levels: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  Future<void> _moveSelectedLevels({required bool increase}) async {
    final selectedStudents = _selectedStudentsFrom(_currentStudents);
    if (selectedStudents.isEmpty) return;

    final options = await _ensureReadingLevelOptionsLoaded();
    final sharedLevel = _sharedSelectedLevelValue(selectedStudents);
    if (sharedLevel == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Select students with the same current level to move together'),
        ),
      );
      return;
    }

    final targetOption = increase
        ? _readingLevelService.nextLevel(sharedLevel, options: options)
        : _readingLevelService.previousLevel(sharedLevel, options: options);

    if (targetOption == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            increase
                ? 'Those students are already at the top of the level scale'
                : 'Those students are already at the lowest level',
          ),
        ),
      );
      return;
    }

    await _applyBulkLevelChange(
      newLevel: targetOption.value,
      reason: increase
          ? 'Bulk move up from level management'
          : 'Bulk move down from level management',
    );
  }

  void _toggleSelectAll(List<StudentModel> students) {
    final visibleIds = students.map((student) => student.id).toSet();
    final hasUnselected =
        visibleIds.any((studentId) => !_selectedStudentIds.contains(studentId));

    setState(() {
      if (hasUnselected) {
        _selectedStudentIds = {..._selectedStudentIds, ...visibleIds};
      } else {
        _selectedStudentIds.removeAll(visibleIds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Manage Reading Levels',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
      bottomNavigationBar:
          _selectedStudentIds.isEmpty ? null : _buildBulkActionBar(),
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
                      'Contact your school admin to enable reading levels.',
                      style: TeacherTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.firestore
                  .collection('schools')
                  .doc(widget.teacher.schoolId)
                  .collection('students')
                  .where('classId', isEqualTo: widget.classModel.id)
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load students',
                      style: TeacherTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.teacherPrimary,
                    ),
                  );
                }

                final students = snapshot.data!.docs
                    .map((doc) => StudentModel.fromFirestore(doc))
                    .toList(growable: false);
                _currentStudents = students;
                final filteredStudents = _filterStudents(students);
                final distribution = _buildDistribution(students);

                return Column(
                  children: [
                    _buildControls(filteredStudents, distribution),
                    Expanded(
                      child: filteredStudents.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              itemCount: filteredStudents.length,
                              itemBuilder: (context, index) {
                                final student = filteredStudents[index];
                                final isSelected =
                                    _selectedStudentIds.contains(student.id);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildStudentTile(
                                    student: student,
                                    isSelected: isSelected,
                                  ),
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
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.classModel.name, style: TeacherTypography.h2),
          const SizedBox(height: 6),
          Text(
            'Set, move, and review reading levels for this class using your school\'s approved level system.',
            style: TeacherTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.menu_book_rounded,
                label:
                    '${widget.classModel.studentIds.length} students in class',
              ),
              _InfoChip(
                icon: Icons.schema_outlined,
                label: _readingLevelOptions.isEmpty
                    ? 'Loading level system...'
                    : _readingLevelService
                        .schemaDisplayName(_readingLevelOptions),
              ),
              _InfoChip(
                icon: Icons.checklist_rounded,
                label: '${_selectedStudentIds.length} selected',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
    List<StudentModel> filteredStudents,
    Map<String, int> distribution,
  ) {
    final visibleIds = filteredStudents.map((student) => student.id).toSet();
    final allVisibleSelected = visibleIds.isNotEmpty &&
        visibleIds
            .every((studentId) => _selectedStudentIds.contains(studentId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              boxShadow: TeacherDimensions.cardShadow,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search students...',
                hintStyle: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilterChip(
                label: const Text('Needs level'),
                selected: _showNeedsLevelOnly,
                onSelected: (value) {
                  setState(() => _showNeedsLevelOnly = value);
                },
                selectedColor:
                    AppColors.teacherPrimaryLight.withValues(alpha: 0.28),
                checkmarkColor: AppColors.teacherPrimary,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: filteredStudents.isEmpty
                    ? null
                    : () => _toggleSelectAll(filteredStudents),
                icon: Icon(
                  allVisibleSelected
                      ? Icons.deselect_outlined
                      : Icons.select_all_rounded,
                ),
                label: Text(
                    allVisibleSelected ? 'Clear visible' : 'Select visible'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.teacherPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: distribution.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusRound),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      '${entry.key} · ${entry.value}',
                      style: TeacherTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentTile({
    required StudentModel student,
    required bool isSelected,
  }) {
    final initials = student.fullName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: InkWell(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedStudentIds.remove(student.id);
            } else {
              _selectedStudentIds.add(student.id);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
            border: Border.all(
              color: isSelected
                  ? AppColors.teacherPrimary.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                activeColor: AppColors.teacherPrimary,
                onChanged: (_) {
                  setState(() {
                    if (isSelected) {
                      _selectedStudentIds.remove(student.id);
                    } else {
                      _selectedStudentIds.add(student.id);
                    }
                  });
                },
              ),
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    AppColors.teacherPrimaryLight.withValues(alpha: 0.28),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: TeacherTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.teacherPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      style: TeacherTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TeacherReadingLevelPill(
                      label: _readingLevelCompactLabel(student),
                      isUnset: _isLevelUnset(student),
                      isUnresolved: _isLevelUnresolved(student),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _readingLevelDisplayLabel(student),
                      style: TeacherTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              'No students match this view',
              style: TeacherTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Adjust your search or filter to see more students.',
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

  Widget _buildBulkActionBar() {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isApplying
                    ? null
                    : () => _moveSelectedLevels(increase: false),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: const Text('Move Down'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isApplying ? null : _showBulkLevelPicker,
                icon: _isApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.tune_rounded),
                label: const Text('Set Level'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teacherPrimary,
                  foregroundColor: AppColors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isApplying
                    ? null
                    : () => _moveSelectedLevels(increase: true),
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                label: const Text('Move Up'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Clear level',
              onPressed: _isApplying
                  ? null
                  : () => _applyBulkLevelChange(newLevel: null),
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.warmOrange,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.teacherSurfaceTint,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.teacherPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TeacherTypography.caption.copyWith(
              color: AppColors.teacherPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
