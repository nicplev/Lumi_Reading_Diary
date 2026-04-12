import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/persistent_cached_image.dart';
import '../../data/models/book_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/book_lookup_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/teacher_device_book_cache_service.dart';
import 'cover_scanner_screen.dart';

class IsbnScannerScreen extends StatefulWidget {
  const IsbnScannerScreen({
    super.key,
    required this.teacher,
    required this.classModel,
    this.student,
    this.studentQueue,
    this.initialTargetDate,
  }) : assert(
          student != null || (studentQueue != null && studentQueue.length > 0),
          'Either student or non-empty studentQueue must be provided',
        );

  final UserModel teacher;
  final ClassModel classModel;
  final StudentModel? student;
  final List<StudentModel>? studentQueue;
  final DateTime? initialTargetDate;

  @override
  State<IsbnScannerScreen> createState() => _IsbnScannerScreenState();
}

class _IsbnScannerScreenState extends State<IsbnScannerScreen> {
  final IsbnAssignmentService _assignmentService = IsbnAssignmentService();
  final MobileScannerController _scannerController = MobileScannerController();

  // --- Session scan state (reset per student in batch mode) ---
  final Set<String> _sessionIsbns = <String>{};
  final Set<String> _pendingIsbns = <String>{};
  final List<ScannedIsbnBook> _sessionBooks = <ScannedIsbnBook>[];

  bool _isProcessing = false;
  bool _isTorchEnabled = false;
  String? _statusMessage;
  int _totalAssignedBooks = 0;
  late String _sessionId;

  // --- Batch queue state ---
  late final List<StudentModel> _queue;
  int _currentQueueIndex = 0;
  final Map<String, List<ScannedIsbnBook>> _booksByStudent =
      <String, List<ScannedIsbnBook>>{};
  final Set<String> _skippedStudentIds = <String>{};

  bool get _isBatchMode => _queue.length > 1;
  StudentModel get _currentStudent => _queue[_currentQueueIndex];
  bool get _isLastStudent => _currentQueueIndex >= _queue.length - 1;

  int get _completedStudentCount {
    var count = 0;
    for (var i = 0; i < _currentQueueIndex; i++) {
      if (!_skippedStudentIds.contains(_queue[i].id)) count++;
    }
    // Count current student if they have books scanned
    if (_sessionBooks.isNotEmpty) count++;
    return count;
  }

  // --- Week selector state ---
  late DateTime _targetDate;

  DateTime get _weekStart => IsbnAssignmentService.startOfWeek(_targetDate);
  DateTime get _weekEnd => IsbnAssignmentService.endOfWeek(_targetDate);

  String get _weekLabel {
    final now = DateTime.now();
    final currentWeekStart = IsbnAssignmentService.startOfWeek(now);
    final nextWeekStart = currentWeekStart.add(const Duration(days: 7));
    final fmt = DateFormat('MMM d');

    final prefix = _weekStart == currentWeekStart
        ? 'This week'
        : _weekStart == nextWeekStart
            ? 'Next week'
            : null;
    final range = '${fmt.format(_weekStart)}\u2013${fmt.format(_weekEnd)}';
    return prefix != null ? '$prefix ($range)' : range;
  }

  bool get _canGoBack {
    final currentWeekStart = IsbnAssignmentService.startOfWeek(DateTime.now());
    return _weekStart.isAfter(currentWeekStart);
  }

  bool get _canGoForward {
    final currentWeekStart = IsbnAssignmentService.startOfWeek(DateTime.now());
    final maxWeekStart = currentWeekStart.add(const Duration(days: 14));
    return _weekStart.isBefore(maxWeekStart);
  }

  // --- Duplicate count state ---
  Map<String, int> _isbnStudentCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _targetDate = widget.initialTargetDate ?? DateTime.now();

    if (widget.studentQueue != null && widget.studentQueue!.isNotEmpty) {
      _queue = List<StudentModel>.from(widget.studentQueue!)
        ..sort((a, b) => a.firstName.compareTo(b.firstName));
    } else {
      _queue = [widget.student!];
    }

    _loadIsbnCounts();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadIsbnCounts() async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;

    try {
      final counts = await _assignmentService.countStudentsWithIsbnsForWeek(
        schoolId: schoolId,
        classId: widget.classModel.id,
        referenceDate: _targetDate,
      );
      if (mounted) {
        setState(() => _isbnStudentCounts = counts);
      }
    } catch (_) {
      // Non-critical — badge just won't show
    }
  }

  // ---- Barcode detection & interactive assignment ----

  bool _isProcessingQueue = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    var queuedAny = false;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      final normalized = IsbnAssignmentService.normalizeIsbn(rawValue);
      if (normalized == null) continue;
      if (_sessionIsbns.contains(normalized) ||
          _pendingIsbns.contains(normalized)) {
        continue;
      }
      _pendingIsbns.add(normalized);
      queuedAny = true;
    }

    if (!queuedAny) return;
    await _processIsbnQueue();
  }

  /// Process pending ISBNs one at a time. Resolved books are assigned
  /// immediately. Unresolved ISBNs pause the queue and show a prompt.
  Future<void> _processIsbnQueue() async {
    if (_isProcessingQueue || _pendingIsbns.isEmpty) return;
    _isProcessingQueue = true;

    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Cannot assign: teacher is missing school ID.';
        });
      }
      _pendingIsbns.clear();
      _isProcessingQueue = false;
      return;
    }

    while (_pendingIsbns.isNotEmpty && mounted) {
      final isbn = _pendingIsbns.first;
      _pendingIsbns.remove(isbn);

      setState(() {
        _isProcessing = true;
        _statusMessage = 'Looking up ISBN...';
      });

      final resolution = await _assignmentService.resolveIsbn(
        rawCode: isbn,
        schoolId: schoolId,
        teacherId: widget.teacher.id,
      );

      if (!mounted) break;

      switch (resolution) {
        case IsbnResolved(:final book):
          await _assignAndAddToSession(book, schoolId);

        case IsbnNotFound(:final isbn):
          setState(() => _isProcessing = false);
          final result = await _showUnresolvedPrompt(isbn);
          if (!mounted) break;
          if (result != null) {
            await _assignAndAddToSession(result, schoolId);
          }

        case IsbnInvalid():
          break;
      }
    }

    if (mounted) {
      setState(() => _isProcessing = false);
    }
    _isProcessingQueue = false;
  }

  /// Assign a resolved book to the current student and update session state.
  Future<bool> _showPreviouslyReadWarning(ScannedIsbnBook book) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PreviouslyReadWarningSheet(
        studentName: _currentStudent.firstName,
        bookTitle: book.title,
        coverImageUrl: book.coverImageUrl,
      ),
    );
    return result ?? false;
  }

  Future<void> _assignAndAddToSession(
    ScannedIsbnBook book,
    String schoolId,
  ) async {
    final alreadyRead = await _assignmentService.studentHasPreviouslyReadBook(
      studentId: _currentStudent.id,
      bookId: book.bookId,
      isbn: book.isbn,
    );
    if (alreadyRead) {
      if (!mounted) return;
      final proceed = await _showPreviouslyReadWarning(book);
      if (!proceed) return;
    }

    try {
      final result = await _assignmentService.assignResolvedBooks(
        schoolId: schoolId,
        classId: widget.classModel.id,
        studentId: _currentStudent.id,
        teacherId: widget.teacher.id,
        books: [book],
        targetMinutes: widget.classModel.defaultMinutesTarget,
        sessionId: _sessionId,
        targetDate: _targetDate,
      );

      if (_sessionIsbns.add(book.isbn)) {
        _sessionBooks.insert(0, book);
        _isbnStudentCounts[book.isbn] =
            (_isbnStudentCounts[book.isbn] ?? 0) + 1;
      }
      _totalAssignedBooks = result.totalAssignedBooks;

      final isNew = result.newlyAssignedBooks.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _statusMessage = isNew
            ? 'Assigned "${book.title}" for this week.'
            : 'Already assigned this week.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not assign "${book.title}". Please try again.';
      });
    }
  }

  /// Show a blocking prompt for an unresolved ISBN. Returns a [ScannedIsbnBook]
  /// if the teacher adds the book via the inline flow, or null if discarded.
  Future<ScannedIsbnBook?> _showUnresolvedPrompt(String isbn) async {
    // 'add' = launch inline add flow, 'discard' = skip this ISBN
    final action = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Warning icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.warmOrange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  color: AppColors.warmOrange,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text('Book Not Found', style: TeacherTypography.h3),
              const SizedBox(height: 8),
              Text(
                'ISBN $isbn wasn\'t found in any book database.',
                style: TeacherTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'You can add it to the Lumi community library by taking a photo of the front cover.',
                style: TeacherTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Add Book button (primary)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, 'add'),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Add Book'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teacherPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusM),
                    ),
                    textStyle: TeacherTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Discard button (secondary)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, 'discard'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusM),
                    ),
                    side: const BorderSide(color: AppColors.teacherBorder),
                  ),
                  child: Text(
                    'Discard This Scan',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (action == 'add' && mounted) {
      return _launchInlineAddFlow(isbn);
    }

    return null; // discarded
  }

  /// Launch the inline cover scanner in ISBN-first mode and handle the result.
  Future<ScannedIsbnBook?> _launchInlineAddFlow(String isbn) async {
    final contributionResult =
        await Navigator.of(context).push<CommunityBookContributionResult>(
      MaterialPageRoute(
        builder: (_) => CoverScannerScreen(
          teacher: widget.teacher,
          mode: CommunityBookContributionMode.isbnFirstInline,
          preScannedIsbn: isbn,
        ),
      ),
    );

    if (contributionResult == null || !mounted) return null;

    // Materialize to school library
    final schoolId = widget.teacher.schoolId ?? '';
    if (schoolId.isNotEmpty) {
      final lookupService = BookLookupService();
      await lookupService.materializeToSchoolLibrary(
        isbn: isbn,
        book: BookModel(
          id: contributionResult.bookId ?? 'isbn_$isbn',
          title: contributionResult.title,
          author: contributionResult.author,
          isbn: isbn,
          coverImageUrl: contributionResult.coverImageUrl,
          readingLevel: contributionResult.readingLevel,
          createdAt: DateTime.now(),
        ),
        source: 'community_books',
        schoolId: schoolId,
        actorId: widget.teacher.id,
      );

      // Warm device scan cache
      try {
        await TeacherDeviceBookCacheService.instance.cacheBook(
          teacherId: widget.teacher.id,
          schoolId: schoolId,
          book: BookModel(
            id: contributionResult.bookId ?? 'isbn_$isbn',
            title: contributionResult.title,
            author: contributionResult.author,
            isbn: isbn,
            coverImageUrl: contributionResult.coverImageUrl,
            readingLevel: contributionResult.readingLevel,
            createdAt: DateTime.now(),
          ),
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _statusMessage = 'Added to library and assigned.';
      });
    }

    return ScannedIsbnBook(
      isbn: isbn,
      title: contributionResult.title,
      author: contributionResult.author,
      coverImageUrl: contributionResult.coverImageUrl,
      bookId: contributionResult.bookId ?? 'isbn_$isbn',
      resolvedFromCatalog: true,
      isNewToLibrary: true,
    );
  }

  // ---- Batch queue navigation ----

  void _advanceToNextStudent() {
    // Save current student's books
    _booksByStudent[_currentStudent.id] =
        List<ScannedIsbnBook>.from(_sessionBooks);

    if (_isLastStudent) {
      _finishScanner();
      return;
    }

    setState(() {
      _currentQueueIndex++;
      _sessionBooks.clear();
      _sessionIsbns.clear();
      _pendingIsbns.clear();
      _totalAssignedBooks = 0;
      _statusMessage = null;
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    });
  }

  void _skipCurrentStudent() {
    _skippedStudentIds.add(_currentStudent.id);
    _advanceToNextStudent();
  }

  void _finishScanner() {
    // Save current student's books if any
    if (_sessionBooks.isNotEmpty) {
      _booksByStudent[_currentStudent.id] =
          List<ScannedIsbnBook>.from(_sessionBooks);
    }

    if (_isBatchMode) {
      final totalScanned = _booksByStudent.values
          .fold<int>(0, (sum, books) => sum + books.length);
      final studentsAssigned =
          _booksByStudent.values.where((b) => b.isNotEmpty).length;
      Navigator.of(context).pop({
        'scannedCount': totalScanned,
        'studentsAssigned': studentsAssigned,
        'skippedCount': _skippedStudentIds.length,
        'totalStudents': _queue.length,
      });
    } else {
      Navigator.of(context).pop({
        'scannedCount': _sessionBooks.length,
        'totalAssignedBooks': _totalAssignedBooks,
      });
    }
  }

  // ---- Week selector ----

  void _shiftWeek(int weeks) {
    setState(() {
      _targetDate = _targetDate.add(Duration(days: 7 * weeks));
      // Clear scan state since week changed
      _sessionBooks.clear();
      _sessionIsbns.clear();
      _pendingIsbns.clear();
      _totalAssignedBooks = 0;
      _statusMessage = null;
    });
    _loadIsbnCounts();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final studentName = _currentStudent.firstName;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _isBatchMode
              ? 'Scan ISBN \u2022 $studentName (${_currentQueueIndex + 1}/${_queue.length})'
              : 'Scan ISBN \u2022 ${_currentStudent.fullName}',
          style: TeacherTypography.bodyLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: Icon(_isTorchEnabled ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              _scannerController.toggleTorch();
              setState(() {
                _isTorchEnabled = !_isTorchEnabled;
              });
            },
          ),
          if (_isBatchMode) ...[
            TextButton(
              onPressed: _isProcessing ? null : _skipCurrentStudent,
              child: Text(
                'Skip',
                style: TextStyle(
                  color: _isProcessing ? Colors.white38 : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: _isProcessing ? null : _advanceToNextStudent,
              child: Text(
                _isLastStudent ? 'Done' : 'Next',
                style: TextStyle(
                  color: _isProcessing ? Colors.white38 : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ] else
            TextButton(
              onPressed: _finishScanner,
              child: const Text(
                'Done',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Batch progress bar
          if (_isBatchMode)
            LinearProgressIndicator(
              value: (_currentQueueIndex + 1) / _queue.length,
              backgroundColor: Colors.white12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.teacherPrimary),
              minHeight: 3,
            ),

          // Week selector bar
          _buildWeekSelector(),

          // Camera
          Expanded(
            flex: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) {
                    return ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Camera unavailable. Please enable camera permissions.',
                            style: TeacherTypography.bodyMedium.copyWith(
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Center(
                  child: Container(
                    width: 260,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.teacherPrimaryLight,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 18,
                  child: Text(
                    'Point camera at ISBN/EAN barcodes. Multiple in one frame are supported.',
                    style: TeacherTypography.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Bottom panel
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        _InfoChip(
                          icon: Icons.qr_code,
                          label: '${_sessionBooks.length} scanned',
                        ),
                        const SizedBox(width: 8),
                        if (_isBatchMode)
                          _InfoChip(
                            icon: Icons.people,
                            label:
                                '$_completedStudentCount/${_queue.length} students',
                          )
                        else
                          _InfoChip(
                            icon: Icons.menu_book,
                            label: '$_totalAssignedBooks total this week',
                          ),
                        const Spacer(),
                        if (_isProcessing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  if (_statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _statusMessage!,
                        style: TeacherTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _sessionBooks.isEmpty
                        ? Center(
                            child: Text(
                              'No ISBN scanned yet',
                              style: TeacherTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            itemCount: _sessionBooks.length,
                            itemBuilder: (context, index) {
                              final book = _sessionBooks[index];
                              return _buildBookCard(book);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSelector() {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white70),
            iconSize: 20,
            onPressed: _canGoBack ? () => _shiftWeek(-1) : null,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            _weekLabel,
            style: TeacherTypography.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white70),
            iconSize: 20,
            onPressed: _canGoForward ? () => _shiftWeek(1) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBookCard(ScannedIsbnBook book) {
    final studentCount = _isbnStudentCounts[book.isbn] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Row(
        children: [
          // Cover thumbnail or status icon
          if (book.coverImageUrl != null && book.coverImageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: PersistentCachedImage(
                imageUrl: book.coverImageUrl!,
                width: 36,
                height: 48,
                fit: BoxFit.cover,
                fallback: Icon(
                  book.resolvedFromCatalog
                      ? Icons.check_circle
                      : Icons.info_outline,
                  color: book.resolvedFromCatalog
                      ? Colors.green
                      : AppColors.warmOrange,
                  size: 18,
                ),
              ),
            )
          else
            Icon(
              book.resolvedFromCatalog
                  ? Icons.check_circle
                  : Icons.info_outline,
              color: book.resolvedFromCatalog
                  ? Colors.green
                  : AppColors.warmOrange,
              size: 18,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: TeacherTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (book.author != null && book.author!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    book.author!,
                    style: TeacherTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'ISBN ${book.isbn}',
                      style: TeacherTypography.caption,
                    ),
                    if (studentCount > 1) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.teacherPrimaryLight
                              .withValues(alpha: 0.3),
                          borderRadius:
                              BorderRadius.circular(TeacherDimensions.radiusS),
                        ),
                        child: Text(
                          '$studentCount students',
                          style: TeacherTypography.caption.copyWith(
                            color: AppColors.teacherPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
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
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.teacherPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TeacherTypography.caption.copyWith(
              color: AppColors.charcoal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviouslyReadWarningSheet extends StatelessWidget {
  const _PreviouslyReadWarningSheet({
    required this.studentName,
    required this.bookTitle,
    this.coverImageUrl,
  });

  final String studentName;
  final String bookTitle;
  final String? coverImageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_edu_rounded,
              color: Color(0xFFFFA000),
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$studentName has read this before',
            style: TeacherTypography.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '"$bookTitle" may already be in $studentName\'s reading history.',
            style: TeacherTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.teacherPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
                textStyle: TeacherTypography.bodyMedium
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              child: const Text('Assign Anyway'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
                textStyle: TeacherTypography.bodyMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text(
                'Skip Book',
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
