import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/reading_level_history_sheet.dart';
import '../../core/widgets/lumi/reading_level_picker_sheet.dart';
import '../../core/widgets/lumi/teacher_book_assignment_card.dart';
import '../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../core/widgets/lumi/teacher_student_list_item.dart';
import '../../data/models/user_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/student_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/allocation_model.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/widgets/lumi/persistent_cached_image.dart';
import '../../data/models/book_model.dart';
import '../../services/book_cover_cache_service.dart';
import '../../services/book_lookup_service.dart';
import '../../services/school_library_service.dart';
import '../../services/book_metadata_resolver.dart';
import '../../data/models/reading_group_model.dart';
import '../../services/allocation_crud_service.dart';
import '../../services/firebase_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/reading_level_service.dart';
import '../../services/student_reading_level_service.dart';

/// Student Detail Screen
///
/// Shows student profile, stats, assigned books, and latest parent comment.
/// Per spec: avatar header, 2-col stats, assigned books list, parent comment.
class StudentDetailScreen extends StatefulWidget {
  final UserModel teacher;
  final StudentModel student;
  final ClassModel? classModel;

  const StudentDetailScreen({
    super.key,
    required this.teacher,
    required this.student,
    this.classModel,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  final AllocationCrudService _allocationCrudService = AllocationCrudService();
  final BookLookupService _bookLookupService = BookLookupService();
  final ReadingLevelService _readingLevelService = ReadingLevelService();
  final StudentReadingLevelService _studentReadingLevelService =
      StudentReadingLevelService();
  final Map<String, Future<String>> _parentNameFutures = {};
  BookMetadataResolver? _metadataResolverInstance;
  // Screen-local ISBN API results (separate from Firestore-doc-based data
  // which is owned by BookCoverCacheService).
  final Map<String, _CachedBookCover> _bookCoverByIsbn = {};
  final Set<String> _isbnCoverLoadsInFlight = <String>{};
  final Set<String> _isbnCoverLoadsCompleted = <String>{};
  List<ReadingLevelOption> _readingLevelOptions = const [];
  bool _levelsEnabled = false;
  StudentModel? _studentOverride;
  bool _readingLevelExpanded = false;
  Future<List<ReadingGroupModel>>? _studentGroupsFuture;

  StudentModel get _currentStudent => _studentOverride ?? widget.student;

  BookMetadataResolver get _metadataResolver {
    final existing = _metadataResolverInstance;
    if (existing != null) return existing;

    final resolver = BookMetadataResolver(
      lookupService: BookLookupService(),
      schoolId: widget.student.schoolId,
      actorId: widget.teacher.id,
    );
    resolver.addListener(_onMetadataUpdated);
    _metadataResolverInstance = resolver;
    return resolver;
  }

  @override
  void initState() {
    super.initState();
    BookCoverCacheService.instance.addListener(_onCoversUpdated);
    _ensureMetadataResolver();
    _loadReadingLevelOptions();
    _studentGroupsFuture = _loadStudentGroups();
  }

  Future<List<ReadingGroupModel>> _loadStudentGroups() async {
    try {
      final snapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.student.schoolId)
          .collection('readingGroups')
          .where('studentIds', arrayContains: widget.student.id)
          .where('isActive', isEqualTo: true)
          .get();
      return snapshot.docs
          .map((doc) => ReadingGroupModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error loading student groups: $e');
      return [];
    }
  }

  @override
  void didUpdateWidget(covariant StudentDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final metadataScopeChanged =
        oldWidget.student.schoolId != widget.student.schoolId ||
            oldWidget.teacher.id != widget.teacher.id;
    final studentChanged = oldWidget.student.id != widget.student.id;

    if (studentChanged) {
      _studentOverride = null;
    }

    if (oldWidget.student.schoolId != widget.student.schoolId) {
      _loadReadingLevelOptions(forceRefresh: true);
    }

    if (!metadataScopeChanged) return;

    _disposeMetadataResolver();
    _bookCoverByIsbn.clear();
    _isbnCoverLoadsInFlight.clear();
    _isbnCoverLoadsCompleted.clear();
    _ensureMetadataResolver();
  }

  void _onCoversUpdated() {
    if (mounted) setState(() {});
  }

  void _onMetadataUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BookCoverCacheService.instance.removeListener(_onCoversUpdated);
    _disposeMetadataResolver();
    super.dispose();
  }

  void _disposeMetadataResolver() {
    final resolver = _metadataResolverInstance;
    if (resolver == null) return;
    resolver.removeListener(_onMetadataUpdated);
    resolver.dispose();
    _metadataResolverInstance = null;
  }

  void _ensureMetadataResolver() {
    _metadataResolver;
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
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.student.schoolId)
            .collection('classes')
            .doc(widget.student.classId)
            .get();
        if (!classDoc.exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Class not found for this student'),
              backgroundColor: AppColors.error,
            ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open assignment flow'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openIsbnScannerFlow() async {
    try {
      var classModel = widget.classModel;
      if (classModel == null) {
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.student.schoolId)
            .collection('classes')
            .doc(widget.student.classId)
            .get();
        if (!classDoc.exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Class not found for this student'),
              backgroundColor: AppColors.error,
            ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scannedCount > 0
                ? 'Scanned $scannedCount book(s). $totalAssigned assigned this week.'
                : 'No ISBN scans captured.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open ISBN scanner'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  bool _canMutateAssignment(_AssignedBookViewData book) {
    return book.allocationId != null &&
        book.allocationId!.isNotEmpty &&
        book.assignmentItemId != null &&
        book.assignmentItemId!.isNotEmpty;
  }

  void _showBookActionsSheet(_AssignedBookViewData book) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TeacherDimensions.radiusXL),
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
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text(book.title, style: TeacherTypography.h3),
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
    final color = isDestructive ? AppColors.error : AppColors.charcoal;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TeacherTypography.bodyMedium.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  Future<void> _handleBookAction(
    _AssignedBookViewData book,
    TeacherBookCardAction action,
  ) async {
    if (!_canMutateAssignment(book)) return;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update assignment: $e'),
          backgroundColor: AppColors.error,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "$title" for the whole class.')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Removed "$title" for ${widget.student.firstName}.')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swapped "$currentTitle" for whole class.')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Swapped "$currentTitle" for ${widget.student.firstName}.')),
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
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TeacherDimensions.radiusXL),
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
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text('Swap Book', style: TeacherTypography.h3),
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
      color: AppColors.teacherBackground,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.teacherPrimaryLight,
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusS),
                ),
                child: Icon(icon, size: 18, color: AppColors.teacherPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TeacherTypography.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(subtitle, style: TeacherTypography.caption),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSecondary.withValues(alpha: 0.4),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated "$currentTitle" for whole class.')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Updated "$currentTitle" for ${widget.student.firstName}.')),
    );
  }

  Future<void> _keepBookNextCycle({
    required String allocationId,
    required String itemId,
    required String title,
  }) async {
    // Look up the allocation doc to find the full AllocationBookItem
    final doc = await _firebaseService.firestore
        .collection('schools')
        .doc(widget.student.schoolId)
        .collection('allocations')
        .doc(allocationId)
        .get();
    if (!doc.exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Allocation not found.')),
      );
      return;
    }

    final allocation = AllocationModel.fromFirestore(doc);
    final items =
        allocation.effectiveAssignmentItemsForStudent(widget.student.id);
    final item = items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book item not found in allocation.')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$title" is already assigned next week.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$title" kept for next week.')),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(TeacherDimensions.radiusL)),
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

  Widget _buildActionHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.teacherPrimaryLight,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusS),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.teacherPrimary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TeacherTypography.caption.copyWith(
                color: AppColors.teacherPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedBooksHeader() {
    return Row(
      children: [
        Expanded(
          child: Text('Assigned Books', style: TeacherTypography.h3),
        ),
        _buildActionHeaderButton(
          icon: Icons.refresh_rounded,
          label: 'Renew',
          onPressed: _showRenewSheet,
        ),
        const SizedBox(width: 8),
        _buildActionHeaderButton(
          icon: Icons.qr_code_scanner,
          label: 'Scan',
          onPressed: _openIsbnScannerFlow,
        ),
        const SizedBox(width: 8),
        _buildActionHeaderButton(
          icon: Icons.add,
          label: 'Assign',
          onPressed: _openAssignFlow,
        ),
      ],
    );
  }

  Future<void> _showRenewSheet() async {
    // Fetch current allocations for this student's class
    final snapshot = await _firebaseService.firestore
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No books to renew.')),
      );
      return;
    }

    if (!mounted) return;
    final selected = await showModalBottomSheet<List<_RenewableBookItem>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(TeacherDimensions.radiusL)),
      ),
      builder: (context) => _RenewBooksSheet(items: currentItems),
    );

    if (selected == null || selected.isEmpty) return;

    final assignmentService = IsbnAssignmentService();
    var keptCount = 0;
    var alreadyCount = 0;

    for (final entry in selected) {
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
    }

    if (!mounted) return;
    final message = alreadyCount > 0
        ? '$keptCount book(s) kept for next week ($alreadyCount already assigned).'
        : '$keptCount book(s) kept for next week.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$actionLabel scope',
                style: TeacherTypography.h3,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose where this change should apply.',
                style: TeacherTypography.bodySmall,
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

  Future<String> _getParentName(String? parentId) {
    if (parentId == null || parentId.isEmpty) {
      return Future.value('Parent');
    }
    return _parentNameFutures.putIfAbsent(parentId, () async {
      final schoolRef = _firebaseService.firestore
          .collection('schools')
          .doc(widget.student.schoolId);

      final parentDoc =
          await schoolRef.collection('parents').doc(parentId).get();
      if (parentDoc.exists) {
        final data = parentDoc.data() ?? {};
        final name = data['fullName'] as String?;
        if (name != null && name.trim().isNotEmpty) return name;
      }

      final userDoc = await schoolRef.collection('users').doc(parentId).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        final name = data['fullName'] as String?;
        if (name != null && name.trim().isNotEmpty) return name;
      }

      return 'Parent';
    });
  }

  List<_ReadingLogSnapshot> _toReadingLogs(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final dateTimestamp = data['date'] as Timestamp?;
      final commentSelections = data['parentCommentSelections'];
      return _ReadingLogSnapshot(
        id: doc.id,
        date: dateTimestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        allocationId: data['allocationId'] as String?,
        bookTitles: List<String>.from(data['bookTitles'] ?? const []),
        status: (data['status'] as String?) ?? '',
        minutesRead: (data['minutesRead'] as num?)?.toInt() ?? 0,
        targetMinutes: (data['targetMinutes'] as num?)?.toInt() ?? 0,
        parentId: data['parentId'] as String?,
        parentComment: (data['parentComment'] as String?)?.trim(),
        parentCommentSelections: commentSelections is List
            ? commentSelections.whereType<String>().toList()
            : const [],
        parentCommentFreeText:
            (data['parentCommentFreeText'] as String?)?.trim(),
        childFeeling: data['childFeeling'] as String?,
      );
    }).toList();
  }

  List<_AssignedBookViewData> _mapAssignedBooks(
    List<AllocationModel> allocations,
    List<_ReadingLogSnapshot> logs,
  ) {
    final now = DateTime.now();
    final seen = <String>{};
    final results = <_AssignedBookViewData>[];

    for (final allocation in allocations) {
      final withinWindow = !allocation.startDate.isAfter(now) &&
          !allocation.endDate.isBefore(now);
      final appliesToStudent = allocation.isForWholeClass ||
          allocation.studentIds.contains(widget.student.id);
      if (!withinWindow || !appliesToStudent) continue;

      if (allocation.type == AllocationType.byTitle) {
        final type = _inferBookType(allocation);
        final effectiveItems =
            allocation.effectiveAssignmentItemsForStudent(widget.student.id);
        if (effectiveItems.isNotEmpty) {
          for (final item in effectiveItems) {
            final itemIsbn = _isbnKey(item.resolvedIsbn ?? '');
            if (itemIsbn.isNotEmpty) {
              final dedupeKey = 'isbn:$itemIsbn';
              if (seen.contains(dedupeKey)) continue;
              seen.add(dedupeKey);

              final cachedBook = _bookCoverByIsbn[itemIsbn];
              final cachedTitle =
                  BookCoverCacheService.instance.resolveTitleByIsbn(itemIsbn);
              final cachedCover = BookCoverCacheService.instance
                  .resolveCoverUrlByIsbn(itemIsbn);
              final rawTitle = cachedBook?.title.isNotEmpty == true
                  ? cachedBook!.title
                  : (item.title.trim().isNotEmpty
                      ? item.title.trim()
                      : (cachedTitle ?? 'Unknown Book (ISBN $itemIsbn)'));
              final status = _deriveStatusForTitle(allocation, logs, rawTitle);
              final displayTitle =
                  IsbnAssignmentService.sanitizeDisplayTitle(rawTitle);

              results.add(
                _AssignedBookViewData(
                  title: displayTitle,
                  subtitle:
                      '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
                  bookType: type,
                  status: status,
                  coverGradient: _coverGradient(type, itemIsbn),
                  coverImageUrl: cachedBook?.coverImageUrl ?? cachedCover,
                  shouldResolveCover: false,
                  allocationId: allocation.id,
                  assignmentItemId: item.id,
                ),
              );
              continue;
            }

            final title = item.title.trim();
            if (title.isEmpty) continue;
            final dedupeKey = 'item:${item.id}';
            if (seen.contains(dedupeKey)) continue;
            seen.add(dedupeKey);
            final status = _deriveStatusForTitle(allocation, logs, title);
            final displayTitle =
                IsbnAssignmentService.sanitizeDisplayTitle(title);
            results.add(
              _AssignedBookViewData(
                title: displayTitle,
                subtitle:
                    '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
                bookType: type,
                status: status,
                coverGradient: _coverGradient(type, item.id),
                coverImageUrl: _resolveCoverUrlForTitle(title),
                shouldResolveCover: true,
                allocationId: allocation.id,
                assignmentItemId: item.id,
              ),
            );
          }
          continue;
        }

        // effectiveItems is empty for this student (all items removed via
        // student-level override). Don't fall through to the generic
        // allocation path below — this allocation simply has no books for
        // this student.
        continue;
      }

      final dedupeKey = 'allocation:${allocation.id}';
      if (seen.contains(dedupeKey)) continue;
      seen.add(dedupeKey);
      final status = _deriveStatusForAllocation(allocation, logs);
      final type = _inferBookType(allocation);
      results.add(
        _AssignedBookViewData(
          title: _allocationTitle(allocation),
          subtitle:
              '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
          bookType: type,
          status: status,
          coverGradient: _coverGradient(type, allocation.id),
          shouldResolveCover: false,
        ),
      );
    }

    return results;
  }

  List<String> _scannedIsbnsForAllocation(AllocationModel allocation) {
    final itemIsbns = allocation
        .effectiveAssignmentItemsForStudent(widget.student.id)
        .map((item) => _isbnKey(item.resolvedIsbn ?? ''))
        .where((isbn) => isbn.isNotEmpty)
        .toSet()
        .toList();
    if (itemIsbns.isNotEmpty) {
      return itemIsbns;
    }

    final rawMetadataIsbns = allocation.metadata?['scannedIsbns'];
    final metadataIsbns = rawMetadataIsbns is! List
        ? const <String>[]
        : rawMetadataIsbns
            .whereType<String>()
            .map(_isbnKey)
            .where((isbn) => isbn.isNotEmpty)
            .toSet()
            .toList();

    if (metadataIsbns.isNotEmpty) {
      return metadataIsbns;
    }

    final parsed = <String>{};

    final bookIds = allocation.bookIds;
    if (bookIds != null && bookIds.isNotEmpty) {
      for (final rawId in bookIds) {
        final id = rawId.trim();
        if (!id.startsWith('isbn_')) continue;
        final isbn = _isbnKey(id.substring(5));
        if (isbn.isNotEmpty) parsed.add(isbn);
      }
    }

    if (parsed.isNotEmpty) {
      return parsed.toList();
    }

    // Legacy fallback: older allocations can store ISBNs in the visible title.
    final bookTitles = allocation.bookTitles;
    if (bookTitles == null || bookTitles.isEmpty) {
      return const [];
    }

    final isbnPattern = RegExp(r'ISBN\s*([0-9Xx\- ]{10,20})');
    for (final rawTitle in bookTitles) {
      final match = isbnPattern.firstMatch(rawTitle);
      if (match == null) continue;
      final isbn = _isbnKey(match.group(1) ?? '');
      if (isbn.isNotEmpty) parsed.add(isbn);
    }
    return parsed.toList();
  }

  String _isbnKey(String rawIsbn) {
    final trimmed = rawIsbn.trim();
    if (trimmed.isEmpty) return '';
    return IsbnAssignmentService.normalizeIsbn(trimmed) ?? trimmed;
  }

  void _primeIsbnCovers(List<AllocationModel> allocations) {
    final missingIsbns = <String>{};

    for (final allocation in allocations) {
      for (final isbn in _scannedIsbnsForAllocation(allocation)) {
        if (BookCoverCacheService.instance.resolveCoverUrlByIsbn(isbn) !=
            null) {
          _isbnCoverLoadsCompleted.add(isbn);
          continue;
        }
        if (_bookCoverByIsbn.containsKey(isbn) ||
            _isbnCoverLoadsInFlight.contains(isbn) ||
            _isbnCoverLoadsCompleted.contains(isbn)) {
          continue;
        }
        missingIsbns.add(isbn);
      }
    }

    if (missingIsbns.isEmpty) return;

    for (final isbn in missingIsbns) {
      _isbnCoverLoadsInFlight.add(isbn);
      unawaited(_loadCoverFromIsbn(isbn));
    }
  }

  Future<void> _loadCoverFromIsbn(String isbn) async {
    try {
      final resolved = await _bookLookupService.lookupByIsbn(
        isbn: isbn,
        schoolId: widget.student.schoolId,
        actorId: widget.teacher.id,
        useFirestoreCache: false,
        persistToFirestoreCache: false,
      );
      if (resolved == null) return;

      final resolvedIsbn = _isbnKey(resolved.isbn ?? isbn);
      final title = resolved.title.trim();
      final rawCoverImageUrl = resolved.coverImageUrl?.trim();
      final hasHttpCover = rawCoverImageUrl != null &&
          rawCoverImageUrl.isNotEmpty &&
          rawCoverImageUrl.startsWith('http');
      final coverImageUrl = hasHttpCover
          ? rawCoverImageUrl.replaceFirst('http://', 'https://')
          : (resolvedIsbn.isNotEmpty
              ? 'https://covers.openlibrary.org/b/isbn/$resolvedIsbn-M.jpg?default=false'
              : null);

      final cached = _CachedBookCover(
        bookId: resolved.id,
        title: title,
        isbn: resolvedIsbn,
        coverImageUrl: coverImageUrl,
      );
      _bookCoverByIsbn[resolvedIsbn] = cached;

      // Also populate the session-level singleton so other screens benefit.
      BookCoverCacheService.instance.cacheFromIsbnLookup(
        isbn: resolvedIsbn,
        title: title,
        coverImageUrl: coverImageUrl,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Best-effort ISBN hydration; keep placeholder when lookup fails.
    } finally {
      _isbnCoverLoadsInFlight.remove(isbn);
      _isbnCoverLoadsCompleted.add(isbn);
    }
  }

  void _resolveMissingBookMetadata(List<_AssignedBookViewData> books) {
    // Title-based API lookups disabled — they fuzzy-match covers from
    // unrelated books.  Books without ISBN-resolved covers show a placeholder.
  }

  String? _resolveCoverUrlForTitle(String title) {
    // 1. Session-level singleton — Firestore doc loads shared across screens,
    //    plus any ISBN API results fed in via cacheFromIsbnLookup.
    final singletonUrl = BookCoverCacheService.instance.resolveCoverUrl(title);
    if (singletonUrl != null) return singletonUrl;

    // 2. Screen-local ISBN API results (keyed directly by isbn in _bookCoverByIsbn).
    final titleKey = BookLookupService.normalizeTitle(title);
    final localIsbnEntry = _bookCoverByIsbn.values
        .where((c) => BookLookupService.normalizeTitle(c.title) == titleKey)
        .firstOrNull;
    final localIsbnUrl = localIsbnEntry?.coverImageUrl;
    if (localIsbnUrl != null && localIsbnUrl.startsWith('http')) {
      return localIsbnUrl;
    }

    return null;
  }

  String _deriveStatusForTitle(
    AllocationModel allocation,
    List<_ReadingLogSnapshot> logs,
    String title,
  ) {
    final titleKey = title.trim().toLowerCase();
    final matching = logs.where((log) {
      final inWindow = !log.date.isBefore(allocation.startDate) &&
          !log.date.isAfter(allocation.endDate.add(const Duration(days: 1)));
      if (!inWindow) return false;
      if (log.allocationId == allocation.id) return true;
      return log.bookTitles
          .any((book) => book.trim().toLowerCase() == titleKey);
    }).toList();

    if (matching.isEmpty) return 'new';
    final hasCompletion = matching.any((log) =>
        log.status == 'completed' || log.minutesRead >= log.targetMinutes);
    return hasCompletion ? 'completed' : 'in_progress';
  }

  String _deriveStatusForAllocation(
    AllocationModel allocation,
    List<_ReadingLogSnapshot> logs,
  ) {
    final matching = logs.where((log) {
      if (log.allocationId != allocation.id) return false;
      return !log.date.isBefore(allocation.startDate) &&
          !log.date.isAfter(allocation.endDate.add(const Duration(days: 1)));
    }).toList();
    if (matching.isEmpty) return 'new';
    final hasCompletion = matching.any((log) =>
        log.status == 'completed' || log.minutesRead >= log.targetMinutes);
    return hasCompletion ? 'completed' : 'in_progress';
  }

  String _allocationTitle(AllocationModel allocation) {
    if (allocation.type == AllocationType.byLevel) {
      if (allocation.levelStart != null && allocation.levelEnd != null) {
        return 'Level ${allocation.levelStart}-${allocation.levelEnd} Reading';
      }
      if (allocation.levelStart != null) {
        return 'Level ${allocation.levelStart} Reading';
      }
    }
    if (allocation.type == AllocationType.freeChoice) {
      return 'Free Choice Reading';
    }
    return 'Reading Allocation';
  }

  String _cadenceLabel(AllocationCadence cadence) {
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

  String _inferBookType(AllocationModel allocation) {
    if (allocation.type == AllocationType.byLevel ||
        allocation.levelStart != null) {
      return 'decodable';
    }
    return 'library';
  }

  List<Color> _coverGradient(String type, String seed) {
    if (type == 'decodable') {
      const palettes = <List<Color>>[
        [AppColors.levelCVC, AppColors.error],
        [AppColors.levelDigraphs, AppColors.warmOrange],
        [AppColors.levelBlends, AppColors.secondaryYellow],
        [AppColors.levelCVCE, AppColors.secondaryGreen],
        [AppColors.levelVowelTeams, AppColors.decodableBlue],
        [AppColors.levelRControlled, AppColors.secondaryPurple],
      ];
      final index = seed.hashCode.abs() % palettes.length;
      return palettes[index];
    }
    return const [AppColors.libraryGreen, Color(0xFF388E3C)];
  }

  _LatestParentCommentViewData? _latestParentComment(
    List<_ReadingLogSnapshot> logs,
  ) {
    for (final log in logs) {
      final hasChips = log.parentCommentSelections.isNotEmpty;
      final freeText = _extractFreeText(log);
      final hasFreeText = freeText.isNotEmpty;
      if (!hasChips && !hasFreeText) continue;

      return _LatestParentCommentViewData(
        parentId: log.parentId,
        commentText: freeText,
        date: log.date,
        selections: log.parentCommentSelections,
        feeling: log.childFeeling,
      );
    }
    return null;
  }

  /// Returns only the parent's typed free-text comment, excluding chip
  /// selections. Falls back to the legacy `parentComment` field if no
  /// structured data exists.
  String _extractFreeText(_ReadingLogSnapshot log) {
    final freeText = log.parentCommentFreeText?.trim() ?? '';
    if (freeText.isNotEmpty) return freeText;
    // Legacy logs stored everything in parentComment. Only use it if there
    // are no structured selections (otherwise it's a duplicate).
    if (log.parentCommentSelections.isEmpty) {
      return log.parentComment?.trim() ?? '';
    }
    return '';
  }


  String _formatCommentDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'Today';
    if (dateOnly == yesterday) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _readingLevelDisplayLabel(StudentModel student) {
    if (_readingLevelOptions.isEmpty) {
      final raw = student.currentReadingLevel?.trim();
      return raw == null || raw.isEmpty ? 'Needs level' : raw;
    }

    return _readingLevelService.formatLevelLabel(
      student.currentReadingLevel,
      options: _readingLevelOptions,
    );
  }

  String _readingLevelCompactLabel(StudentModel student) {
    if (_readingLevelOptions.isEmpty) {
      final raw = student.currentReadingLevel?.trim();
      return raw == null || raw.isEmpty ? 'Needs level' : raw;
    }

    return _readingLevelService.formatCompactLabel(
      student.currentReadingLevel,
      options: _readingLevelOptions,
    );
  }

  bool _isReadingLevelUnset(StudentModel student) {
    final raw = student.currentReadingLevel?.trim();
    return raw == null || raw.isEmpty;
  }

  bool _isReadingLevelUnresolved(StudentModel student) {
    if (_readingLevelOptions.isEmpty) return false;
    return _readingLevelService.hasUnresolvedLevel(
      student.currentReadingLevel,
      options: _readingLevelOptions,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open reading level picker: $error'),
          backgroundColor: AppColors.error,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update reading level: $error'),
          backgroundColor: AppColors.error,
        ),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          didUpdate ? 'Reading level updated' : 'No reading level change saved',
        ),
        backgroundColor:
            didUpdate ? AppColors.success : AppColors.textSecondary,
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load reading level history: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.teacherBackground,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        surfaceTintColor: AppColors.white,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: TeacherStudentListItem.colorForName(
                  _currentStudent.fullName),
              child: Text(
                _currentStudent.firstName[0].toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(_currentStudent.fullName, style: TeacherTypography.h3),
          ],
        ),
        actions: [
          if (_levelsEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TeacherReadingLevelPill(
                label: _readingLevelCompactLabel(_currentStudent),
                isUnset: _isReadingLevelUnset(_currentStudent),
                isUnresolved: _isReadingLevelUnresolved(_currentStudent),
                onTap: _showReadingLevelPicker,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Last read indicator
            _buildLastReadIndicator(),
            const SizedBox(height: 12),

            // Group badges
            _buildGroupBadges(),

            // Stats
            _buildStatsRow(),
            const SizedBox(height: 20),

            if (_levelsEnabled) ...[
              _buildReadingLevelCard(),
              const SizedBox(height: 20),
            ],

            // Assigned Books section
            _buildAssignedBooksSection(),
            const SizedBox(height: 20),

            // Reading History
            _buildReadingHistorySection(),
            const SizedBox(height: 20),

            // Latest Parent Comment
            _buildParentCommentSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupBadges() {
    return FutureBuilder<List<ReadingGroupModel>>(
      future: _studentGroupsFuture,
      builder: (context, snapshot) {
        final groups = snapshot.data;
        if (groups == null || groups.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: groups.map((group) {
              final groupColor = group.color != null
                  ? Color(
                      int.parse(group.color!.replaceFirst('#', '0xFF')))
                  : AppColors.teacherPrimary;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusRound),
                  border: Border.all(
                    color: groupColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: groupColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      group.name,
                      style: TeacherTypography.caption.copyWith(
                        color: groupColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildLastReadIndicator() {
    final lastRead = _currentStudent.stats?.lastReadingDate;
    final String label;
    final Color color;

    if (lastRead == null) {
      label = 'No reading logged yet';
      color = AppColors.textSecondary;
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
        color = AppColors.teacherPrimary;
      } else if (diff < 7) {
        label = 'Last read $diff days ago';
        color = AppColors.warmOrange;
      } else {
        label = 'Last read ${(diff / 7).floor()} week${diff >= 14 ? 's' : ''} ago';
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
          style: TeacherTypography.bodySmall.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _buildReadingHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Reading', style: TeacherTypography.h3),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: _firebaseService.firestore
              .collection('schools')
              .doc(widget.student.schoolId)
              .collection('readingLogs')
              .where('studentId', isEqualTo: widget.student.id)
              .orderBy('date', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final logs = _toReadingLogs(snapshot.data!);
            if (logs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusL),
                  border: Border.all(color: AppColors.teacherBorder),
                ),
                child: Center(
                  child: Text(
                    'No reading history yet',
                    style: TeacherTypography.bodySmall,
                  ),
                ),
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius:
                    BorderRadius.circular(TeacherDimensions.radiusL),
                border: Border.all(color: AppColors.teacherBorder),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < logs.length; i++) ...[
                    _buildReadingLogRow(logs[i]),
                    if (i < logs.length - 1)
                      Divider(
                        height: 1,
                        color: AppColors.teacherBorder,
                        indent: 14,
                        endIndent: 14,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildReadingLogRow(_ReadingLogSnapshot log) {
    final dateStr = _formatCommentDate(log.date);
    final books = log.bookTitles.isNotEmpty
        ? log.bookTitles.join(', ')
        : 'Free reading';
    final minutes = log.minutesRead;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Date
          SizedBox(
            width: 70,
            child: Text(
              dateStr,
              style: TeacherTypography.caption,
            ),
          ),
          const SizedBox(width: 8),
          // Book title
          Expanded(
            child: Text(
              books,
              style: TeacherTypography.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Minutes
          Text(
            '${minutes}m',
            style: TeacherTypography.caption.copyWith(
              color: AppColors.teacherPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          // Feeling blob
          if (log.childFeeling != null) ...[
            const SizedBox(width: 6),
            Image.asset(
              'assets/blobs/blob-${log.childFeeling}.png',
              width: 18,
              height: 18,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadingLevelCard() {
    final hasResolvedLevel = !_isReadingLevelUnset(_currentStudent) &&
        !_isReadingLevelUnresolved(_currentStudent);
    final canMoveDown = hasResolvedLevel &&
        _readingLevelService.previousLevel(
              _currentStudent.currentReadingLevel,
              options: _readingLevelOptions,
            ) !=
            null;
    final canMoveUp = hasResolvedLevel &&
        _readingLevelService.nextLevel(
              _currentStudent.currentReadingLevel,
              options: _readingLevelOptions,
            ) !=
            null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tappable header ──────────────────────────────────────────
            InkWell(
              onTap: () => setState(
                () => _readingLevelExpanded = !_readingLevelExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Text('Reading Level', style: TeacherTypography.h3),
                    const SizedBox(width: 8),
                    TeacherReadingLevelPill(
                      label: _readingLevelCompactLabel(_currentStudent),
                      isUnset: _isReadingLevelUnset(_currentStudent),
                      isUnresolved: _isReadingLevelUnresolved(_currentStudent),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _readingLevelExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded content ─────────────────────────────────────────
            if (_readingLevelExpanded) ...[
              Divider(height: 1, color: AppColors.teacherBorder),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Level label + date
                    Row(
                      children: [
                        Text(
                          _readingLevelDisplayLabel(_currentStudent),
                          style: TeacherTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (_currentStudent.readingLevelUpdatedAt != null) ...[
                          Text(
                            '  ·  Updated ${_formatCommentDate(_currentStudent.readingLevelUpdatedAt!)}',
                            style: TeacherTypography.bodySmall,
                          ),
                        ],
                      ],
                    ),

                    // Unresolved level warning
                    if (_isReadingLevelUnresolved(_currentStudent)) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          'Legacy level — pick a new level to fix.',
                          style: TeacherTypography.bodySmall.copyWith(
                            color: AppColors.charcoal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // ── Action row ───────────────────────────────────────
                    Row(
                      children: [
                        _buildCompactLevelButton(
                          icon: Icons.keyboard_arrow_down_rounded,
                          label: 'Down',
                          onPressed: canMoveDown
                              ? () => _moveReadingLevel(increase: false)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        _buildCompactLevelButton(
                          icon: Icons.keyboard_arrow_up_rounded,
                          label: 'Up',
                          onPressed: canMoveUp
                              ? () => _moveReadingLevel(increase: true)
                              : null,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _showReadingLevelHistory,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -2,
                            ),
                            textStyle: TeacherTypography.bodySmall,
                          ),
                          child: const Text('History'),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          onPressed: _showReadingLevelPicker,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.teacherPrimary,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            elevation: 0,
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -2,
                            ),
                            textStyle: TeacherTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                            ),
                          ),
                          child: const Text('Change Level'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLevelButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed != null
            ? AppColors.teacherPrimary
            : AppColors.textSecondary,
        side: BorderSide(
          color: onPressed != null
              ? AppColors.teacherPrimary.withValues(alpha: 0.35)
              : AppColors.divider,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        textStyle: TeacherTypography.bodySmall.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        ),
      ),
    );
  }

  /// Returns the current streak only if the student read today or yesterday.
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

  Widget _buildStatsRow() {
    final streak = _activeStreak(_currentStudent.stats);
    final totalNights = _currentStudent.stats?.totalReadingDays ?? 0;
    final totalBooks = _currentStudent.stats?.totalBooksRead ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reading Stats', style: TeacherTypography.h3),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            border: Border.all(color: AppColors.teacherBorder),
          ),
          child: Row(
            children: [
              _buildCompactStat(
                '$streak', 'Day streak',
                icon: Icons.local_fire_department_outlined,
                iconSize: 20,
                iconColor: AppColors.warmOrange,
                circleColor: AppColors.warmOrange.withValues(alpha: 0.12),
              ),
              _compactDivider(),
              _buildCompactStat(
                '$totalNights', 'Total nights',
                icon: Icons.nights_stay_outlined,
              ),
              _compactDivider(),
              _buildCompactStat(
                '$totalBooks', 'Total books',
                icon: Icons.menu_book_outlined,
                iconSize: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStat(
    String value,
    String label, {
    required IconData icon,
    double iconSize = 18,
    Color iconColor = AppColors.teacherPrimary,
    Color? circleColor,
  }) {
    final bg = circleColor ?? AppColors.teacherPrimaryLight;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TeacherTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _compactDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.divider,
    );
  }

  Widget _buildAssignedBooksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAssignedBooksHeader(),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: _firebaseService.firestore
              .collection('schools')
              .doc(widget.student.schoolId)
              .collection('allocations')
              .where('classId', isEqualTo: widget.student.classId)
              .where('isActive', isEqualTo: true)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, allocationSnapshot) {
            if (allocationSnapshot.hasError) {
              return _buildSectionInfoCard(
                'Could not load assigned books',
                isError: true,
              );
            }
            if (!allocationSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final allocations = allocationSnapshot.data!.docs
                .map((doc) => AllocationModel.fromFirestore(doc))
                .toList();
            BookCoverCacheService.instance.primeFromAllocations(
              allocations,
              _firebaseService.firestore,
            );
            _primeIsbnCovers(allocations);

            return StreamBuilder<QuerySnapshot>(
              stream: _firebaseService.firestore
                  .collection('schools')
                  .doc(widget.student.schoolId)
                  .collection('readingLogs')
                  .where('studentId', isEqualTo: widget.student.id)
                  .orderBy('date', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, logSnapshot) {
                if (logSnapshot.hasError) {
                  return _buildSectionInfoCard(
                    'Could not load reading progress',
                    isError: true,
                  );
                }
                if (!logSnapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final logs = _toReadingLogs(logSnapshot.data!);
                final books = _mapAssignedBooks(allocations, logs);
                _resolveMissingBookMetadata(books);

                if (books.isEmpty) {
                  return _buildSectionInfoCard(
                    'No active assigned books for this student yet.',
                  );
                }

                return Column(
                  children: books.map((book) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TeacherBookAssignmentCard(
                        title: book.title,
                        subtitle: book.subtitle,
                        coverGradient: book.coverGradient,
                        coverImageUrl: book.coverImageUrl,
                        bookType: book.bookType,
                        status: book.status,
                        onActionSelected: _canMutateAssignment(book)
                            ? (action) => _handleBookAction(book, action)
                            : null,
                        onTap: _canMutateAssignment(book)
                            ? () => _showBookActionsSheet(book)
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildParentCommentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Latest Parent Comment', style: TeacherTypography.h3),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: _firebaseService.firestore
              .collection('schools')
              .doc(widget.student.schoolId)
              .collection('readingLogs')
              .where('studentId', isEqualTo: widget.student.id)
              .orderBy('date', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildSectionInfoCard(
                'Could not load parent comments',
                isError: true,
              );
            }

            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final logs = _toReadingLogs(snapshot.data!);
            final latest = _latestParentComment(logs);
            if (latest == null) {
              return ClipRRect(
                borderRadius:
                    BorderRadius.circular(TeacherDimensions.radiusL),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusL),
                    border: Border.all(color: AppColors.teacherBorder),
                  ),
                  child: Row(
                    children: [
                      Container(width: 4, height: 48, color: AppColors.divider),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'No parent comments yet',
                        style: TeacherTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            }

            return FutureBuilder<String>(
              future: _getParentName(latest.parentId),
              builder: (context, parentSnapshot) {
                final parentName = parentSnapshot.data ?? 'Parent';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusL),
                    border: Border.all(color: AppColors.teacherBorder),
                    // Left accent via a gradient trick won't work with
                    // Border.all, so we overlay it below.
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left accent bar — stretches full card height
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: AppColors.teacherPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Icon
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.teacherPrimaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 14,
                          color: AppColors.teacherPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Chips + blob feeling
                            if (latest.selections.isNotEmpty ||
                                latest.feeling != null)
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment:
                                    WrapCrossAlignment.center,
                                children: [
                                  ...latest.selections.map((chip) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.teacherPrimaryLight,
                                        borderRadius:
                                            BorderRadius.circular(
                                                TeacherDimensions.radiusS),
                                      ),
                                      child: Text(
                                        chip,
                                        style: TeacherTypography.caption
                                            .copyWith(
                                          color: AppColors.teacherPrimary,
                                        ),
                                      ),
                                    );
                                  }),
                                  if (latest.feeling != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Image.asset(
                                          'assets/blobs/blob-${latest.feeling}.png',
                                          width: 22,
                                          height: 22,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          latest.feeling![0].toUpperCase() +
                                              latest.feeling!
                                                  .substring(1),
                                          style:
                                              TeacherTypography.caption,
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            // Free-text comment (if any)
                            if (latest.commentText.isNotEmpty) ...[
                              if (latest.selections.isNotEmpty)
                                const SizedBox(height: 6),
                              Text(
                                latest.commentText,
                                style:
                                    TeacherTypography.bodyMedium.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              '— $parentName · ${_formatCommentDate(latest.date)}',
                              style: TeacherTypography.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionInfoCard(String message, {bool isError = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Text(
        message,
        style: TeacherTypography.bodyMedium.copyWith(
          color: isError ? AppColors.error : AppColors.textSecondary,
        ),
      ),
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
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
          border: Border.all(color: AppColors.divider),
          color: AppColors.white,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.teacherPrimaryLight.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              ),
              child: Icon(icon, color: AppColors.teacherPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TeacherTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TeacherTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignedBookViewData {
  final String title;
  final String subtitle;
  final String bookType;
  final String status;
  final List<Color> coverGradient;
  final String? coverImageUrl;
  final bool shouldResolveCover;
  final String? allocationId;
  final String? assignmentItemId;

  const _AssignedBookViewData({
    required this.title,
    required this.subtitle,
    required this.bookType,
    required this.status,
    required this.coverGradient,
    this.coverImageUrl,
    this.shouldResolveCover = false,
    this.allocationId,
    this.assignmentItemId,
  });
}

class _CachedBookCover {
  const _CachedBookCover({
    required this.bookId,
    required this.title,
    this.isbn,
    this.coverImageUrl,
  });

  final String bookId;
  final String title;
  final String? isbn;
  final String? coverImageUrl;
}

class _ReadingLogSnapshot {
  final String id;
  final DateTime date;
  final String? allocationId;
  final List<String> bookTitles;
  final String status;
  final int minutesRead;
  final int targetMinutes;
  final String? parentId;
  final String? parentComment;
  final List<String> parentCommentSelections;
  final String? parentCommentFreeText;
  final String? childFeeling;

  const _ReadingLogSnapshot({
    required this.id,
    required this.date,
    required this.allocationId,
    required this.bookTitles,
    required this.status,
    required this.minutesRead,
    required this.targetMinutes,
    required this.parentId,
    required this.parentComment,
    required this.parentCommentSelections,
    required this.parentCommentFreeText,
    required this.childFeeling,
  });
}

class _LatestParentCommentViewData {
  final String? parentId;
  final String commentText;
  final DateTime date;
  final List<String> selections;
  final String? feeling;

  const _LatestParentCommentViewData({
    required this.parentId,
    required this.commentText,
    required this.date,
    required this.selections,
    this.feeling,
  });
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
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Keep books for next week',
                style: TeacherTypography.h3,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Uncheck books being returned',
                style: TeacherTypography.bodySmall,
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
                  style: TeacherTypography.bodyMedium,
                ),
                value: _selected.contains(i),
                activeColor: AppColors.teacherPrimary,
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
                        final result = _selected
                            .map((i) => widget.items[i])
                            .toList();
                        Navigator.of(context).pop(result);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teacherPrimary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                ),
                child: Text(
                  selectedCount > 0
                      ? 'Keep $selectedCount book(s) for next week'
                      : 'Select books to keep',
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.white,
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TeacherDimensions.radiusXL),
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
                      color: AppColors.teacherBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Choose a Book', style: TeacherTypography.h3),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search by title or author...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppColors.teacherBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            TeacherDimensions.radiusM),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<BookModel>>(
                stream: _libraryService.booksStream(widget.schoolId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var books = snapshot.data!;
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
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No books match "$_searchQuery"'
                            : 'No books in library yet',
                        style: TeacherTypography.bodySmall,
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: books.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: AppColors.teacherBorder,
                    ),
                    itemBuilder: (context, index) {
                      final book = books[index];
                      final hasCover = book.coverImageUrl != null &&
                          book.coverImageUrl!.isNotEmpty &&
                          book.coverImageUrl!.startsWith('http');
                      return InkWell(
                        onTap: () => Navigator.pop(context, book),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 36,
                                  height: 50,
                                  child: hasCover
                                      ? PersistentCachedImage(
                                          imageUrl:
                                              book.coverImageUrl!,
                                          fit: BoxFit.cover,
                                          fallback: Container(
                                            color: AppColors
                                                .teacherPrimaryLight,
                                            child: const Icon(
                                                Icons.menu_book,
                                                size: 16,
                                                color: AppColors
                                                    .teacherPrimary),
                                          ),
                                        )
                                      : Container(
                                          color: AppColors
                                              .teacherPrimaryLight,
                                          child: const Icon(
                                              Icons.menu_book,
                                              size: 16,
                                              color: AppColors
                                                  .teacherPrimary),
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
                                      style: TeacherTypography
                                          .bodyMedium
                                          .copyWith(
                                              fontWeight:
                                                  FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (book.author != null)
                                      Text(
                                        book.author!,
                                        style:
                                            TeacherTypography.caption,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.4),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Scan Replacement Book',
          style:
              TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      body:
          _resolvedBook != null ? _buildConfirmView() : _buildScannerView(),
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
            color: AppColors.charcoal.withValues(alpha: 0.85),
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
                          color: AppColors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Looking up book...',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          color: AppColors.white,
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
                      color: AppColors.white,
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
      color: AppColors.teacherBackground,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius:
                BorderRadius.circular(TeacherDimensions.radiusM),
            child: SizedBox(
              width: 120,
              height: 170,
              child: hasCover
                  ? PersistentCachedImage(
                      imageUrl: book.coverImageUrl!,
                      fit: BoxFit.cover,
                      fallback: Container(
                        color: AppColors.teacherPrimaryLight,
                        child: const Icon(Icons.menu_book,
                            size: 40, color: AppColors.teacherPrimary),
                      ),
                    )
                  : Container(
                      color: AppColors.teacherPrimaryLight,
                      child: const Icon(Icons.menu_book,
                          size: 40, color: AppColors.teacherPrimary),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            book.title,
            style: TeacherTypography.h2,
            textAlign: TextAlign.center,
          ),
          if (book.author != null) ...[
            const SizedBox(height: 4),
            Text(
              book.author!,
              style: TeacherTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
          if (book.isbn != null) ...[
            const SizedBox(height: 8),
            Text('ISBN ${book.isbn}', style: TeacherTypography.caption),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, book),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teacherPrimary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                      TeacherDimensions.radiusM),
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
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.teacherPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
