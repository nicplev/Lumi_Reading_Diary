import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_card.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/allocation_model.dart';
import '../../../data/models/book_model.dart';
import '../../../data/models/reading_group_model.dart';
import '../../../data/models/reading_level_option.dart';
import '../../../services/allocation_crud_service.dart';
import '../../../services/firebase_service.dart';
import '../../../services/isbn_assignment_service.dart';
import '../../../services/reading_level_service.dart';
import '../../../services/staff_notification_service.dart';
import 'library_picker_sheet.dart';
import 'allocation_preview_sheet.dart';
import 'widgets/allocation_date_picker_sheet.dart';
import 'widgets/allocation_frequency_picker_sheet.dart';
import 'widgets/allocation_reading_type_card.dart';
import 'widgets/allocation_schedule_card.dart';
import 'widgets/allocation_student_scope_card.dart';

class NewAllocationTab extends StatefulWidget {
  final UserModel teacher;
  final ClassModel? selectedClass;
  final String? preselectedStudentId;
  final AllocationModel? editingAllocation;
  final VoidCallback onEditCancelled;
  final VoidCallback onSaved;

  const NewAllocationTab({
    super.key,
    required this.teacher,
    this.selectedClass,
    this.preselectedStudentId,
    this.editingAllocation,
    required this.onEditCancelled,
    required this.onSaved,
  });

  @override
  State<NewAllocationTab> createState() => _NewAllocationTabState();
}

class _NewAllocationTabState extends State<NewAllocationTab> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  final AllocationCrudService _allocationCrudService = AllocationCrudService();
  final ReadingLevelService _readingLevelService = ReadingLevelService();

  // Form controllers
  final _minutesController = TextEditingController(text: '20');
  final _bookTitlesController = TextEditingController();
  final List<String> _bookTitles = [];
  final Map<String, BookModel> _selectedLibraryBooksByTitle = {};

  // Selection state
  AllocationType _allocationType = AllocationType.freeChoice;
  AllocationCadence _cadence = AllocationCadence.weekly;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  List<String> _selectedStudentIds = [];
  bool _selectAllStudents = true;
  String? _levelRangeStart;
  String? _levelRangeEnd;

  // Data
  List<StudentModel> _students = [];
  List<ReadingLevelOption> _readingLevelOptions = const [];
  List<ReadingGroupModel> _readingGroups = [];
  bool _levelsEnabled = true;
  bool _isLoading = false;
  String _studentSearchQuery = '';

  // Group selection
  bool _selectByGroup = false;
  final List<String> _selectedGroupIds = [];

  // Validation errors
  String? _bookTitleError;
  String? _levelError;
  String? _studentError;

  @override
  void initState() {
    super.initState();
    _loadReadingLevelOptions();
    if (widget.selectedClass != null) {
      _loadStudents();
    }
    if (widget.editingAllocation != null) {
      _populateFromAllocation(widget.editingAllocation!);
    }
  }

  @override
  void didUpdateWidget(covariant NewAllocationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teacher.schoolId != widget.teacher.schoolId) {
      _loadReadingLevelOptions(forceRefresh: true);
    }
    // Handle edit mode transitions
    if (widget.editingAllocation != oldWidget.editingAllocation) {
      if (widget.editingAllocation != null) {
        _populateFromAllocation(widget.editingAllocation!);
      } else {
        _resetForm();
      }
    }
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _bookTitlesController.dispose();
    super.dispose();
  }

  void _populateFromAllocation(AllocationModel a) {
    setState(() {
      _allocationType = a.type;
      _cadence = a.cadence;
      _minutesController.text = a.targetMinutes.toString();
      _startDate = a.startDate;
      _endDate = a.endDate;
      _levelRangeStart = a.levelStart;
      _levelRangeEnd = a.levelEnd;

      _bookTitles.clear();
      _selectedLibraryBooksByTitle.clear();
      final items = a.activeAssignmentItems;
      if (items.isNotEmpty) {
        for (final item in items) {
          _bookTitles.add(item.title);
        }
      } else if (a.bookTitles != null) {
        _bookTitles.addAll(a.bookTitles!);
      }

      if (a.isForWholeClass) {
        _selectAllStudents = true;
        _selectedStudentIds = _students.map((s) => s.id).toList();
      } else {
        _selectAllStudents = false;
        _selectedStudentIds = List.from(a.studentIds);
      }
    });
  }

  Future<void> _loadStudents() async {
    if (widget.selectedClass == null) return;

    setState(() => _isLoading = true);

    try {
      // Load the class roster from the source of truth — each student doc's
      // `classId` — rather than the ClassModel.studentIds denormalized cache,
      // which can be empty/stale and made "Whole Class" show 0 even when the
      // class had students. Mirrors the roster query in TeacherClassroomScreen.
      final studentsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.teacher.schoolId)
          .collection('students')
          .where('classId', isEqualTo: widget.selectedClass!.id)
          .get();
      final students =
          studentsSnapshot.docs.map(StudentModel.fromFirestore).toList();

      // Load reading groups for this class in parallel
      final groupsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.teacher.schoolId)
          .collection('readingGroups')
          .where('classId', isEqualTo: widget.selectedClass!.id)
          .where('isActive', isEqualTo: true)
          .get();

      // Sort alphabetically
      students.sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _students = students;
        _readingGroups = groupsSnapshot.docs
            .map((doc) => ReadingGroupModel.fromFirestore(doc))
            .toList()
          ..sort((a, b) {
            final orderCmp = a.sortOrder.compareTo(b.sortOrder);
            return orderCmp != 0 ? orderCmp : a.name.compareTo(b.name);
          });
        if (widget.editingAllocation != null) {
          // Already populated via _populateFromAllocation
        } else if (widget.preselectedStudentId != null &&
            students.any((s) => s.id == widget.preselectedStudentId)) {
          _selectAllStudents = false;
          _selectedStudentIds = [widget.preselectedStudentId!];
          _allocationType = AllocationType.byTitle;
        } else {
          _selectedStudentIds = students.map((s) => s.id).toList();
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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
      debugPrint('Error loading allocation reading level options: $error');
    }
  }

  String _formatLevelLabel(String? value) {
    if (value == null || value.trim().isEmpty) return 'Not set';
    if (_readingLevelOptions.isEmpty) return value.trim();
    return _readingLevelService.formatLevelLabel(
      value,
      options: _readingLevelOptions,
    );
  }

  String _formatLevelRangeLabel(String? start, String? end) {
    if (start == null || start.trim().isEmpty) return 'Level not set';
    final startLabel = _formatLevelLabel(start);
    if (end == null || end.trim().isEmpty) return startLabel;
    final endLabel = _formatLevelLabel(end);
    return '$startLabel – $endLabel';
  }

  bool _validate() {
    bool valid = true;
    setState(() {
      _bookTitleError = null;
      _levelError = null;
      _studentError = null;
    });

    if (widget.selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class')),
      );
      return false;
    }

    if (_allocationType == AllocationType.byTitle && _bookTitles.isEmpty) {
      setState(() => _bookTitleError = 'Add at least one book');
      valid = false;
    }

    if (_allocationType == AllocationType.byLevel &&
        (_levelRangeStart == null || _levelRangeStart!.trim().isEmpty)) {
      setState(() => _levelError = 'Choose a starting reading level');
      valid = false;
    }

    if (_allocationType == AllocationType.byLevel &&
        _readingLevelOptions.isNotEmpty &&
        _levelRangeStart != null &&
        _levelRangeEnd != null &&
        _readingLevelService.compareLevels(
              _levelRangeStart,
              _levelRangeEnd,
              options: _readingLevelOptions,
            ) >
            0) {
      setState(() => _levelError = 'End level must be at or above start level');
      valid = false;
    }

    if (!_selectAllStudents && _selectedStudentIds.isEmpty) {
      setState(() => _studentError = 'Select at least one student');
      valid = false;
    }

    return valid;
  }

  void _showPreview() {
    if (!_validate()) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AllocationPreviewSheet(
        type: _allocationType,
        cadence: _cadence,
        targetMinutes: int.tryParse(_minutesController.text) ?? 20,
        startDate: _startDate,
        endDate: _endDate,
        bookTitles: _bookTitles,
        levelStart: _levelRangeStart,
        levelEnd: _levelRangeEnd,
        studentCount:
            _selectAllStudents ? _students.length : _selectedStudentIds.length,
        isWholeClass: _selectAllStudents,
        isEditing: widget.editingAllocation != null,
        formatLevelRange: _formatLevelRangeLabel,
        onConfirm: _saveAllocation,
      ),
    );
  }

  Future<void> _notifyParentsOfNewAllocation(AllocationModel allocation) async {
    try {
      final String title;
      final String body;
      final teacherName = widget.teacher.fullName;
      final minutes = allocation.targetMinutes;

      switch (allocation.type) {
        case AllocationType.freeChoice:
          title = 'New Reading Goal';
          body = '$teacherName has set a reading goal: '
              '$minutes minutes of any book your child enjoys this week.';
        case AllocationType.byLevel:
          final levelRange = allocation.levelEnd != null
              ? 'Level ${allocation.levelStart}–${allocation.levelEnd}'
              : 'Level ${allocation.levelStart}';
          title = 'New Reading Assignment';
          body = '$teacherName assigned $levelRange reading: '
              '$minutes minutes this week.';
        case AllocationType.byTitle:
          final bookCount = allocation.bookTitles?.length ?? 0;
          final bookLabel = bookCount == 1 ? '1 book' : '$bookCount books';
          title = 'New Reading Assignment';
          body = '$teacherName assigned $bookLabel: '
              '$minutes minutes this week.';
      }

      await StaffNotificationService.instance.createCampaign(
        user: widget.teacher,
        title: title,
        body: body,
        messageType: 'reading_assignment',
        audienceType: allocation.studentIds.isEmpty ? 'classes' : 'students',
        classIds: [allocation.classId],
        studentIds: allocation.studentIds,
      );
    } catch (e) {
      // Notification failure should not block allocation success
      debugPrint('Failed to send allocation notification: $e');
    }
  }

  Future<void> _saveAllocation() async {
    setState(() => _isLoading = true);

    try {
      final sanitizedTitles = _bookTitles
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(growable: false);

      final assignmentItems = _allocationType == AllocationType.byTitle
          ? _buildInitialAssignmentItems(
              titles: sanitizedTitles,
              teacherId: widget.teacher.id,
            )
          : null;

      // Previously-read check for byTitle allocations
      if (assignmentItems != null) {
        final conflicts = await _checkPreviouslyReadConflicts(assignmentItems);
        if (conflicts.isNotEmpty && mounted) {
          setState(() => _isLoading = false);
          final proceed = await _showAllocationConflictDialog(conflicts);
          if (!proceed) return;
          setState(() => _isLoading = true);
        }
      }

      if (widget.editingAllocation != null) {
        // Update existing allocation
        await _allocationCrudService.updateAllocation(
          schoolId: widget.teacher.schoolId!,
          allocationId: widget.editingAllocation!.id,
          actorId: widget.teacher.id,
          type: _allocationType,
          cadence: _cadence,
          targetMinutes: int.tryParse(_minutesController.text) ?? 20,
          startDate: _startDate,
          endDate: _endDate,
          studentIds: _selectAllStudents ? [] : _selectedStudentIds,
          levelStart: _levelRangeStart,
          levelEnd: _levelRangeEnd,
          assignmentItems: assignmentItems,
        );
      } else {
        // Create new allocation
        final allocation = AllocationModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          schoolId: widget.selectedClass!.schoolId,
          classId: widget.selectedClass!.id,
          teacherId: widget.teacher.id,
          studentIds: _selectAllStudents ? [] : _selectedStudentIds,
          type: _allocationType,
          cadence: _cadence,
          targetMinutes: int.tryParse(_minutesController.text) ?? 20,
          startDate: _startDate,
          endDate: _endDate,
          levelStart: _levelRangeStart,
          levelEnd: _levelRangeEnd,
          bookTitles: sanitizedTitles.isEmpty ? null : sanitizedTitles,
          assignmentItems: assignmentItems,
          schemaVersion: assignmentItems == null ? 1 : 2,
          isRecurring: false,
          createdAt: DateTime.now(),
          createdBy: widget.teacher.id,
        );

        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.teacher.schoolId!)
            .collection('allocations')
            .doc(allocation.id)
            .set(allocation.toFirestore());

        // Fire-and-forget: notify parents of the new allocation
        _notifyParentsOfNewAllocation(allocation);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.editingAllocation != null
                ? 'Allocation updated'
                : 'Allocation created'),
            backgroundColor: LumiTokens.green,
          ),
        );
        _resetForm();
        widget.onSaved();
      }
    } catch (e, stackTrace) {
      debugPrint('Error saving allocation: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<AllocationBookItem> _buildInitialAssignmentItems({
    required List<String> titles,
    required String teacherId,
  }) {
    final now = DateTime.now();
    return titles.asMap().entries.map((entry) {
      final selectedBook = _selectedLibraryBooksByTitle[entry.value];
      return AllocationBookItem(
        id: 'manual_${now.millisecondsSinceEpoch}_${entry.key}',
        title: entry.value,
        bookId: selectedBook?.id,
        isbn: selectedBook?.isbn?.trim(),
        addedAt: now,
        addedBy: teacherId,
        metadata: {
          'source': selectedBook != null
              ? 'school_library_picker'
              : 'manual_allocation',
        },
      );
    }).toList(growable: false);
  }

  Future<void> _browseLibrary() async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LibraryPickerSheet(
        schoolId: schoolId,
        alreadyAdded: List<String>.from(_bookTitles),
        onBooksSelected: (books) {
          setState(() {
            for (final book in books) {
              if (!_bookTitles.contains(book.title)) {
                _bookTitles.add(book.title);
                _selectedLibraryBooksByTitle[book.title] = book;
              }
            }
            _bookTitleError = null;
          });
        },
      ),
    );
  }

  void _addManualTitle() {
    final text = _bookTitlesController.text.trim();
    if (text.isEmpty) return;

    if (_bookTitles.any((t) => t.toLowerCase() == text.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This book is already in the list')),
      );
      return;
    }

    setState(() {
      _bookTitles.add(text);
      _bookTitlesController.clear();
      _bookTitleError = null;
    });
  }

  void _resetForm() {
    setState(() {
      _allocationType = AllocationType.freeChoice;
      _cadence = AllocationCadence.weekly;
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 7));
      _minutesController.text = '20';
      if (widget.preselectedStudentId != null &&
          _students.any((s) => s.id == widget.preselectedStudentId)) {
        _selectAllStudents = false;
        _selectedStudentIds = [widget.preselectedStudentId!];
        _allocationType = AllocationType.byTitle;
      } else {
        _selectedStudentIds = _students.map((s) => s.id).toList();
        _selectAllStudents = true;
      }
      _levelRangeStart = null;
      _levelRangeEnd = null;
      _bookTitles.clear();
      _selectedLibraryBooksByTitle.clear();
      _bookTitlesController.clear();
      _bookTitleError = null;
      _levelError = null;
      _studentError = null;
      _studentSearchQuery = '';
      _selectByGroup = false;
      _selectedGroupIds.clear();
    });
  }

  void _updateEndDate() {
    setState(() {
      switch (_cadence) {
        case AllocationCadence.daily:
          _endDate = _startDate.add(const Duration(days: 1));
          break;
        case AllocationCadence.weekly:
          _endDate = _startDate.add(const Duration(days: 7));
          break;
        case AllocationCadence.fortnightly:
          _endDate = _startDate.add(const Duration(days: 14));
          break;
        case AllocationCadence.custom:
          break;
      }
    });
  }

  String _getCadenceLabel(AllocationCadence cadence) {
    switch (cadence) {
      case AllocationCadence.daily:
        return 'Daily';
      case AllocationCadence.weekly:
        return 'Weekly';
      case AllocationCadence.fortnightly:
        return 'Fortnightly';
      case AllocationCadence.custom:
        return 'Custom';
    }
  }

  // ─── Card callback handlers ─────────────────────────────────────────

  void _onTypeChanged(AllocationType type) {
    setState(() {
      _allocationType = type;
      _bookTitleError = null;
      _levelError = null;
    });
  }

  void _onStartLevelChanged(String? value) {
    setState(() {
      _levelRangeStart = value;
      _levelError = null;
      if (_levelRangeEnd != null &&
          value != null &&
          _readingLevelOptions.isNotEmpty &&
          _readingLevelService.compareLevels(
                value,
                _levelRangeEnd,
                options: _readingLevelOptions,
              ) >
              0) {
        _levelRangeEnd = value;
      }
    });
  }

  Future<void> _pickFrequency() async {
    final picked = await AllocationFrequencyPickerSheet.show(
      context,
      currentCadence: _cadence,
      getCadenceLabel: _getCadenceLabel,
    );
    if (picked != null) {
      setState(() {
        _cadence = picked;
        _updateEndDate();
      });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await AllocationDatePickerSheet.show(
      context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _updateEndDate();
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await AllocationDatePickerSheet.show(
      context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  void _setScopeMode({
    required bool allStudents,
    required bool byGroup,
  }) {
    setState(() {
      _selectAllStudents = allStudents;
      _selectByGroup = byGroup;
      _studentError = null;
      if (allStudents) {
        _selectedStudentIds = _students.map((s) => s.id).toList();
        _selectedGroupIds.clear();
      } else if (byGroup) {
        _selectedStudentIds.clear();
        _selectedGroupIds.clear();
      } else {
        _selectedGroupIds.clear();
      }
    });
  }

  void _onGroupSelectionChanged(String groupId, bool selected) {
    setState(() {
      if (selected) {
        _selectedGroupIds.add(groupId);
      } else {
        _selectedGroupIds.remove(groupId);
      }
      // Merge all selected groups' student IDs (deduplicated)
      final ids = <String>{};
      for (final gId in _selectedGroupIds) {
        final group = _readingGroups.firstWhere((g) => g.id == gId);
        ids.addAll(group.studentIds);
      }
      _selectedStudentIds = ids.toList();
      _studentError = null;
    });
  }

  void _onStudentToggled(String studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
        _studentError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedClass == null) {
      return Center(
        child: LumiEmptyCard(
          icon: Icons.class_,
          title: 'No class selected',
          message:
              'Please select a class from the dashboard to create an allocation.',
          accentColor: LumiTokens.green,
        ),
      );
    }

    // Show loading indicator while students are being fetched
    // to prevent the form from flickering with default values
    if (_isLoading && _students.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: LumiTokens.green),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Edit mode banner
            if (widget.editingAllocation != null) ...[
              _buildEditBanner(),
              const SizedBox(height: 12),
            ],

            // Reading Type Section
            AllocationReadingTypeCard(
              allocationType: _allocationType,
              levelsEnabled: _levelsEnabled,
              readingLevelOptions: _readingLevelOptions,
              levelRangeStart: _levelRangeStart,
              levelRangeEnd: _levelRangeEnd,
              bookTitles: _bookTitles,
              libraryBookTitles: _selectedLibraryBooksByTitle.keys.toSet(),
              bookTitleError: _bookTitleError,
              levelError: _levelError,
              bookTitlesController: _bookTitlesController,
              onTypeChanged: _onTypeChanged,
              onStartLevelChanged: _onStartLevelChanged,
              onEndLevelChanged: (value) =>
                  setState(() => _levelRangeEnd = value),
              onBrowseLibrary: _browseLibrary,
              onAddManualTitle: _addManualTitle,
              onRemoveTitle: (title) => setState(() {
                _bookTitles.remove(title);
                _selectedLibraryBooksByTitle.remove(title);
              }),
              onManualTextChanged: () => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Schedule Section
            AllocationScheduleCard(
              cadence: _cadence,
              cadenceLabel: _getCadenceLabel(_cadence),
              minutesController: _minutesController,
              startDate: _startDate,
              endDate: _endDate,
              onCadenceTap: _pickFrequency,
              onStartDateTap: _pickStartDate,
              onEndDateTap: _pickEndDate,
            ),
            const SizedBox(height: 16),

            // Students Section
            AllocationStudentScopeCard(
              students: _students,
              readingGroups: _readingGroups,
              selectAllStudents: _selectAllStudents,
              selectByGroup: _selectByGroup,
              selectedStudentIds: _selectedStudentIds,
              selectedGroupIds: _selectedGroupIds,
              studentSearchQuery: _studentSearchQuery,
              studentError: _studentError,
              levelsEnabled: _levelsEnabled,
              formatLevelLabel: _formatLevelLabel,
              onScopeChanged: (allStudents, byGroup) =>
                  _setScopeMode(allStudents: allStudents, byGroup: byGroup),
              onGroupToggled: _onGroupSelectionChanged,
              onStudentToggled: _onStudentToggled,
              onSelectAll: () => setState(() {
                _selectedStudentIds = _students.map((s) => s.id).toList();
                _studentError = null;
              }),
              onDeselectAll: () => setState(() => _selectedStudentIds.clear()),
              onSearchChanged: (v) => setState(() => _studentSearchQuery = v),
            ),
            const SizedBox(height: 16),

                // Assignment summary
                _buildSummaryCard(),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 16),
              child: _buildFloatingAction(),
            ),
          ),
        ],
      ),
    );
  }

  /// Whether the current form is a valid assignment. Drives the floating
  /// button: frosted + disabled while incomplete, solid green + tappable once
  /// ready. Mirrors [_validate] without the side effects.
  bool _isValid() {
    if (widget.selectedClass == null) return false;
    // Specific Books needs at least one title chosen.
    if (_allocationType == AllocationType.byTitle && _bookTitles.isEmpty) {
      return false;
    }
    // By Level needs a start level, with end at or above it.
    if (_allocationType == AllocationType.byLevel) {
      if (_levelRangeStart == null || _levelRangeStart!.trim().isEmpty) {
        return false;
      }
      if (_readingLevelOptions.isNotEmpty &&
          _levelRangeEnd != null &&
          _readingLevelService.compareLevels(
                _levelRangeStart,
                _levelRangeEnd,
                options: _readingLevelOptions,
              ) >
              0) {
        return false;
      }
    }
    // Student scope must resolve to at least one student.
    if (_selectAllStudents) {
      if (_students.isEmpty) return false;
    } else if (_selectedStudentIds.isEmpty) {
      return false;
    }
    return true;
  }

  /// Floating primary action — a frosted, translucent green pill while the
  /// assignment is incomplete, snapping to solid full-colour green and becoming
  /// tappable once the inputs make a valid assignment.
  Widget _buildFloatingAction() {
    final isEditing = widget.editingAllocation != null;
    final valid = _isValid();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          label: isEditing ? 'Review changes' : 'Review & assign',
          valid: valid,
        ),
        if (isEditing) ...[
          const SizedBox(height: 4),
          LumiTextButton(
            onPressed: widget.onEditCancelled,
            text: 'Cancel edit',
            color: LumiTokens.muted,
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton({required String label, required bool valid}) {
    final enabled = valid && !_isLoading;
    final contentColor = LumiTokens.paper.withValues(alpha: valid ? 1 : 0.85);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        boxShadow: valid
            ? [
                BoxShadow(
                  color: LumiTokens.green.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: valid ? 0 : 14,
            sigmaY: valid ? 0 : 14,
          ),
          child: Material(
            color: valid
                ? LumiTokens.green
                : LumiTokens.green.withValues(alpha: 0.45),
            child: InkWell(
              onTap: enabled ? _showPreview : null,
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                  border: valid
                      ? null
                      : Border.all(
                          color: LumiTokens.paper.withValues(alpha: 0.3)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(LumiTokens.paper),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.preview, size: 20, color: contentColor),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style:
                                LumiType.button.copyWith(color: contentColor),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final minutes = int.tryParse(_minutesController.text) ?? 20;

    final String typeLabel;
    switch (_allocationType) {
      case AllocationType.freeChoice:
        typeLabel = 'Free choice reading';
      case AllocationType.byLevel:
        typeLabel =
            'Reading level · ${_formatLevelRangeLabel(_levelRangeStart, _levelRangeEnd)}';
      case AllocationType.byTitle:
        final n = _bookTitles.length;
        typeLabel = n == 0 ? 'Specific books' : '$n book${n == 1 ? '' : 's'}';
    }

    final dateRange =
        '${DateFormat('MMM d').format(_startDate)} – ${DateFormat('MMM d').format(_endDate)}';
    final count =
        _selectAllStudents ? _students.length : _selectedStudentIds.length;
    final studentsLabel = _selectAllStudents
        ? 'Whole class · $count ${count == 1 ? 'student' : 'students'}'
        : '$count ${count == 1 ? 'student' : 'students'}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SUMMARY', style: LumiType.sectionLabel),
          const SizedBox(height: 10),
          Text(
            typeLabel,
            style: LumiType.body
                .copyWith(color: LumiTokens.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${_getCadenceLabel(_cadence)} · $minutes min · $dateRange',
            style: LumiType.caption,
          ),
          const SizedBox(height: 2),
          Text(studentsLabel, style: LumiType.caption),
        ],
      ),
    );
  }

  Widget _buildEditBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LumiTokens.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 16, color: LumiTokens.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Editing existing allocation. Changes will update the current allocation.',
              style: LumiType.caption.copyWith(color: LumiTokens.ink),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_ReadConflict>> _checkPreviouslyReadConflicts(
    List<AllocationBookItem> items,
  ) async {
    final service = IsbnAssignmentService();
    final conflicts = <_ReadConflict>[];
    final targetStudentIds = _selectAllStudents
        ? _students.map((s) => s.id).toList()
        : List<String>.from(_selectedStudentIds);
    if (targetStudentIds.isEmpty) return conflicts;

    // Fetch every target student's read-history in a few batched queries, then
    // match books in memory — replaces the old N-students × M-books sequential
    // reads (500+ round-trips for a "select-all" big class before the save).
    final readByStudent = await service.readBookIdsForStudents(targetStudentIds);

    for (final studentId in targetStudentIds) {
      final read = readByStudent[studentId] ?? const <String>{};
      for (final item in items) {
        // Same variant set the old studentHasPreviouslyReadBook checked.
        final variants = <String>{};
        if (item.bookId != null && item.bookId!.isNotEmpty) {
          variants.add(item.bookId!);
        }
        if (item.isbn != null && item.isbn!.isNotEmpty) {
          variants.add(item.isbn!);
          variants.add('isbn_${item.isbn!}');
        }
        if (variants.isEmpty) continue;
        if (variants.any(read.contains)) {
          final matches = _students.where((s) => s.id == studentId);
          final name = matches.isNotEmpty ? matches.first.firstName : studentId;
          conflicts
              .add(_ReadConflict(studentName: name, bookTitle: item.title));
        }
      }
    }
    return conflicts;
  }

  Future<bool> _showAllocationConflictDialog(
    List<_ReadConflict> conflicts,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: LumiTokens.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            ),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: LumiTokens.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_edu_rounded,
                    color: LumiTokens.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Books Previously Read', style: LumiType.subhead),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Some students may have already read these books:',
                  style: LumiType.caption,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    shrinkWrap: true,
                    children: conflicts
                        .map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '• ${c.studentName} — "${c.bookTitle}"',
                                style: LumiType.body
                                    .copyWith(color: LumiTokens.ink),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Do you still want to assign these books?',
                  style: LumiType.body.copyWith(
                    color: LumiTokens.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Go Back',
                  style: LumiType.button.copyWith(color: LumiTokens.muted),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: LumiTokens.green,
                  foregroundColor: LumiTokens.paper,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                ),
                child: const Text('Assign Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _ReadConflict {
  const _ReadConflict({required this.studentName, required this.bookTitle});
  final String studentName;
  final String bookTitle;
}
