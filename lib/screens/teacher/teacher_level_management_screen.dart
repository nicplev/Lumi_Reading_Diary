import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/lumi/reading_level_picker_sheet.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../data/models/class_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_level_service.dart';
import '../../services/student_reading_level_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';

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
  // Cached so rebuilds (search typing, etc.) reuse the live roster
  // subscription instead of re-subscribing every keystroke.
  Stream<QuerySnapshot>? _studentsStream;

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

      showLumiToast(
        message: updatedCount > 0
            ? 'Updated reading levels for $updatedCount student${updatedCount == 1 ? '' : 's'}'
            : 'No reading level changes were needed',
        type: updatedCount > 0 ? LumiToastType.success : LumiToastType.info,
      );
    } catch (error) {
      if (!mounted) return;
      showLumiToast(
        message: 'Could not update reading levels: $error',
        type: LumiToastType.error,
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
      showLumiToast(
        message:
            'Select students with the same current level to move together',
        type: LumiToastType.warning,
      );
      return;
    }

    final targetOption = increase
        ? _readingLevelService.nextLevel(sharedLevel, options: options)
        : _readingLevelService.previousLevel(sharedLevel, options: options);

    if (targetOption == null) {
      if (!mounted) return;
      showLumiToast(
        message: increase
            ? 'Those students are already at the top of the level scale'
            : 'Those students are already at the lowest level',
        type: LumiToastType.info,
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

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.paper,
        foregroundColor: LumiTokens.ink,
        elevation: 0,
        surfaceTintColor: LumiTokens.paper,
        toolbarHeight: 64,
        title: Text('Manage Reading Levels', style: LumiType.subhead),
      ),
      bottomNavigationBar:
          _selectedStudentIds.isEmpty ? null : _buildBulkActionBar(),
      body: !_levelsEnabled
          ? const Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: _LevelStateCard(
                  icon: Icons.info_outline_rounded,
                  title: 'Reading levels are not enabled',
                  message:
                      'Contact your school admin to enable reading levels for your school.',
                ),
              ),
            )
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _studentsStream ??=
                        FirebaseService.instance.firestore
                            .collection('schools')
                            .doc(widget.teacher.schoolId)
                            .collection('students')
                            .where('classId', isEqualTo: widget.classModel.id)
                            .where('isActive', isEqualTo: true)
                            .snapshots()
                            .asBroadcastStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load students',
                            style:
                                LumiType.body.copyWith(color: LumiTokens.muted),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: LumiTokens.green,
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
                                    padding:
                                        const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                    itemCount: filteredStudents.length,
                                    itemBuilder: (context, index) {
                                      final student = filteredStudents[index];
                                      final isSelected = _selectedStudentIds
                                          .contains(student.id);
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.classModel.name, style: LumiType.heading),
          const SizedBox(height: 4),
          Text(
            'Set, move, and review reading levels for this class using your school\'s approved level system.',
            style: LumiType.body.copyWith(color: LumiTokens.muted),
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
          _LevelSearchBar(
            controller: _searchController,
            query: _searchQuery,
            onChanged: (value) => setState(() => _searchQuery = value),
            onClear: _clearSearch,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TeacherFilterChip(
                label: 'Needs level',
                isActive: _showNeedsLevelOnly,
                activeColor: LumiTokens.green,
                onTap: () => setState(
                    () => _showNeedsLevelOnly = !_showNeedsLevelOnly),
              ),
              const Spacer(),
              _buildSelectVisibleButton(
                filteredStudents,
                allVisibleSelected: allVisibleSelected,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: distribution.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: LumiTokens.paper,
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusPill),
                      border: Border.all(color: LumiTokens.rule),
                    ),
                    child: Text(
                      '${entry.key} · ${entry.value}',
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.ink,
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

  Widget _buildSelectVisibleButton(
    List<StudentModel> filteredStudents, {
    required bool allVisibleSelected,
  }) {
    final enabled = filteredStudents.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => _toggleSelectAll(filteredStudents) : null,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            border: Border.all(color: LumiTokens.rule, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allVisibleSelected
                    ? Icons.deselect_outlined
                    : Icons.select_all_rounded,
                size: 16,
                color: enabled
                    ? LumiTokens.green
                    : LumiTokens.muted.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Text(
                allVisibleSelected ? 'Clear visible' : 'Select visible',
                style: LumiType.caption.copyWith(
                  color: enabled ? LumiTokens.ink : LumiTokens.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentTile({
    required StudentModel student,
    required bool isSelected,
  }) {
    void toggleSelection() {
      setState(() {
        if (isSelected) {
          _selectedStudentIds.remove(student.id);
        } else {
          _selectedStudentIds.add(student.id);
        }
      });
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        boxShadow: [
          BoxShadow(
            color: LumiTokens.ink.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: isSelected
            ? LumiTokens.tintGreen.withValues(alpha: 0.24)
            : LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        child: InkWell(
          onTap: toggleSelection,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              border: Border.all(
                color: isSelected
                    ? LumiTokens.green.withValues(alpha: 0.55)
                    : LumiTokens.rule,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                _SelectionIndicator(isSelected: isSelected),
                const SizedBox(width: 12),
                StudentAvatar.fromStudent(student, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.fullName,
                        style: LumiType.body
                            .copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TeacherReadingLevelPill(
                            label: _readingLevelCompactLabel(student),
                            isUnset: _isLevelUnset(student),
                            isUnresolved: _isLevelUnresolved(student),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _readingLevelDisplayLabel(student),
                              style: LumiType.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: _LevelStateCard(
          icon: Icons.search_off_rounded,
          title: 'No students match this view',
          message: 'Adjust your search or filter to see more students.',
        ),
      ),
    );
  }

  Widget _buildBulkActionBar() {
    final moveButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: LumiTokens.ink,
      side: const BorderSide(color: LumiTokens.rule, width: 1.2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
      textStyle: LumiType.button.copyWith(fontSize: 13),
    );

    return Container(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        border: const Border(top: BorderSide(color: LumiTokens.rule)),
        boxShadow: LumiTokens.shadowFloat,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isApplying
                      ? null
                      : () => _moveSelectedLevels(increase: false),
                  style: moveButtonStyle,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  label: const Text('Move Down'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isApplying ? null : _showBulkLevelPicker,
                  style: FilledButton.styleFrom(
                    backgroundColor: LumiTokens.green,
                    foregroundColor: LumiTokens.paper,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusLarge),
                    ),
                    textStyle: LumiType.button.copyWith(fontSize: 13),
                  ),
                  icon: _isApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LumiTokens.paper,
                          ),
                        )
                      : const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Set Level'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isApplying
                      ? null
                      : () => _moveSelectedLevels(increase: true),
                  style: moveButtonStyle,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
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
                color: LumiTokens.red,
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LumiTokens.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isSelected ? LumiTokens.green : LumiTokens.paper,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? LumiTokens.green : LumiTokens.rule,
          width: 1.4,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, size: 16, color: LumiTokens.paper)
          : null,
    );
  }
}

class _LevelStateCard extends StatelessWidget {
  const _LevelStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: LumiTokens.green.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            ),
            child: Icon(icon, size: 34, color: LumiTokens.green),
          ),
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
        ],
      ),
    );
  }
}

class _LevelSearchBar extends StatefulWidget {
  const _LevelSearchBar({
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
  State<_LevelSearchBar> createState() => _LevelSearchBarState();
}

class _LevelSearchBarState extends State<_LevelSearchBar>
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
                hintText: 'Search students...',
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
