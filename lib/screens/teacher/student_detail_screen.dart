import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/comments/teacher_comments_sheet.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/reading_level_history_sheet.dart';
import '../../core/widgets/lumi/reading_level_picker_sheet.dart';
import '../../core/widgets/lumi/teacher_book_assignment_card.dart';
import '../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/student_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/allocation_model.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/widgets/lumi/persistent_cached_image.dart';
import '../../data/models/book_model.dart';
import '../../services/book_lookup_service.dart';
import '../../services/school_library_service.dart';
import '../../services/allocation_crud_service.dart';
import '../../services/firebase_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/reading_level_service.dart';
import '../../services/student_reading_level_service.dart';
import '../../data/providers/student_detail_providers.dart';
import 'student_detail/achievements_section.dart';
import 'student_detail/assigned_books_section.dart';
import 'student_detail/parent_comment_section.dart';
import 'student_detail/reading_history_section.dart';
import 'student_detail/reading_level_card.dart';
import 'student_detail/reading_level_labels.dart';
import 'student_detail/reading_log_snapshot.dart';
import 'student_detail/feelings_section.dart';
import 'student_detail/group_badges_section.dart';
import 'student_detail/stats_row_section.dart';
import 'teacher_log_reading_sheet.dart';

/// Student Detail Screen
///
/// Shows student profile, stats, assigned books, and latest parent comment.
/// Per spec: avatar header, 2-col stats, assigned books list, parent comment.

class StudentDetailScreen extends StatefulWidget {
  final UserModel teacher;
  final StudentModel student;
  final ClassModel? classModel;

  /// Test seam (same pattern as TeacherClassroomScreen): defaults to the
  /// app-wide instance in production.
  final FirebaseFirestore? firestore;

  const StudentDetailScreen({
    super.key,
    required this.teacher,
    required this.student,
    this.classModel,
    this.firestore,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  late final FirebaseFirestore _firestore;
  late final AllocationCrudService _allocationCrudService;
  late final ReadingLevelService _readingLevelService;
  late final StudentReadingLevelService _studentReadingLevelService;
  List<ReadingLevelOption> _readingLevelOptions = const [];
  bool _levelsEnabled = false;
  StudentModel? _studentOverride;

  StudentModel get _currentStudent => _studentOverride ?? widget.student;

  StudentDetailLookup get _lookup => StudentDetailLookup(
        schoolId: widget.student.schoolId,
        classId: widget.student.classId,
        studentId: widget.student.id,
      );
  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseService.instance.firestore;
    _allocationCrudService = AllocationCrudService(firestore: _firestore);
    _readingLevelService = ReadingLevelService(firestore: _firestore);
    _studentReadingLevelService = StudentReadingLevelService(
      firestore: _firestore,
      readingLevelService: _readingLevelService,
    );
    _loadReadingLevelOptions();
  }

  @override
  void didUpdateWidget(covariant StudentDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final studentChanged = oldWidget.student.id != widget.student.id;

    if (studentChanged) {
      _studentOverride = null;
    }

    if (oldWidget.student.schoolId != widget.student.schoolId) {
      _loadReadingLevelOptions(forceRefresh: true);
    }

  }

  Future<void> _loadReadingLevelOptions({bool forceRefresh = false}) async {
    try {
      final options = await _readingLevelService.loadSchoolLevels(
        widget.student.schoolId,
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

    final options = await _readingLevelService.loadSchoolLevels(
      widget.student.schoolId,
    );
    if (mounted) {
      setState(() => _readingLevelOptions = options);
    } else {
      _readingLevelOptions = options;
    }
    return options;
  }

  Future<void> _openAssignFlow() async {
    try {
      var classModel = widget.classModel;
      if (classModel == null) {
        final classDoc = await _firestore
            .collection('schools')
            .doc(widget.student.schoolId)
            .collection('classes')
            .doc(widget.student.classId)
            .get();
        if (!classDoc.exists) {
          if (!mounted) return;
          showLumiToast(
            message: 'Class not found for this student',
            type: LumiToastType.error,
          );
          return;
        }
        classModel = ClassModel.fromFirestore(classDoc);
      }

      if (!mounted) return;
      await context.push(
        '/teacher/allocation',
        extra: {
          'teacher': widget.teacher,
          'selectedClass': classModel,
          'preselectedStudentId': widget.student.id,
        },
      );
    } catch (_) {
      if (!mounted) return;
      showLumiToast(
        message: 'Could not open assignment flow',
        type: LumiToastType.error,
      );
    }
  }

  Future<void> _openIsbnScannerFlow() async {
    try {
      var classModel = widget.classModel;
      if (classModel == null) {
        final classDoc = await _firestore
            .collection('schools')
            .doc(widget.student.schoolId)
            .collection('classes')
            .doc(widget.student.classId)
            .get();
        if (!classDoc.exists) {
          if (!mounted) return;
          showLumiToast(
            message: 'Class not found for this student',
            type: LumiToastType.error,
          );
          return;
        }
        classModel = ClassModel.fromFirestore(classDoc);
      }

      if (!mounted) return;
      final result = await context.push(
        '/teacher/isbn-scanner',
        extra: {
          'teacher': widget.teacher,
          'student': widget.student,
          'classModel': classModel,
        },
      );

      if (!mounted || result == null) return;
      if (result is! Map<String, dynamic>) return;

      final scannedCount = (result['scannedCount'] as num?)?.toInt() ?? 0;
      final totalAssigned =
          (result['totalAssignedBooks'] as num?)?.toInt() ?? 0;

      showLumiToast(
        message: scannedCount > 0
            ? 'Scanned $scannedCount book(s). $totalAssigned assigned this week.'
            : 'No ISBN scans captured.',
        type: scannedCount > 0 ? LumiToastType.success : LumiToastType.info,
      );
    } catch (_) {
      if (!mounted) return;
      showLumiToast(
        message: 'Could not open ISBN scanner',
        type: LumiToastType.error,
      );
    }
  }

  void _showBookActionsSheet(AssignedBookViewData book) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiTokens.radiusXL),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: LumiTokens.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text(book.title, style: LumiType.subhead),
            const SizedBox(height: 16),
            _buildSheetAction(
              icon: Icons.swap_horiz_rounded,
              label: 'Swap',
              onTap: () {
                Navigator.pop(context);
                _handleBookAction(book, TeacherBookCardAction.swap);
              },
            ),
            _buildSheetAction(
              icon: Icons.refresh_rounded,
              label: 'Keep next week',
              onTap: () {
                Navigator.pop(context);
                _handleBookAction(book, TeacherBookCardAction.keepNextCycle);
              },
            ),
            _buildSheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Remove',
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                _handleBookAction(book, TeacherBookCardAction.remove);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? AppColors.error : LumiTokens.ink;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: LumiType.body.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  Future<void> _handleBookAction(
    AssignedBookViewData book,
    TeacherBookCardAction action,
  ) async {
    if (!book.canMutateAssignment) return;

    final allocationId = book.allocationId!;
    final itemId = book.assignmentItemId!;

    try {
      switch (action) {
        case TeacherBookCardAction.remove:
          await _removeBookAssignment(
            allocationId: allocationId,
            itemId: itemId,
            title: book.title,
          );
          break;
        case TeacherBookCardAction.swap:
          await _swapBookAssignment(
            allocationId: allocationId,
            itemId: itemId,
            currentTitle: book.title,
          );
          break;
        case TeacherBookCardAction.edit:
          await _editBookAssignment(
            allocationId: allocationId,
            itemId: itemId,
            currentTitle: book.title,
          );
          break;
        case TeacherBookCardAction.keepNextCycle:
          await _keepBookNextCycle(
            allocationId: allocationId,
            itemId: itemId,
            title: book.title,
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      showLumiToast(
        message: 'Could not update assignment: $e',
        type: LumiToastType.error,
      );
    }
  }

  Future<void> _removeBookAssignment({
    required String allocationId,
    required String itemId,
    required String title,
  }) async {
    final scope = await _pickActionScope(actionLabel: 'Remove');
    if (scope == null) return;
    final forWholeClass = scope == _AssignmentEditScope.wholeClass;
    final confirmed = await _confirmDestructiveAction(
      title: 'Remove "$title"?',
      message: forWholeClass
          ? 'This removes the book for the whole class.'
          : 'This removes the book for ${widget.student.firstName} only.',
      confirmLabel: forWholeClass ? 'Remove for class' : 'Remove for student',
    );
    if (!confirmed) return;

    if (forWholeClass) {
      await _allocationCrudService.removeBookGlobally(
        schoolId: widget.student.schoolId,
        allocationId: allocationId,
        actorId: widget.teacher.id,
        itemId: itemId,
      );
      if (!mounted) return;
      showLumiToast(
        message: 'Removed "$title" for the whole class.',
        type: LumiToastType.success,
      );
      return;
    }

    await _allocationCrudService.removeBookForStudents(
      schoolId: widget.student.schoolId,
      allocationId: allocationId,
      actorId: widget.teacher.id,
      itemId: itemId,
      studentIds: [widget.student.id],
    );
    if (!mounted) return;
    showLumiToast(
      message: 'Removed "$title" for ${widget.student.firstName}.',
      type: LumiToastType.success,
    );
  }

  Future<void> _swapBookAssignment({
    required String allocationId,
    required String itemId,
    required String currentTitle,
  }) async {
    // Step 1: Pick swap method
    final selectedBook = await _showSwapMethodPicker();
    if (selectedBook == null || !mounted) return;

    // Step 2: Pick scope
    final scope = await _pickActionScope(actionLabel: 'Swap');
    if (scope == null || !mounted) return;

    // Step 3: Execute swap with full book data
    final nextTitle = selectedBook.title;
    final nextBookId = selectedBook.id;
    final nextIsbn = selectedBook.isbn;
    final nextMetadata = <String, dynamic>{
      'source': 'library_swap',
      if (selectedBook.coverImageUrl != null)
        'coverImageUrl': selectedBook.coverImageUrl,
    };

    if (scope == _AssignmentEditScope.wholeClass) {
      await _allocationCrudService.swapBookGlobally(
        schoolId: widget.student.schoolId,
        allocationId: allocationId,
        actorId: widget.teacher.id,
        removeItemId: itemId,
        nextTitle: nextTitle,
        nextBookId: nextBookId,
        nextIsbn: nextIsbn,
        nextMetadata: nextMetadata,
      );
      if (!mounted) return;
      showLumiToast(
        message: 'Swapped "$currentTitle" for whole class.',
        type: LumiToastType.success,
      );
      return;
    }

    await _allocationCrudService.swapBookForStudents(
      schoolId: widget.student.schoolId,
      allocationId: allocationId,
      actorId: widget.teacher.id,
      removeItemId: itemId,
      studentIds: [widget.student.id],
      nextTitle: nextTitle,
      nextBookId: nextBookId,
      nextIsbn: nextIsbn,
      nextMetadata: nextMetadata,
    );
    if (!mounted) return;
    showLumiToast(
      message: 'Swapped "$currentTitle" for ${widget.student.firstName}.',
      type: LumiToastType.success,
    );
  }

  /// Shows a bottom sheet letting the teacher choose between library browse
  /// or ISBN scan to find a replacement book.
  Future<BookModel?> _showSwapMethodPicker() async {
    final method = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiTokens.radiusXL),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: LumiTokens.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text('Swap Book', style: LumiType.subhead),
            const SizedBox(height: 16),
            _buildSwapMethodTile(
              icon: Icons.menu_book_rounded,
              label: 'Choose from Library',
              subtitle: 'Browse your school\'s scanned books',
              onTap: () => Navigator.pop(context, 'library'),
            ),
            const SizedBox(height: 8),
            _buildSwapMethodTile(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan ISBN Barcode',
              subtitle: 'Scan the replacement book\'s barcode',
              onTap: () => Navigator.pop(context, 'scan'),
            ),
          ],
        ),
      ),
    );

    if (method == null || !mounted) return null;

    if (method == 'library') {
      return showModalBottomSheet<BookModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _BookPickerSheet(schoolId: widget.student.schoolId),
      );
    }

    if (method == 'scan') {
      return Navigator.push<BookModel>(
        context,
        MaterialPageRoute(
          builder: (_) => _SwapScannerScreen(
            schoolId: widget.student.schoolId,
            actorId: widget.teacher.id,
          ),
        ),
      );
    }

    return null;
  }

  Widget _buildSwapMethodTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: LumiTokens.cream,
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: LumiTokens.tintGreen,
                  borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
                ),
                child: Icon(icon, size: 18, color: LumiTokens.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style:
                          LumiType.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(subtitle, style: LumiType.caption),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: LumiTokens.muted.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editBookAssignment({
    required String allocationId,
    required String itemId,
    required String currentTitle,
  }) async {
    final nextTitle = await _promptBookTitle(
      title: 'Edit Book',
      hintText: 'Book title',
      initialValue: currentTitle,
    );
    if (nextTitle == null) return;
    if (nextTitle == currentTitle.trim()) return;

    final scope = await _pickActionScope(actionLabel: 'Edit');
    if (scope == null) return;

    if (scope == _AssignmentEditScope.wholeClass) {
      await _allocationCrudService.updateBookGlobally(
        schoolId: widget.student.schoolId,
        allocationId: allocationId,
        actorId: widget.teacher.id,
        itemId: itemId,
        title: nextTitle,
      );
      if (!mounted) return;
      showLumiToast(
        message: 'Updated "$currentTitle" for whole class.',
        type: LumiToastType.success,
      );
      return;
    }

    await _allocationCrudService.swapBookForStudents(
      schoolId: widget.student.schoolId,
      allocationId: allocationId,
      actorId: widget.teacher.id,
      removeItemId: itemId,
      studentIds: [widget.student.id],
      nextTitle: nextTitle,
      nextMetadata: const {'source': 'student_edit'},
    );
    if (!mounted) return;
    showLumiToast(
      message: 'Updated "$currentTitle" for ${widget.student.firstName}.',
      type: LumiToastType.success,
    );
  }

  Future<void> _keepBookNextCycle({
    required String allocationId,
    required String itemId,
    required String title,
  }) async {
    // Look up the allocation doc to find the full AllocationBookItem
    final doc = await _firestore
        .collection('schools')
        .doc(widget.student.schoolId)
        .collection('allocations')
        .doc(allocationId)
        .get();
    if (!doc.exists) {
      if (!mounted) return;
      showLumiToast(
        message: 'Allocation not found.',
        type: LumiToastType.error,
      );
      return;
    }

    final allocation = AllocationModel.fromFirestore(doc);
    final items =
        allocation.effectiveAssignmentItemsForStudent(widget.student.id);
    final item = items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      if (!mounted) return;
      showLumiToast(
        message: 'Book item not found in allocation.',
        type: LumiToastType.error,
      );
      return;
    }

    final assignmentService = IsbnAssignmentService();
    final result = await assignmentService.reassignBooksToNextCycle(
      schoolId: widget.student.schoolId,
      classId: widget.student.classId,
      studentId: widget.student.id,
      teacherId: widget.teacher.id,
      itemsToKeep: [item],
      sourceAllocationId: allocationId,
      targetMinutes: allocation.targetMinutes,
    );

    if (!mounted) return;
    if (result.alreadyAssignedCount > 0) {
      showLumiToast(
        message: '"$title" is already assigned next week.',
        type: LumiToastType.info,
      );
    } else {
      showLumiToast(
        message: '"$title" kept for next week.',
        type: LumiToastType.success,
      );
    }
  }

  Future<String?> _promptBookTitle({
    required String title,
    required String hintText,
    required String initialValue,
  }) async {
    var draftValue = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: initialValue,
            autofocus: true,
            decoration: InputDecoration(hintText: hintText),
            textInputAction: TextInputAction.done,
            onChanged: (value) => draftValue = value,
            onFieldSubmitted: (value) =>
                Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(draftValue.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<_AssignmentEditScope?> _pickActionScope({
    required String actionLabel,
  }) async {
    return showModalBottomSheet<_AssignmentEditScope>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusLarge)),
      ),
      builder: (context) =>
          _buildActionScopeSheetBody(actionLabel: actionLabel),
    );
  }

  Future<bool> _confirmDestructiveAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
              ),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _openTeacherLogSheet() async {
    await TeacherLogReadingSheet.show(
      context: context,
      teacher: widget.teacher,
      student: widget.student,
    );
  }

  Future<void> _showRenewSheet() async {
    // Fetch current allocations for this student's class
    final snapshot = await _firestore
        .collection('schools')
        .doc(widget.student.schoolId)
        .collection('allocations')
        .where('classId', isEqualTo: widget.student.classId)
        .where('isActive', isEqualTo: true)
        .get();

    final allocations =
        snapshot.docs.map((doc) => AllocationModel.fromFirestore(doc)).toList();

    // Collect active assignment items for this student
    final now = DateTime.now();
    final currentItems = <_RenewableBookItem>[];
    for (final allocation in allocations) {
      final withinWindow = !allocation.startDate.isAfter(now) &&
          !allocation.endDate.isBefore(now);
      final appliesToStudent = allocation.isForWholeClass ||
          allocation.studentIds.contains(widget.student.id);
      if (!withinWindow || !appliesToStudent) continue;
      if (allocation.type != AllocationType.byTitle) continue;

      final items =
          allocation.effectiveAssignmentItemsForStudent(widget.student.id);
      for (final item in items) {
        if (item.title.trim().isEmpty) continue;
        currentItems.add(_RenewableBookItem(
          item: item,
          allocationId: allocation.id,
          targetMinutes: allocation.targetMinutes,
        ));
      }
    }

    if (currentItems.isEmpty) {
      if (!mounted) return;
      showLumiToast(
        message: 'No books to renew.',
        type: LumiToastType.info,
      );
      return;
    }

    if (!mounted) return;
    final selected = await showModalBottomSheet<List<_RenewableBookItem>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusLarge)),
      ),
      builder: (context) => _RenewBooksSheet(items: currentItems),
    );

    if (selected == null || selected.isEmpty) return;

    final assignmentService = IsbnAssignmentService();
    var keptCount = 0;
    var alreadyCount = 0;
    var failedCount = 0;

    // Per-book try/catch so one failure (e.g. offline mid-loop) doesn't abort
    // the rest and leave a silent partial renew — report exactly what happened.
    for (final entry in selected) {
      try {
        final result = await assignmentService.reassignBooksToNextCycle(
          schoolId: widget.student.schoolId,
          classId: widget.student.classId,
          studentId: widget.student.id,
          teacherId: widget.teacher.id,
          itemsToKeep: [entry.item],
          sourceAllocationId: entry.allocationId,
          targetMinutes: entry.targetMinutes,
        );
        keptCount += result.keptCount;
        alreadyCount += result.alreadyAssignedCount;
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;
    final String message;
    final LumiToastType type;
    if (failedCount == 0) {
      message = alreadyCount > 0
          ? '$keptCount book(s) kept for next week ($alreadyCount already assigned).'
          : '$keptCount book(s) kept for next week.';
      type = LumiToastType.success;
    } else if (keptCount == 0) {
      message = "Couldn't renew books. Please try again.";
      type = LumiToastType.error;
    } else {
      message = '$keptCount book(s) kept, $failedCount failed — please retry.';
      type = LumiToastType.warning;
    }
    showLumiToast(message: message, type: type);
  }

  Widget _buildActionScopeSheetBody({
    required String actionLabel,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: LumiTokens.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$actionLabel scope',
                style: LumiType.subhead,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose where this change should apply.',
                style: LumiType.caption,
              ),
            ),
            const SizedBox(height: 12),
            _ScopeOptionTile(
              icon: Icons.person_outline,
              title: '$actionLabel for ${widget.student.firstName}',
              subtitle: 'Only this student',
              onTap: () =>
                  Navigator.of(context).pop(_AssignmentEditScope.studentOnly),
            ),
            const SizedBox(height: 8),
            _ScopeOptionTile(
              icon: Icons.groups_2_outlined,
              title: 'Apply to whole class',
              subtitle: 'All students in this allocation',
              onTap: () =>
                  Navigator.of(context).pop(_AssignmentEditScope.wholeClass),
            ),
          ],
        ),
      ),
    );
  }
  /// denormalized comment state the [CommentThread] needs to read and post.
  ReadingLogModel _toReadingLogModel(ReadingLogSnapshot snap) {
    return ReadingLogModel(
      id: snap.id,
      studentId: _currentStudent.id,
      parentId: snap.parentId ?? '',
      schoolId: _currentStudent.schoolId,
      classId: _currentStudent.classId,
      date: snap.date,
      minutesRead: snap.minutesRead,
      targetMinutes: snap.targetMinutes,
      status: LogStatus.values.firstWhere(
        (e) => e.toString() == 'LogStatus.${snap.status}',
        orElse: () => LogStatus.pending,
      ),
      bookTitles: snap.bookTitles,
      notes: snap.notes,
      createdAt: snap.createdAt,
      comprehensionAudioPath: snap.comprehensionAudioPath,
      comprehensionAudioDurationSec: snap.comprehensionAudioDurationSec,
      comprehensionAudioUploaded: snap.comprehensionAudioUploaded,
      lastCommentAt: snap.lastCommentAt,
      lastCommentByRole: snap.lastCommentByRole,
      commentsViewedAt: snap.commentsViewedAt,
    );
  }

  /// Opens the comment thread for [snap]'s log in the shared teacher sheet.
  void _openLogComments(ReadingLogSnapshot snap) {
    openTeacherCommentsSheet(
      context,
      log: _toReadingLogModel(snap),
      studentName: _currentStudent.fullName,
    );
  }

  Future<void> _showReadingLevelPicker() async {
    try {
      final options = await _ensureReadingLevelOptionsLoaded();
      if (!mounted) return;

      final normalizedCurrent = _readingLevelService.normalizeLevel(
        _currentStudent.currentReadingLevel,
        options: options,
      );
      final currentDisplayLabel = normalizedCurrent == null
          ? null
          : _readingLevelService.formatLevelLabel(
              normalizedCurrent,
              options: options,
            );

      final result = await ReadingLevelPickerSheet.show(
        context,
        studentName: _currentStudent.fullName,
        levelSystemLabel: _readingLevelService.schemaDisplayName(options),
        options: options,
        currentLevelValue: normalizedCurrent,
        currentDisplayLabel: currentDisplayLabel,
        rawStoredLevel: _currentStudent.currentReadingLevel,
      );

      if (!mounted || result == null) return;
      await _applyReadingLevelChange(
        newLevel: result.levelValue,
        reason: result.reason,
      );
    } catch (error) {
      if (!mounted) return;
      showLumiToast(
        message: 'Could not open reading level picker: $error',
        type: LumiToastType.error,
      );
    }
  }

  Future<void> _moveReadingLevel({required bool increase}) async {
    try {
      final options = await _ensureReadingLevelOptionsLoaded();
      final nextOption = increase
          ? _readingLevelService.nextLevel(
              _currentStudent.currentReadingLevel,
              options: options,
            )
          : _readingLevelService.previousLevel(
              _currentStudent.currentReadingLevel,
              options: options,
            );
      if (nextOption == null) return;

      await _applyReadingLevelChange(
        newLevel: nextOption.value,
        reason: null,
      );
    } catch (error) {
      if (!mounted) return;
      showLumiToast(
        message: 'Could not update reading level: $error',
        type: LumiToastType.error,
      );
    }
  }

  Future<void> _applyReadingLevelChange({
    required String? newLevel,
    String? reason,
  }) async {
    final options = await _ensureReadingLevelOptionsLoaded();
    final didUpdate = await _studentReadingLevelService.updateStudentLevel(
      actor: widget.teacher,
      student: _currentStudent,
      options: options,
      newLevel: newLevel,
      reason: reason,
      source: StudentReadingLevelService.sourceTeacher,
    );

    if (!mounted) return;

    if (didUpdate) {
      setState(() {
        _studentOverride = _studentWithUpdatedLevel(
          current: _currentStudent,
          newLevel: newLevel,
          options: options,
        );
      });
    }

    showLumiToast(
      message:
          didUpdate ? 'Reading level updated' : 'No reading level change saved',
      type: didUpdate ? LumiToastType.success : LumiToastType.info,
    );
  }

  StudentModel _studentWithUpdatedLevel({
    required StudentModel current,
    required String? newLevel,
    required List<ReadingLevelOption> options,
  }) {
    return StudentModel(
      id: current.id,
      firstName: current.firstName,
      lastName: current.lastName,
      studentId: current.studentId,
      schoolId: current.schoolId,
      classId: current.classId,
      currentReadingLevel: newLevel,
      currentReadingLevelIndex: _readingLevelService.sortIndexForLevel(
        newLevel,
        options: options,
      ),
      readingLevelUpdatedAt: DateTime.now(),
      readingLevelUpdatedBy: widget.teacher.id,
      readingLevelSource: StudentReadingLevelService.sourceTeacher,
      parentIds: current.parentIds,
      dateOfBirth: current.dateOfBirth,
      profileImageUrl: current.profileImageUrl,
      isActive: current.isActive,
      createdAt: current.createdAt,
      enrolledAt: current.enrolledAt,
      additionalInfo: current.additionalInfo,
      levelHistory: current.levelHistory,
      stats: current.stats,
    );
  }

  Future<void> _showReadingLevelHistory() async {
    try {
      final options = await _ensureReadingLevelOptionsLoaded();
      if (!mounted) return;

      await ReadingLevelHistorySheet.show(
        context,
        studentName: _currentStudent.fullName,
        eventsStream: _studentReadingLevelService.watchReadingLevelEvents(
          schoolId: _currentStudent.schoolId,
          studentId: _currentStudent.id,
        ),
        levelOptions: options,
        readingLevelService: _readingLevelService,
      );
    } catch (error) {
      if (!mounted) return;
      showLumiToast(
        message: 'Could not load reading level history: $error',
        type: LumiToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.paper,
        foregroundColor: LumiTokens.ink,
        elevation: 0,
        toolbarHeight: 64,
        surfaceTintColor: LumiTokens.paper,
        title: Row(
          children: [
            StudentAvatar.fromStudent(_currentStudent, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentStudent.fullName,
                    style: LumiType.subhead,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  _buildLastReadIndicator(),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_levelsEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TeacherReadingLevelPill(
                label: readingLevelCompactLabel(
                  _currentStudent,
                  options: _readingLevelOptions,
                  service: _readingLevelService,
                ),
                isUnset: isReadingLevelUnset(_currentStudent),
                isUnresolved: isReadingLevelUnresolved(
                  _currentStudent,
                  options: _readingLevelOptions,
                  service: _readingLevelService,
                ),
                onTap: _showReadingLevelPicker,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewPaddingOf(context).bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group badges
            GroupBadgesSection(
              firestore: _firestore,
              schoolId: widget.student.schoolId,
              classId: widget.student.classId,
              studentId: widget.student.id,
            ),

            // Stats
            StatsRowSection(student: _currentStudent),
            const SizedBox(height: 20),

            if (_levelsEnabled) ...[
              ReadingLevelCard(
                student: _currentStudent,
                options: _readingLevelOptions,
                readingLevelService: _readingLevelService,
                onMoveLevel: _moveReadingLevel,
                onShowHistory: _showReadingLevelHistory,
                onShowPicker: _showReadingLevelPicker,
              ),
              const SizedBox(height: 20),
            ],

            // Assigned Books section
            AssignedBooksSection(
              lookup: _lookup,
              firestore: _firestore,
              teacherId: widget.teacher.id,
              onLogReading: _openTeacherLogSheet,
              onRenew: _showRenewSheet,
              onScanIsbn: _openIsbnScannerFlow,
              onAssignBooks: _openAssignFlow,
              onBookAction: _handleBookAction,
              onBookTap: _showBookActionsSheet,
            ),
            const SizedBox(height: 20),

            // Reading Feelings tracker
            FeelingsSection(lookup: _lookup),
            const SizedBox(height: 20),

            // Reading History
            ReadingHistorySection(
              lookup: _lookup,
              onViewAll: () => context.push(
                '/teacher/student-reading-history/${widget.student.id}',
                extra: {'student': _currentStudent},
              ),
              onOpenLogComments: _openLogComments,
            ),
            const SizedBox(height: 20),

            // Latest Parent Comment
            ParentCommentSection(
              lookup: _lookup,
              firestore: _firestore,
              onOpenLogComments: _openLogComments,
            ),
            const SizedBox(height: 20),

            // Achievements
            AchievementsSection(
              firestore: _firestore,
              schoolId: widget.student.schoolId,
              studentId: widget.student.id,
              onOpenAchievements: _openAchievements,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLastReadIndicator() {
    final lastRead = _currentStudent.stats?.lastReadingDate;
    final String label;
    final Color color;

    if (lastRead == null) {
      label = 'No reading logged yet';
      color = LumiTokens.muted;
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastDay = DateTime(lastRead.year, lastRead.month, lastRead.day);
      final diff = today.difference(lastDay).inDays;

      if (diff == 0) {
        label = 'Last read today';
        color = AppColors.success;
      } else if (diff == 1) {
        label = 'Last read yesterday';
        color = LumiTokens.green;
      } else if (diff < 7) {
        label = 'Last read $diff days ago';
        color = AppColors.warmOrange;
      } else {
        label =
            'Last read ${(diff / 7).floor()} week${diff >= 14 ? 's' : ''} ago';
        color = AppColors.error;
      }
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: LumiType.caption.copyWith(color: LumiTokens.muted),
        ),
      ],
    );
  }

  void _openAchievements() {
    final student = _currentStudent;
    context.push(
      '/teacher/student-achievements/${student.id}',
      extra: {
        'teacher': widget.teacher,
        'student': student,
      },
    );
  }

}

enum _AssignmentEditScope {
  studentOnly,
  wholeClass,
}

class _ScopeOptionTile extends StatelessWidget {
  const _ScopeOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          border: Border.all(color: LumiTokens.rule),
          color: LumiTokens.paper,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: LumiTokens.tintGreen.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              ),
              child: Icon(icon, color: LumiTokens.green, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LumiType.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: LumiType.caption,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: LumiTokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _RenewableBookItem {
  const _RenewableBookItem({
    required this.item,
    required this.allocationId,
    required this.targetMinutes,
  });

  final AllocationBookItem item;
  final String allocationId;
  final int targetMinutes;
}

class _RenewBooksSheet extends StatefulWidget {
  const _RenewBooksSheet({required this.items});

  final List<_RenewableBookItem> items;

  @override
  State<_RenewBooksSheet> createState() => _RenewBooksSheetState();
}

class _RenewBooksSheetState extends State<_RenewBooksSheet> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    // All checked by default
    _selected = Set<int>.from(
      List.generate(widget.items.length, (i) => i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: LumiTokens.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Keep books for next week',
                style: LumiType.subhead,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Uncheck books being returned',
                style: LumiType.caption,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(widget.items.length, (i) {
              final item = widget.items[i];
              final title =
                  IsbnAssignmentService.sanitizeDisplayTitle(item.item.title);
              return CheckboxListTile(
                title: Text(
                  title,
                  style: LumiType.body,
                ),
                value: _selected.contains(i),
                activeColor: LumiTokens.green,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selected.add(i);
                    } else {
                      _selected.remove(i);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedCount > 0
                    ? () {
                        final result =
                            _selected.map((i) => widget.items[i]).toList();
                        Navigator.of(context).pop(result);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: LumiTokens.green,
                  foregroundColor: LumiTokens.paper,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                ),
                child: Text(
                  selectedCount > 0
                      ? 'Keep $selectedCount book(s) for next week'
                      : 'Select books to keep',
                  style: LumiType.body.copyWith(
                    color: LumiTokens.paper,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// BOOK PICKER SHEET (Library Browse)
// ============================================

class _BookPickerSheet extends StatefulWidget {
  final String schoolId;
  const _BookPickerSheet({required this.schoolId});

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet> {
  final _searchController = TextEditingController();
  final _libraryService = SchoolLibraryService();
  String _searchQuery = '';

  final List<BookModel> _books = [];
  String? _cursor;
  bool _hasMore = true;
  bool _isLoading = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final page = await _libraryService.fetchBooksPage(
        widget.schoolId,
        startAfterDocId: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _books.addAll(page.books);
        _cursor = page.lastDocId ?? _cursor;
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiTokens.radiusXL),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: LumiTokens.rule,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Choose a Book', style: LumiType.subhead),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search by title or author...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: LumiTokens.cream,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_isLoading && _books.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_loadError != null && _books.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Could not load library.',
                              style: LumiType.caption),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loadNextPage,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  var books = _books;
                  if (_searchQuery.isNotEmpty) {
                    books = books.where((b) {
                      final title = b.title.toLowerCase();
                      final author = (b.author ?? '').toLowerCase();
                      return title.contains(_searchQuery) ||
                          author.contains(_searchQuery);
                    }).toList();
                  }

                  if (books.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No books match "$_searchQuery"'
                                : 'No books in library yet',
                            style: LumiType.caption,
                          ),
                          if (_searchQuery.isNotEmpty && _hasMore) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _loadNextPage,
                              child: const Text('Load more books'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  // Auto-load the next page when the user scrolls near the
                  // bottom of the currently-rendered list. Trips slightly
                  // before the actual edge so the spinner doesn't flash.
                  return NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (_hasMore &&
                          !_isLoading &&
                          n.metrics.extentAfter < 240) {
                        _loadNextPage();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      itemCount: books.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: LumiTokens.rule,
                      ),
                      itemBuilder: (context, index) {
                        if (index >= books.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text('Loading more…',
                                      style: LumiType.caption),
                            ),
                          );
                        }
                        final book = books[index];
                        final hasCover = book.coverImageUrl != null &&
                            book.coverImageUrl!.isNotEmpty &&
                            book.coverImageUrl!.startsWith('http');
                        return InkWell(
                          onTap: () => Navigator.pop(context, book),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    width: 36,
                                    height: 50,
                                    child: hasCover
                                        ? PersistentCachedImage(
                                            imageUrl: book.coverImageUrl!,
                                            fit: BoxFit.cover,
                                            fallback: Container(
                                              color:
                                                  AppColors.teacherPrimaryLight,
                                              child: const Icon(Icons.menu_book,
                                                  size: 16,
                                                  color:
                                                      AppColors.teacherPrimary),
                                            ),
                                          )
                                        : Container(
                                            color:
                                                AppColors.teacherPrimaryLight,
                                            child: const Icon(Icons.menu_book,
                                                size: 16,
                                                color:
                                                    AppColors.teacherPrimary),
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
                                        book.title,
                                        style: LumiType.body.copyWith(
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (book.author != null)
                                        Text(
                                          book.author!,
                                          style: LumiType.caption,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color:
                                      LumiTokens.muted.withValues(alpha: 0.4),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// SWAP ISBN SCANNER SCREEN
// ============================================

class _SwapScannerScreen extends StatefulWidget {
  final String schoolId;
  final String actorId;

  const _SwapScannerScreen({
    required this.schoolId,
    required this.actorId,
  });

  @override
  State<_SwapScannerScreen> createState() => _SwapScannerScreenState();
}

class _SwapScannerScreenState extends State<_SwapScannerScreen> {
  final _bookLookupService = BookLookupService();
  MobileScannerController? _scannerController;
  BookModel? _resolvedBook;
  bool _isLooking = false;
  String? _error;
  final Set<String> _processedCodes = {};

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isLooking || _resolvedBook != null) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final normalized = IsbnAssignmentService.normalizeIsbn(raw);
      if (normalized == null) continue;
      if (_processedCodes.contains(normalized)) continue;
      _processedCodes.add(normalized);

      setState(() {
        _isLooking = true;
        _error = null;
      });

      try {
        final book = await _bookLookupService.lookupByIsbn(
          isbn: normalized,
          schoolId: widget.schoolId,
          actorId: widget.actorId,
          useDeviceScanCache: true,
          persistToDeviceScanCache: true,
        );

        if (!mounted) return;

        if (book != null && book.metadata?['placeholder'] != true) {
          setState(() {
            _resolvedBook = book;
            _isLooking = false;
          });
          _scannerController?.stop();
        } else {
          setState(() {
            _isLooking = false;
            _error = 'Book not found for ISBN $normalized';
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLooking = false;
          _error = 'Lookup failed. Try again.';
        });
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.ink,
      appBar: AppBar(
        backgroundColor: LumiTokens.ink,
        foregroundColor: LumiTokens.paper,
        elevation: 0,
        title: const Text(
          'Scan Replacement Book',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      body: _resolvedBook != null ? _buildConfirmView() : _buildScannerView(),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        if (_scannerController != null)
          MobileScanner(
            controller: _scannerController!,
            onDetect: _onBarcodeDetected,
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            color: LumiTokens.ink.withValues(alpha: 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLooking)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: LumiTokens.paper,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Looking up book...',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          color: LumiTokens.paper,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                else if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      color: AppColors.warmOrange,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  )
                else
                  const Text(
                    'Point camera at an ISBN barcode',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      color: LumiTokens.paper,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmView() {
    final book = _resolvedBook!;
    final hasCover = book.coverImageUrl != null &&
        book.coverImageUrl!.isNotEmpty &&
        book.coverImageUrl!.startsWith('http');

    return Container(
      color: LumiTokens.cream,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
            child: SizedBox(
              width: 120,
              height: 170,
              child: hasCover
                  ? PersistentCachedImage(
                      imageUrl: book.coverImageUrl!,
                      fit: BoxFit.cover,
                      fallback: Container(
                        color: LumiTokens.tintGreen,
                        child: const Icon(Icons.menu_book,
                            size: 40, color: LumiTokens.green),
                      ),
                    )
                  : Container(
                      color: LumiTokens.tintGreen,
                      child: const Icon(Icons.menu_book,
                          size: 40, color: LumiTokens.green),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            book.title,
            style: LumiType.heading,
            textAlign: TextAlign.center,
          ),
          if (book.author != null) ...[
            const SizedBox(height: 4),
            Text(
              book.author!,
              style: LumiType.caption,
              textAlign: TextAlign.center,
            ),
          ],
          if (book.isbn != null) ...[
            const SizedBox(height: 8),
            Text('ISBN ${book.isbn}', style: LumiType.caption),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, book),
              style: ElevatedButton.styleFrom(
                backgroundColor: LumiTokens.green,
                foregroundColor: LumiTokens.paper,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                ),
              ),
              child: const Text(
                'Use This Book',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _resolvedBook = null;
                _error = null;
              });
              _scannerController?.start();
            },
            child: Text(
              'Scan a different book',
              style: LumiType.body.copyWith(
                color: LumiTokens.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
