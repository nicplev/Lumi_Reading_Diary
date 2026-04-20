import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/teacher_constants.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_card.dart';
import '../../../core/widgets/lumi/lumi_input.dart';
import '../../../core/widgets/lumi/teacher_alert_banner.dart';
import '../../../core/widgets/lumi/teacher_filter_chip.dart';
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
      final studentIds = widget.selectedClass!.studentIds;
      final students = <StudentModel>[];

      // Batch load in chunks of 30 (Firestore whereIn limit)
      for (var i = 0; i < studentIds.length; i += 30) {
        final chunk = studentIds.sublist(
          i,
          i + 30 > studentIds.length ? studentIds.length : i + 30,
        );
        final snapshot = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.teacher.schoolId)
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        students.addAll(snapshot.docs.map(StudentModel.fromFirestore));
      }

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
              ? 'Level ${allocation.levelStart}\u2013${allocation.levelEnd}'
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
            backgroundColor: AppColors.success,
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

  @override
  Widget build(BuildContext context) {
    if (widget.selectedClass == null) {
      return Center(
        child: LumiEmptyCard(
          icon: Icons.class_,
          title: 'No class selected',
          message:
              'Please select a class from the dashboard to create an allocation.',
          accentColor: AppColors.teacherPrimary,
        ),
      );
    }

    // Show loading indicator while students are being fetched
    // to prevent the form from flickering with default values
    if (_isLoading && _students.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.teacherPrimary),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Edit mode banner
            if (widget.editingAllocation != null) ...[
              TeacherAlertBanner(
                type: AlertBannerType.info,
                message:
                    'Editing existing allocation. Changes will update the current allocation.',
              ),
              const SizedBox(height: 12),
            ],

            // Reading Type Section
            _buildReadingTypeCard(),
            const SizedBox(height: 16),

            // Schedule Section
            _buildScheduleCard(),
            const SizedBox(height: 16),

            // Students Section
            _buildStudentsCard(),
            const SizedBox(height: 24),

            // Separator
            const Divider(color: AppColors.teacherBorder, thickness: 1),
            const SizedBox(height: 8),

            // Action Buttons
            LumiPrimaryButton(
              onPressed: _isLoading ? null : _showPreview,
              text: widget.editingAllocation != null
                  ? 'Review Changes'
                  : 'Review Allocation',
              isLoading: _isLoading,
              isFullWidth: true,
              icon: Icons.preview,
              color: AppColors.teacherPrimary,
            ),

            if (widget.editingAllocation != null) ...[
              const SizedBox(height: 8),
              Center(
                child: LumiTextButton(
                  onPressed: widget.onEditCancelled,
                  text: 'Cancel Edit',
                  color: AppColors.textSecondary,
                ),
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── Reading Type Card ──────────────────────────────────────────────

  Widget _buildReadingTypeCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.book, 'Reading Type'),
          const SizedBox(height: 12),

          // Info banner
          TeacherAlertBanner(
            type: AlertBannerType.info,
            message:
                'Reading levels and book selection will be customised based on your school\'s requirements.',
          ),
          const SizedBox(height: 16),

          // Type chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TeacherFilterChip(
                label: 'Free Choice',
                isActive: _allocationType == AllocationType.freeChoice,
                icon: Icons.menu_book_outlined,
                onTap: () => setState(() {
                  _allocationType = AllocationType.freeChoice;
                  _bookTitleError = null;
                  _levelError = null;
                }),
              ),
              if (_levelsEnabled)
                TeacherFilterChip(
                  label: 'By Level',
                  isActive: _allocationType == AllocationType.byLevel,
                  icon: Icons.bar_chart,
                  onTap: () => setState(() {
                    _allocationType = AllocationType.byLevel;
                    _bookTitleError = null;
                    _levelError = null;
                  }),
                ),
              TeacherFilterChip(
                label: 'Specific Books',
                isActive: _allocationType == AllocationType.byTitle,
                icon: Icons.library_books_outlined,
                onTap: () => setState(() {
                  _allocationType = AllocationType.byTitle;
                  _bookTitleError = null;
                  _levelError = null;
                }),
              ),
            ],
          ),

          // Level range fields
          if (_allocationType == AllocationType.byLevel) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LumiDropdown<String>(
                    label: 'Start Level',
                    hintText: 'Select level',
                    value: _levelRangeStart,
                    items: _readingLevelOptions.map((o) => o.value).toList(),
                    itemLabel: (v) {
                      final opt = _readingLevelOptions
                          .where((o) => o.value == v)
                          .firstOrNull;
                      return opt?.displayLabel ?? v;
                    },
                    errorText: _levelError,
                    onChanged: (value) {
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
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LumiDropdown<String?>(
                    label: 'End Level',
                    hintText: 'Optional',
                    value: _levelRangeEnd,
                    items: [
                      null,
                      ..._readingLevelOptions.map((o) => o.value),
                    ],
                    itemLabel: (v) {
                      if (v == null) return 'No end level';
                      final opt = _readingLevelOptions
                          .where((o) => o.value == v)
                          .firstOrNull;
                      return opt?.displayLabel ?? v;
                    },
                    onChanged: (value) =>
                        setState(() => _levelRangeEnd = value),
                  ),
                ),
              ],
            ),
          ],

          // Book selection fields
          if (_allocationType == AllocationType.byTitle) ...[
            const SizedBox(height: 16),

            // Added books
            if (_bookTitles.isNotEmpty) ...[
              ..._bookTitles.map((title) {
                final hasLibraryData =
                    _selectedLibraryBooksByTitle.containsKey(title);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.teacherPrimaryLight,
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusM),
                      border:
                          Border.all(color: AppColors.teacherBorder, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasLibraryData
                              ? Icons.local_library
                              : Icons.menu_book,
                          color: AppColors.teacherPrimary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: TeacherTypography.bodyMedium
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _bookTitles.remove(title);
                            _selectedLibraryBooksByTitle.remove(title);
                          }),
                          child: Icon(Icons.close,
                              color: AppColors.textSecondary, size: 18),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],

            // Error text
            if (_bookTitleError != null) ...[
              Text(
                _bookTitleError!,
                style:
                    TeacherTypography.caption.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: 8),
            ],

            // Browse library button
            LumiSecondaryButton(
              onPressed: _browseLibrary,
              text: 'Browse School Library',
              icon: Icons.search,
              isFullWidth: true,
              color: AppColors.teacherPrimary,
            ),
            const SizedBox(height: 10),

            // Manual entry
            Row(
              children: [
                Expanded(
                  child: LumiInput(
                    controller: _bookTitlesController,
                    hintText: 'Or type a title manually',
                    prefixIcon: const Icon(Icons.add, size: 20),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: _bookTitlesController.text.trim().isNotEmpty
                        ? _addManualTitle
                        : null,
                    icon: Icon(
                      Icons.add_circle,
                      color: _bookTitlesController.text.trim().isNotEmpty
                          ? AppColors.teacherPrimary
                          : AppColors.textSecondary,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Schedule Card ──────────────────────────────────────────────────

  Widget _buildScheduleCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.calendar_today, 'Schedule'),
          const SizedBox(height: 12),

          // Cadence + minutes row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await _FrequencyPickerSheet.show(
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
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Frequency',
                        style: TeacherTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.charcoal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.offWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.teacherBorder, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _getCadenceLabel(_cadence),
                                style: TeacherTypography.bodyMedium,
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down,
                                size: 16, color: AppColors.teacherPrimary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LumiInput(
                  label: 'Minutes Target',
                  controller: _minutesController,
                  keyboardType: TextInputType.number,
                  suffixIcon: Align(
                    widthFactor: 1.0,
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        'min',
                        style: TeacherTypography.bodySmall,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date range row
          Row(
            children: [
              Expanded(
                  child: _buildDateField('Start Date', _startDate, () async {
                final picked = await _DatePickerSheet.show(
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
              })),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildDateField('End Date', _endDate, () async {
                final picked = await _DatePickerSheet.show(
                  context,
                  initialDate: _endDate,
                  firstDate: _startDate,
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _endDate = picked);
                }
              })),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: AppColors.teacherPrimary),
              const SizedBox(width: 4),
              Text(
                () {
                  final days = _endDate.difference(_startDate).inDays;
                  return days == 1 ? '1-day window' : '$days-day window';
                }(),
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Students Card ──────────────────────────────────────────────────

  Widget _buildStudentsCard() {
    final filteredStudents = _studentSearchQuery.isEmpty
        ? _students
        : _students
            .where((s) => s.fullName
                .toLowerCase()
                .contains(_studentSearchQuery.toLowerCase()))
            .toList();

    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.groups, 'Students'),
          const SizedBox(height: 12),

          // Scope chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TeacherFilterChip(
                label: 'Whole Class (${_students.length})',
                isActive: _selectAllStudents && !_selectByGroup,
                icon: Icons.groups_outlined,
                onTap: () => _setScopeMode(allStudents: true, byGroup: false),
              ),
              TeacherFilterChip(
                label: 'Select Students',
                isActive: !_selectAllStudents && !_selectByGroup,
                icon: Icons.person_outline,
                onTap: () => _setScopeMode(allStudents: false, byGroup: false),
              ),
              if (_readingGroups.isNotEmpty)
                TeacherFilterChip(
                  label: 'By Group (${_readingGroups.length})',
                  isActive: _selectByGroup,
                  icon: Icons.workspaces_outlined,
                  onTap: () => _setScopeMode(allStudents: false, byGroup: true),
                ),
            ],
          ),

          if (_studentError != null && !_selectAllStudents) ...[
            const SizedBox(height: 8),
            Text(
              _studentError!,
              style: TeacherTypography.caption.copyWith(color: AppColors.error),
            ),
          ],

          // Group selection UI
          if (_selectByGroup) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: _readingGroups.isEmpty
                  ? Text(
                      'No groups found. Create groups in Settings > Reading Groups.',
                      style: TeacherTypography.caption
                          .copyWith(color: AppColors.textSecondary),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _readingGroups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final group = _readingGroups[index];
                        final isSelected = _selectedGroupIds.contains(group.id);
                        final groupColor = group.color != null
                            ? Color(int.parse(
                                group.color!.replaceFirst('#', '0xFF')))
                            : AppColors.teacherPrimary;
                        return GestureDetector(
                          onTap: () =>
                              _onGroupSelectionChanged(group.id, !isSelected),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.teacherPrimaryLight
                                  : AppColors.white,
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.teacherPrimary
                                        .withValues(alpha: 0.4)
                                    : AppColors.teacherBorder,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: groupColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group.name,
                                        style: TeacherTypography.bodyMedium
                                            .copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        '${group.studentIds.length} students',
                                        style: TeacherTypography.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: isSelected
                                      ? AppColors.teacherPrimary
                                      : AppColors.textSecondary,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_selectedGroupIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_selectedStudentIds.length} students selected from ${_selectedGroupIds.length} group${_selectedGroupIds.length == 1 ? '' : 's'}',
                style: TeacherTypography.caption
                    .copyWith(color: AppColors.teacherPrimary),
              ),
            ],
          ],

          if (!_selectAllStudents && !_selectByGroup) ...[
            const SizedBox(height: 12),

            // Search + select all/none row
            Row(
              children: [
                Expanded(
                  child: LumiSearchInput(
                    hintText: 'Search students...',
                    onChanged: (v) => setState(() => _studentSearchQuery = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                LumiTextButton(
                  onPressed: () => setState(() {
                    _selectedStudentIds = _students.map((s) => s.id).toList();
                    _studentError = null;
                  }),
                  text: 'Select All',
                  color: AppColors.teacherPrimary,
                ),
                const SizedBox(width: 4),
                LumiTextButton(
                  onPressed: () => setState(() {
                    _selectedStudentIds.clear();
                  }),
                  text: 'Deselect All',
                  color: AppColors.textSecondary,
                ),
                const Spacer(),
                Text(
                  '${_selectedStudentIds.length} selected',
                  style: TeacherTypography.caption,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Student list
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filteredStudents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final student = filteredStudents[index];
                  final isSelected = _selectedStudentIds.contains(student.id);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedStudentIds.remove(student.id);
                        } else {
                          _selectedStudentIds.add(student.id);
                          _studentError = null;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.teacherPrimaryLight
                            : AppColors.white,
                        borderRadius:
                            BorderRadius.circular(TeacherDimensions.radiusM),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.teacherPrimary.withValues(alpha: 0.4)
                              : AppColors.teacherBorder,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Initials avatar
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.teacherPrimary
                                  : AppColors.teacherPrimaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _initials(student.fullName),
                                style: TeacherTypography.caption.copyWith(
                                  color: isSelected
                                      ? AppColors.white
                                      : AppColors.teacherPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  student.fullName,
                                  style: TeacherTypography.bodyMedium
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (_levelsEnabled &&
                                    student.currentReadingLevel != null)
                                  Text(
                                    'Level: ${_formatLevelLabel(student.currentReadingLevel)}',
                                    style: TeacherTypography.caption,
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected
                                ? AppColors.teacherPrimary
                                : AppColors.textSecondary,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Shared Helpers ─────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.teacherPrimaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.teacherPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Text(title, style: TeacherTypography.h3),
      ],
    );
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

  Widget _buildDateField(String label, DateTime date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TeacherTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.teacherBorder, width: 1.2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(date),
                    style: TeacherTypography.bodyMedium,
                  ),
                ),
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.teacherPrimary),
              ],
            ),
          ),
        ],
      ),
    );
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '?';
  }

  Future<List<_ReadConflict>> _checkPreviouslyReadConflicts(
    List<AllocationBookItem> items,
  ) async {
    final service = IsbnAssignmentService();
    final conflicts = <_ReadConflict>[];
    final targetStudentIds = _selectAllStudents
        ? _students.map((s) => s.id).toList()
        : List<String>.from(_selectedStudentIds);

    for (final studentId in targetStudentIds) {
      for (final item in items) {
        if (item.bookId == null && item.isbn == null) continue;
        final hasRead = await service.studentHasPreviouslyReadBook(
          studentId: studentId,
          bookId: item.bookId,
          isbn: item.isbn,
        );
        if (hasRead) {
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_edu_rounded,
                    color: Color(0xFFFFA000),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Books Previously Read'),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Some students may have already read these books:',
                  style: TeacherTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
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
                                style: TeacherTypography.bodySmall,
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Do you still want to assign these books?',
                  style: TeacherTypography.bodySmall
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Go Back',
                  style: TeacherTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teacherPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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

// ─── Frequency Picker Sheet ──────────────────────────────────────────────────

class _FrequencyPickerSheet extends StatelessWidget {
  const _FrequencyPickerSheet({
    required this.currentCadence,
    required this.getCadenceLabel,
  });

  final AllocationCadence currentCadence;
  final String Function(AllocationCadence) getCadenceLabel;

  static Future<AllocationCadence?> show(
    BuildContext context, {
    required AllocationCadence currentCadence,
    required String Function(AllocationCadence) getCadenceLabel,
  }) {
    return showModalBottomSheet<AllocationCadence>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FrequencyPickerSheet(
        currentCadence: currentCadence,
        getCadenceLabel: getCadenceLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Select Frequency', style: TeacherTypography.h3),
          const SizedBox(height: 8),
          ...AllocationCadence.values.map((cadence) {
            final isSelected = cadence == currentCadence;
            return InkWell(
              onTap: () => Navigator.of(context).pop(cadence),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        getCadenceLabel(cadence),
                        style: TeacherTypography.bodyMedium.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected
                              ? AppColors.teacherPrimary
                              : AppColors.charcoal,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: AppColors.teacherPrimary,
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Date Picker Sheet ───────────────────────────────────────────────────────

class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final clamped = initialDate.isBefore(firstDate) ? firstDate : initialDate;
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DatePickerSheet(
        initialDate: clamped,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
  }

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Select Date', style: TeacherTypography.h3),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: AppColors.teacherPrimary,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                  ),
            ),
            child: CalendarDatePicker(
              initialDate: _selectedDate,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onDateChanged: (date) {
                setState(() => _selectedDate = date);
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(
                    'Cancel',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selectedDate),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teacherPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
