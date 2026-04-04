import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/reading_level_history_sheet.dart';
import '../../core/widgets/lumi/reading_level_picker_sheet.dart';
import '../../core/widgets/lumi/teacher_stat_card.dart';
import '../../core/widgets/lumi/teacher_book_assignment_card.dart';
import '../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../core/widgets/lumi/teacher_student_list_item.dart';
import '../../data/models/user_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/student_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/book_cover_cache_service.dart';
import '../../services/book_lookup_service.dart';
import '../../services/book_metadata_resolver.dart';
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
  bool _levelsEnabled = true;
  StudentModel? _studentOverride;
  bool _readingLevelExpanded = false;

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
    final nextTitle = await _promptBookTitle(
      title: 'Swap Book',
      hintText: 'Replacement book title',
      initialValue: '',
    );
    if (nextTitle == null) return;

    final scope = await _pickActionScope(actionLabel: 'Swap');
    if (scope == null) return;

    if (scope == _AssignmentEditScope.wholeClass) {
      await _allocationCrudService.swapBookGlobally(
        schoolId: widget.student.schoolId,
        allocationId: allocationId,
        actorId: widget.teacher.id,
        removeItemId: itemId,
        nextTitle: nextTitle,
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
      nextMetadata: const {'source': 'student_swap'},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Swapped "$currentTitle" for ${widget.student.firstName}.')),
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
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: TeacherTypography.bodyMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.teacherPrimary,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.teacherPrimary,
        side: BorderSide(
          color: AppColors.teacherPrimary.withValues(alpha: 0.3),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusM)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
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
      final hasComment = (log.parentComment?.isNotEmpty ?? false) ||
          log.parentCommentSelections.isNotEmpty ||
          (log.parentCommentFreeText?.isNotEmpty ?? false);
      if (!hasComment) continue;

      final text = _composeCommentText(log);
      if (text.isEmpty) continue;

      return _LatestParentCommentViewData(
        parentId: log.parentId,
        commentText: text,
        date: log.date,
        selections: log.parentCommentSelections,
        starRating: _starRatingFromFeeling(log.childFeeling),
      );
    }
    return null;
  }

  String _composeCommentText(_ReadingLogSnapshot log) {
    final chips = log.parentCommentSelections.join('. ');
    final freeText = log.parentCommentFreeText?.trim() ?? '';
    final structured =
        [chips, freeText].where((value) => value.isNotEmpty).join('. ').trim();
    if (structured.isNotEmpty) return structured;
    return log.parentComment?.trim() ?? '';
  }

  int? _starRatingFromFeeling(String? childFeeling) {
    switch (childFeeling) {
      case 'hard':
        return 1;
      case 'tricky':
        return 2;
      case 'okay':
        return 3;
      case 'good':
        return 4;
      case 'great':
        return 5;
      default:
        return null;
    }
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
          behavior: SnackBarBehavior.floating,
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
          behavior: SnackBarBehavior.floating,
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
        behavior: SnackBarBehavior.floating,
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
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Student Detail',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student header
            _buildStudentHeader(),
            const SizedBox(height: 20),

            if (_levelsEnabled) ...[
              _buildReadingLevelCard(),
              const SizedBox(height: 20),
            ],

            // Stats cards (2-column)
            _buildStatsRow(),
            const SizedBox(height: 24),

            // Assigned Books section
            _buildAssignedBooksSection(),
            const SizedBox(height: 24),

            // Latest Parent Comment
            _buildParentCommentSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentHeader() {
    final fullName = _currentStudent.fullName;

    return Row(
      children: [
        CircleAvatar(
          radius: TeacherDimensions.avatarM / 2,
          backgroundColor: TeacherStudentListItem.colorForName(fullName),
          child: Text(
            _currentStudent.firstName[0].toUpperCase(),
            style: TeacherTypography.statValue.copyWith(
              color: AppColors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fullName, style: TeacherTypography.h2),
              if (_levelsEnabled) ...[
                const SizedBox(height: 6),
                TeacherReadingLevelPill(
                  label: _readingLevelCompactLabel(_currentStudent),
                  isUnset: _isReadingLevelUnset(_currentStudent),
                  isUnresolved: _isReadingLevelUnresolved(_currentStudent),
                  onTap: _showReadingLevelPicker,
                ),
              ],
            ],
          ),
        ),
      ],
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

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: TeacherStatCard(
            icon: Icons.local_fire_department,
            iconColor: AppColors.warmOrange,
            iconBgColor: AppColors.warmOrange.withValues(alpha: 0.15),
            value: '${_currentStudent.stats?.currentStreak ?? 0}',
            label: 'Day Streak',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TeacherStatCard(
            icon: Icons.nights_stay,
            iconColor: AppColors.teacherPrimary,
            iconBgColor: AppColors.teacherPrimaryLight,
            value: '${_currentStudent.stats?.totalReadingDays ?? 0}',
            label: 'Total Nights',
          ),
        ),
      ],
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
              return _buildSectionInfoCard('No parent comments yet.');
            }

            return FutureBuilder<String>(
              future: _getParentName(latest.parentId),
              builder: (context, parentSnapshot) {
                final parentName = parentSnapshot.data ?? 'Parent';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusL),
                    boxShadow: TeacherDimensions.cardShadow,
                    border: const Border(
                      left: BorderSide(
                        color: AppColors.teacherPrimary,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '"${latest.commentText}"',
                        style: TeacherTypography.bodyMedium.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if (latest.selections.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: latest.selections.map((chip) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.teacherPrimaryLight,
                                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                              ),
                              child: Text(
                                chip,
                                style: TeacherTypography.caption.copyWith(
                                  color: AppColors.teacherPrimary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (latest.starRating != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: List.generate(5, (index) {
                            final isFilled = index < latest.starRating!;
                            return Icon(
                              isFilled ? Icons.star : Icons.star_border,
                              size: 16,
                              color: AppColors.warmOrange,
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '— $parentName • ${_formatCommentDate(latest.date)}',
                        style: TeacherTypography.bodySmall,
                      ),
                    ],
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
  final int? starRating;

  const _LatestParentCommentViewData({
    required this.parentId,
    required this.commentText,
    required this.date,
    required this.selections,
    required this.starRating,
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
