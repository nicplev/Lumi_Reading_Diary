import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/characters/lumi_character.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/persistent_cached_image.dart';
import '../../data/models/book_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/book_lookup_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/teacher_device_book_cache_service.dart';
import 'cover_scanner_screen.dart';
import '../../core/utils/image_decode.dart';

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

  // Bumped each time a scan is accepted — drives the reticle flash, success
  // check, and haptic feedback.
  int _scanFlashTick = 0;

  // --- Batch queue state ---
  late final List<StudentModel> _queue;
  int _currentQueueIndex = 0;
  final Map<String, List<ScannedIsbnBook>> _booksByStudent =
      <String, List<ScannedIsbnBook>>{};
  final Set<String> _skippedStudentIds = <String>{};
  double _panelDragOffset = 0;
  bool _isDraggingPanel = false;

  bool get _isBatchMode => _queue.length > 1;
  StudentModel get _currentStudent => _queue[_currentQueueIndex];
  bool get _isLastStudent => _currentQueueIndex >= _queue.length - 1;
  bool get _canChangeStudent => !_isProcessing && !_isProcessingQueue;

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
    final range = '${fmt.format(_weekStart)}–${fmt.format(_weekEnd)}';
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

  Future<void> _retryCamera() async {
    await Permission.camera.request();
    try {
      await _scannerController.start();
    } catch (_) {}
    if (mounted) setState(() {});
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

        case IsbnLookupUnavailable():
          setState(() {
            _isProcessing = false;
            _statusMessage =
                "You're offline — can't look that book up right now. "
                'Try again once you\'re connected.';
          });

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
      // Confirm the scan landed with a haptic tick + reticle flash.
      if (isNew) HapticFeedback.mediumImpact();
      setState(() {
        if (isNew) _scanFlashTick++;
        if (result.queuedOffline) {
          _statusMessage =
              'Saved "${book.title}" — it\'ll assign once you\'re back online.';
        } else {
          _statusMessage = isNew
              ? 'Assigned "${book.title}" for this week.'
              : 'Already assigned this week.';
        }
      });
    } catch (e) {
      debugPrint(
        '[IsbnAssignment] failed code='
        '${IsbnAssignmentService.diagnosticCode(e)}',
      );
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
            color: LumiTokens.paper,
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
                    color: LumiTokens.rule,
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
                  color: LumiTokens.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  color: LumiTokens.orange,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text('Book not found', style: LumiType.subhead),
              const SizedBox(height: 8),
              Text(
                'ISBN $isbn wasn\'t found in any book database.',
                style: LumiType.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'You can add it to the Lumi community library by taking a photo of the front cover.',
                style: LumiType.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Add Book button (primary)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, 'add'),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Add book'),
                  style: FilledButton.styleFrom(
                    backgroundColor: LumiTokens.green,
                    foregroundColor: LumiTokens.paper,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                    ),
                    textStyle: LumiType.button,
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
                          BorderRadius.circular(LumiTokens.radiusMedium),
                    ),
                    side: const BorderSide(color: LumiTokens.rule),
                  ),
                  child: Text(
                    'Discard this scan',
                    style: LumiType.button.copyWith(color: LumiTokens.muted),
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
        source: contributionResult.schoolLocalOnly
            ? 'demo_school_local'
            : 'community_books',
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
      _panelDragOffset = 0;
      _isDraggingPanel = false;
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

  void _onPanelDragStart(DragStartDetails details) {
    if (!_canChangeStudent) return;
    setState(() => _isDraggingPanel = true);
  }

  void _onPanelDragUpdate(DragUpdateDetails details) {
    if (!_canChangeStudent) return;
    final maxDrag = MediaQuery.sizeOf(context).width * 0.55;
    setState(() {
      _panelDragOffset =
          (_panelDragOffset + details.delta.dx).clamp(-maxDrag, 0.0).toDouble();
    });
  }

  void _onPanelDragEnd(DragEndDetails details) {
    if (!_canChangeStudent) {
      _resetPanelDrag();
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    final shouldAdvance = _panelDragOffset <= -72 || velocity <= -550;
    if (shouldAdvance) {
      HapticFeedback.selectionClick();
      _advanceToNextStudent();
      return;
    }

    _resetPanelDrag();
  }

  void _resetPanelDrag() {
    if (!mounted) return;
    setState(() {
      _panelDragOffset = 0;
      _isDraggingPanel = false;
    });
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        titleSpacing: 0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: _buildWeekSelector(),
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
        ],
      ),
      body: Column(
        children: [
          // Batch progress bar
          if (_isBatchMode)
            LinearProgressIndicator(
              value: (_currentQueueIndex + 1) / _queue.length,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(LumiTokens.green),
              minHeight: 3,
            ),

          // Camera
          Expanded(
            flex: 13,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _buildCameraError(),
                ),
                Positioned(
                  top: LumiTokens.space4,
                  left: LumiTokens.space4,
                  right: LumiTokens.space4,
                  child: _StudentIdentityOverlay(
                    student: _currentStudent,
                    position: _isBatchMode ? _currentQueueIndex + 1 : null,
                    total: _isBatchMode ? _queue.length : null,
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: _ReticleOverlay(flashTick: _scanFlashTick),
                ),
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: _ScanSuccessTickOverlay(tick: _scanFlashTick),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 18,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusPill),
                      ),
                      child: Text(
                        'Point at ISBN/EAN barcodes — scan several in one frame.',
                        style: LumiType.caption.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom panel
          Expanded(
            flex: 7,
            child: GestureDetector(
              key: const Key('isbn_scan_results_panel'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart:
                  _isBatchMode && _canChangeStudent ? _onPanelDragStart : null,
              onHorizontalDragUpdate:
                  _isBatchMode && _canChangeStudent ? _onPanelDragUpdate : null,
              onHorizontalDragEnd:
                  _isBatchMode && _canChangeStudent ? _onPanelDragEnd : null,
              onHorizontalDragCancel: _isBatchMode ? _resetPanelDrag : null,
              child: AnimatedSlide(
                offset: Offset(
                  _panelDragOffset / MediaQuery.sizeOf(context).width,
                  0,
                ),
                duration: _isDraggingPanel
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _buildBottomPanel(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraError() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded,
                  color: Colors.white70, size: 40),
              const SizedBox(height: 16),
              Text(
                'Camera unavailable',
                style: LumiType.subhead.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enable camera access for Lumi to scan book barcodes.',
                style: LumiType.body.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open settings'),
                style: FilledButton.styleFrom(
                  backgroundColor: LumiTokens.green,
                  foregroundColor: LumiTokens.paper,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                  ),
                  textStyle: LumiType.button,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _retryCamera,
                child: Text(
                  'Retry',
                  style: LumiType.button.copyWith(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left),
          color: Colors.white70,
          disabledColor: Colors.white24,
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 40),
          onPressed: _canGoBack ? () => _shiftWeek(-1) : null,
          visualDensity: VisualDensity.compact,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LumiTokens.space1),
          child: Text(
            _weekLabel,
            style: LumiType.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right),
          color: Colors.white70,
          disabledColor: Colors.white24,
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 40),
          onPressed: _canGoForward ? () => _shiftWeek(1) : null,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      key: ValueKey(_currentStudent.id),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(LumiTokens.radiusXL),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isBatchMode) ...[
            const SizedBox(height: LumiTokens.space2),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LumiTokens.rule,
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LumiTokens.space4,
                LumiTokens.space1,
                LumiTokens.space2,
                0,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.swipe_left_rounded,
                    size: 18,
                    color: LumiTokens.muted,
                  ),
                  const SizedBox(width: LumiTokens.space2),
                  Expanded(
                    child: Text(
                      _isLastStudent
                          ? 'Swipe left to finish'
                          : 'Swipe left for next student',
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('isbn_batch_skip_button'),
                    onPressed: _canChangeStudent ? _skipCurrentStudent : null,
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text('Skip'),
                    style: TextButton.styleFrom(
                      foregroundColor: LumiTokens.muted,
                      disabledForegroundColor:
                          LumiTokens.muted.withValues(alpha: 0.45),
                      textStyle: LumiType.button,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LumiTokens.space4,
                LumiTokens.space3,
                LumiTokens.space3,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    'Scanned books',
                    style: LumiType.subhead.copyWith(fontSize: 18),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('isbn_single_done_button'),
                    onPressed: _canChangeStudent ? _finishScanner : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Done'),
                    style: FilledButton.styleFrom(
                      backgroundColor: LumiTokens.green,
                      foregroundColor: LumiTokens.paper,
                      disabledBackgroundColor:
                          LumiTokens.green.withValues(alpha: 0.45),
                      disabledForegroundColor: LumiTokens.paper,
                      padding: const EdgeInsets.symmetric(
                        horizontal: LumiTokens.space4,
                        vertical: LumiTokens.space2,
                      ),
                      visualDensity: VisualDensity.compact,
                      textStyle: LumiType.button,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
              LumiTokens.space4,
              _isBatchMode ? 0 : LumiTokens.space2,
              LumiTokens.space4,
              LumiTokens.space2,
            ),
            child: Row(
              children: [
                _InfoChip(
                  icon: Icons.qr_code_rounded,
                  label: '${_sessionBooks.length} scanned',
                ),
                const SizedBox(width: LumiTokens.space2),
                if (_isBatchMode)
                  _InfoChip(
                    icon: Icons.people_alt_rounded,
                    label: '$_completedStudentCount/${_queue.length} students',
                  )
                else
                  _InfoChip(
                    icon: Icons.menu_book_rounded,
                    label: '$_totalAssignedBooks total this week',
                  ),
                const Spacer(),
                if (_isProcessing)
                  const SizedBox(
                    width: LumiTokens.space4,
                    height: LumiTokens.space4,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(LumiTokens.green),
                    ),
                  ),
              ],
            ),
          ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumiTokens.space4,
              ),
              child: Text(
                _statusMessage!,
                style: LumiType.caption,
              ),
            ),
          const SizedBox(height: LumiTokens.space2),
          Expanded(
            child: _sessionBooks.isEmpty
                ? Center(
                    child: Text(
                      'No ISBN scanned yet',
                      style: LumiType.body.copyWith(color: LumiTokens.muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      LumiTokens.space4,
                      0,
                      LumiTokens.space4,
                      LumiTokens.space3,
                    ),
                    itemCount: _sessionBooks.length,
                    itemBuilder: (context, index) {
                      final book = _sessionBooks[index];
                      return _buildBookCard(book);
                    },
                  ),
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
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
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
                      ? LumiTokens.green
                      : LumiTokens.orange,
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
                  ? LumiTokens.green
                  : LumiTokens.orange,
              size: 18,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: LumiType.body.copyWith(
                    color: LumiTokens.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (book.author != null && book.author!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    book.author!,
                    style: LumiType.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('ISBN ${book.isbn}', style: LumiType.caption),
                    if (studentCount > 1) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: LumiTokens.green.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusSmall),
                        ),
                        child: Text(
                          '$studentCount students',
                          style: LumiType.caption.copyWith(
                            color: LumiTokens.green,
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

class _StudentIdentityOverlay extends StatelessWidget {
  const _StudentIdentityOverlay({
    required this.student,
    this.position,
    this.total,
  });

  final StudentModel student;
  final int? position;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final fullName = student.fullName.trim();
    final character = LumiCharacters.findById(student.displayCharacterId);
    final profileImageUrl = student.profileImageUrl?.trim() ?? '';

    Widget? visual;
    if (character != null) {
      visual = Image.asset(
        character.assetPath,
        width: 52,
        cacheWidth: decodeCacheSize(context, 52),
        height: 52,
        fit: BoxFit.contain,
      );
    }
    if (profileImageUrl.startsWith('http')) {
      visual = ClipOval(
        child: PersistentCachedImage(
          imageUrl: profileImageUrl,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          fallback: visual ?? const SizedBox.shrink(),
        ),
      );
    }

    final progressLabel = position != null && total != null
        ? 'Student $position of $total'
        : null;
    final semanticsLabel = progressLabel == null
        ? 'Scanning for $fullName'
        : 'Scanning for $fullName, $progressLabel';

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (visual != null) ...[
              visual,
              const SizedBox(width: LumiTokens.space3),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: visual == null
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    softWrap: true,
                    textAlign:
                        visual == null ? TextAlign.center : TextAlign.start,
                    style: LumiType.subhead.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 10,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  if (progressLabel != null) ...[
                    const SizedBox(height: LumiTokens.space1),
                    Text(
                      progressLabel,
                      style: LumiType.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 8,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LumiTokens.green),
          const SizedBox(width: 6),
          Text(
            label,
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scan reticle — green corner brackets that flash brighter on each accepted
/// scan (driven by [flashTick]).
class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay({required this.flashTick});

  final int flashTick;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(flashTick),
      tween: Tween<double>(begin: flashTick == 0 ? 0.0 : 1.0, end: 0.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, flash, _) {
        return SizedBox(
          width: 260,
          height: 180,
          child: CustomPaint(painter: _ReticlePainter(flash: flash)),
        );
      },
    );
  }
}

class _ScanSuccessTickOverlay extends StatelessWidget {
  const _ScanSuccessTickOverlay({required this.tick});

  final int tick;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(tick),
        tween: Tween<double>(begin: tick == 0 ? 0.0 : 1.0, end: 0.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          if (value == 0) return const SizedBox.shrink();
          final scale = 0.82 + ((1 - value) * 0.22);
          return Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: LumiTokens.green.withValues(alpha: 0.94),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: LumiTokens.green.withValues(alpha: 0.35),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 54,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.flash});

  /// 0 = resting, 1 = just scanned.
  final double flash;

  @override
  void paint(Canvas canvas, Size size) {
    const armLength = 28.0;
    final rect = Offset.zero & size;
    final color = Color.lerp(
      LumiTokens.green.withValues(alpha: 0.9),
      LumiTokens.paper,
      flash,
    )!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3 + flash * 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    _corner(canvas, paint, rect.topLeft, 1, 1, armLength);
    _corner(canvas, paint, rect.topRight, -1, 1, armLength);
    _corner(canvas, paint, rect.bottomLeft, 1, -1, armLength);
    _corner(canvas, paint, rect.bottomRight, -1, -1, armLength);

    if (flash > 0) {
      final fill = Paint()
        ..color = LumiTokens.green.withValues(alpha: 0.12 * flash);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)),
        fill,
      );
    }
  }

  void _corner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    int dx,
    int dy,
    double len,
  ) {
    final path = Path()
      ..moveTo(corner.dx + dx * len, corner.dy)
      ..lineTo(corner.dx, corner.dy)
      ..lineTo(corner.dx, corner.dy + dy * len);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => oldDelegate.flash != flash;
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
        color: LumiTokens.paper,
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
                color: LumiTokens.rule,
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
              color: LumiTokens.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_edu_rounded,
              color: LumiTokens.orange,
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$studentName has read this before',
            style: LumiType.subhead,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '"$bookTitle" may already be in $studentName\'s reading history.',
            style: LumiType.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: LumiTokens.green,
                foregroundColor: LumiTokens.paper,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                ),
                textStyle: LumiType.button,
              ),
              child: const Text('Assign anyway'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: LumiTokens.rule),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                ),
              ),
              child: Text(
                'Skip book',
                style: LumiType.button.copyWith(color: LumiTokens.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
