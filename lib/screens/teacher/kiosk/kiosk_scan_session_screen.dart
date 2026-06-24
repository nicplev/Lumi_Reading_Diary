import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/lumi/student_avatar.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/isbn_assignment_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Outcome of a single kiosk scan, used to label the session list + banner.
enum _KioskOutcome { added, renewed, reread }

class _KioskScanEntry {
  const _KioskScanEntry(this.book, this.outcome);
  final ScannedIsbnBook book;
  final _KioskOutcome outcome;
}

/// Student-facing scan screen for the in-classroom kiosk. The student scans
/// their books for the week with a Bluetooth barcode scanner (HID keyboard
/// wedge — captured here as raw key events so no on-screen keyboard appears) or
/// the device camera as a fallback. Each scan is classified (renew / already on
/// list / already read / new) and persisted into the student's weekly
/// allocation via the same [IsbnAssignmentService] the teacher scanner uses.
class KioskScanSessionScreen extends StatefulWidget {
  const KioskScanSessionScreen({
    super.key,
    required this.teacher,
    required this.classModel,
    required this.student,
  });

  final UserModel teacher;
  final ClassModel classModel;
  final StudentModel student;

  @override
  State<KioskScanSessionScreen> createState() => _KioskScanSessionScreenState();
}

class _KioskScanSessionScreenState extends State<KioskScanSessionScreen> {
  final IsbnAssignmentService _service = IsbnAssignmentService();
  final FocusNode _keyboardFocus = FocusNode();
  final StringBuffer _wedgeBuffer = StringBuffer();

  final List<_KioskScanEntry> _entries = <_KioskScanEntry>[];
  final Set<String> _sessionIsbns = <String>{};

  late final String _sessionId;
  bool _isProcessing = false;
  String? _bannerMessage;
  Color _bannerColor = LumiTokens.green;

  /// Lumi book-mascot shown after a successful scan; null shows the scanner
  /// icon. [_celebrateTick] keys the animation so it replays on each success.
  String? _celebrateAsset;
  int _celebrateTick = 0;

  String get _schoolId => widget.teacher.schoolId ?? '';

  @override
  void initState() {
    super.initState();
    _sessionId = 'kiosk_${DateTime.now().millisecondsSinceEpoch}';
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _refocus() {
    if (mounted) _keyboardFocus.requestFocus();
  }

  // ── Bluetooth keyboard-wedge capture ────────────────────────────────
  // HID scanners "type" the barcode digits followed by Enter. We buffer the
  // digits and flush on Enter. Using raw key events (not a TextField) keeps the
  // soft keyboard from popping up on the iPad.
  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _wedgeBuffer.toString();
      _wedgeBuffer.clear();
      if (code.isNotEmpty) _handleCode(code);
      return;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && RegExp(r'[0-9Xx]').hasMatch(ch)) {
      _wedgeBuffer.write(ch);
    }
  }

  Future<void> _handleCode(String rawCode) async {
    if (_isProcessing) return;
    final normalized = IsbnAssignmentService.normalizeIsbn(rawCode);
    if (normalized == null) {
      _showBanner("That doesn't look like a book barcode.", LumiTokens.orange);
      return;
    }
    if (_sessionIsbns.contains(normalized)) {
      _showBanner('Already scanned just now.', LumiTokens.blue);
      return;
    }
    if (_schoolId.isEmpty) {
      _showBanner('Cannot scan: missing school.', LumiTokens.red);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final resolution = await _service.resolveIsbn(
        rawCode: normalized,
        schoolId: _schoolId,
        teacherId: widget.teacher.id,
      );
      if (!mounted) return;
      switch (resolution) {
        case IsbnResolved(:final book):
          await _processBook(book);
        case IsbnNotFound():
          _showBanner(
            "We couldn't find that book — ask your teacher.",
            LumiTokens.orange,
          );
        case IsbnInvalid():
          _showBanner(
            "That doesn't look like a book barcode.",
            LumiTokens.orange,
          );
      }
    } catch (_) {
      if (mounted) _showBanner('Something went wrong. Try again.', LumiTokens.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
      _refocus();
    }
  }

  Future<void> _processBook(ScannedIsbnBook book) async {
    final result = await _service.classifyScan(
      schoolId: _schoolId,
      studentId: widget.student.id,
      isbn: book.isbn,
      bookId: book.bookId,
    );
    if (!mounted) return;

    switch (result.classification) {
      case ScanClassification.alreadyThisWeek:
        _showBanner('"${book.title}" is already on your list.', LumiTokens.blue);
        return;
      case ScanClassification.renew:
        await _persist(book, renewed: true);
        _addEntry(book, _KioskOutcome.renewed);
        HapticFeedback.mediumImpact();
        _showBanner('Renewed "${book.title}" for another week! 🎉',
            LumiTokens.green);
        return;
      case ScanClassification.alreadyRead:
        final readAgain = await _showAlreadyReadSheet(book);
        if (!mounted || !readAgain) {
          _refocus();
          return;
        }
        await _persist(book);
        _addEntry(book, _KioskOutcome.reread);
        HapticFeedback.mediumImpact();
        _showBanner('Reading "${book.title}" again — nice!', LumiTokens.green);
        return;
      case ScanClassification.newBook:
        await _persist(book);
        _addEntry(book, _KioskOutcome.added);
        HapticFeedback.mediumImpact();
        _showBanner('Added "${book.title}"!', LumiTokens.green);
        return;
    }
  }

  Future<void> _persist(ScannedIsbnBook book, {bool renewed = false}) async {
    await _service.assignResolvedBooks(
      schoolId: _schoolId,
      classId: widget.classModel.id,
      studentId: widget.student.id,
      teacherId: widget.teacher.id,
      books: [book],
      targetMinutes: widget.classModel.defaultMinutesTarget,
      sessionId: _sessionId,
      renewedIsbns: renewed ? {book.isbn} : const <String>{},
    );
  }

  void _addEntry(ScannedIsbnBook book, _KioskOutcome outcome) {
    _sessionIsbns.add(book.isbn);
    setState(() {
      _entries.insert(0, _KioskScanEntry(book, outcome));
      _celebrateAsset = switch (outcome) {
        _KioskOutcome.added => 'assets/lumi/Lumi_Books_Green.png',
        _KioskOutcome.renewed => 'assets/lumi/Lumi_Books_LBlue.png',
        _KioskOutcome.reread => 'assets/lumi/Lumi_Books_Orange.png',
      };
      _celebrateTick++;
    });
  }

  void _showBanner(String message, Color color) {
    setState(() {
      _bannerMessage = message;
      _bannerColor = color;
    });
  }

  Future<bool> _showAlreadyReadSheet(ScannedIsbnBook book) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AlreadyReadSheet(
        studentName: widget.student.firstName,
        bookTitle: book.title,
      ),
    );
    return result ?? false;
  }

  Future<void> _scanWithCamera() async {
    final controller = MobileScannerController();
    String? captured;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: ColoredBox(
              color: LumiTokens.ink,
              child: Stack(
                children: [
                  MobileScanner(
                    controller: controller,
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final code = IsbnAssignmentService.normalizeIsbn(
                            barcode.rawValue);
                        if (code != null) {
                          captured = code;
                          Navigator.of(ctx).pop();
                          break;
                        }
                      }
                    },
                    errorBuilder: (context, error) => _CameraUnavailable(
                      onClose: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Material(
                      color: LumiTokens.paper,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded,
                            color: LumiTokens.ink),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 32,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: LumiTokens.ink.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                        ),
                        child: Text(
                          'Point at a book barcode',
                          style: LumiType.caption.copyWith(color: LumiTokens.paper),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    await controller.dispose();
    if (captured != null) {
      await _handleCode(captured!);
    } else {
      _refocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _refocus,
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: LumiTokens.cream,
          appBar: AppBar(
            backgroundColor: LumiTokens.cream,
            elevation: 0,
            titleSpacing: 0,
            title: Row(
              children: [
                StudentAvatar.fromStudent(widget.student, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Hi ${widget.student.firstName}! Scan your books',
                    style: LumiType.subhead,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Side-by-side on a landscape iPad; stacked on a phone/portrait.
                final wide = constraints.maxWidth >= 720;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            if (_bannerMessage != null) _buildBanner(),
                            Expanded(
                              child: Center(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: _buildScanPanel(),
                                ),
                              ),
                            ),
                            _buildDoneBar(),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, color: LumiTokens.rule),
                      Expanded(flex: 6, child: _buildEntriesPane()),
                    ],
                  );
                }
                return Column(
                  children: [
                    if (_bannerMessage != null) _buildBanner(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: _buildScanPanel(),
                    ),
                    Expanded(child: _buildEntriesPane()),
                    _buildDoneBar(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The celebratory Lumi book mascot (after a scan) or the scanner icon.
  Widget _buildMascot() {
    if (_isProcessing) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(color: LumiTokens.green),
          ),
        ),
      );
    }
    if (_celebrateAsset == null) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: LumiTokens.tintGreen.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.qr_code_scanner_rounded,
            size: 56, color: LumiTokens.green),
      );
    }
    return Image.asset(
      _celebrateAsset!,
      height: 120,
      key: ValueKey(_celebrateTick),
    )
        .animate(key: ValueKey(_celebrateTick))
        .scale(
          begin: const Offset(0.6, 0.6),
          end: const Offset(1, 1),
          duration: 320.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 200.ms);
  }

  /// The central scan call-to-action card (mascot + heading + camera button).
  Widget _buildScanPanel() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
          boxShadow: LumiTokens.shadowCard,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMascot(),
            const SizedBox(height: 20),
            Text(
              _isProcessing ? 'Looking up your book…' : 'Scan a book barcode',
              style: LumiType.heading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Point the barcode scanner at your book — or tap below to use '
              'the camera.',
              style: LumiType.body.copyWith(color: LumiTokens.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _isProcessing ? null : _scanWithCamera,
              icon: const Icon(Icons.photo_camera_rounded,
                  color: LumiTokens.green),
              label: Text(
                'Use camera',
                style: LumiType.button.copyWith(color: LumiTokens.green),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: LumiTokens.green, width: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _bannerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: _bannerColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        _bannerMessage!,
        style: LumiType.body.copyWith(
          color: _bannerColor,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    )
        .animate(key: ValueKey(_bannerMessage))
        .fadeIn(duration: 200.ms)
        .slideY(begin: -0.15, end: 0, curve: Curves.easeOut);
  }

  Widget _buildEntriesPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            _entries.isEmpty
                ? 'Scanned this session'
                : 'Scanned this session • ${_entries.length}',
            style: LumiType.sectionLabel,
          ),
        ),
        Expanded(child: _buildEntries()),
      ],
    );
  }

  Widget _buildEntries() {
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded,
                size: 48, color: LumiTokens.rule),
            const SizedBox(height: 12),
            Text(
              'Your scanned books\nwill appear here.',
              style: LumiType.body.copyWith(color: LumiTokens.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final tile = _buildEntryTile(_entries[index]);
        // Animate only the newest (top) tile so the list doesn't re-animate
        // wholesale on every scan.
        if (index == 0) {
          return tile
              .animate(key: ValueKey(_celebrateTick))
              .fadeIn(duration: 220.ms)
              .slideX(begin: 0.12, end: 0, curve: Curves.easeOut);
        }
        return tile;
      },
    );
  }

  Widget _buildEntryTile(_KioskScanEntry entry) {
    final (label, color) = switch (entry.outcome) {
      _KioskOutcome.added => ('Added', LumiTokens.green),
      _KioskOutcome.renewed => ('Renewed', LumiTokens.blue),
      _KioskOutcome.reread => ('Reading again', LumiTokens.orange),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        children: [
          _buildCover(entry.book.coverImageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  IsbnAssignmentService.sanitizeDisplayTitle(entry.book.title),
                  style: LumiType.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.book.author != null)
                  Text(
                    entry.book.author!,
                    style: LumiType.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: LumiType.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(String? url) {
    const w = 40.0;
    const h = 56.0;
    if (url == null || url.isEmpty) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: LumiTokens.cream,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.menu_book_rounded,
            size: 20, color: LumiTokens.muted),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: w,
          height: h,
          color: LumiTokens.cream,
          child: const Icon(Icons.menu_book_rounded,
              size: 20, color: LumiTokens.muted),
        ),
      ),
    );
  }

  Widget _buildDoneBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: () {
            CommonWidgets.showSuccessSnackbar(
              context,
              '${widget.student.firstName} scanned ${_entries.length} book(s).',
            );
            Navigator.of(context).pop(_entries.length);
          },
          style: FilledButton.styleFrom(
            backgroundColor: LumiTokens.green,
            foregroundColor: LumiTokens.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            ),
          ),
          child: Text(
            _entries.isEmpty ? 'Done' : "I'm done!",
            style: LumiType.button,
          ),
        ),
      ),
    );
  }
}

/// Lumi-styled message shown inside the camera sheet when no camera is
/// available (e.g. a device with only a Bluetooth scanner, or the simulator).
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LumiTokens.ink,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded,
                  size: 48, color: LumiTokens.paper),
              const SizedBox(height: 16),
              Text(
                'No camera on this device',
                style: LumiType.subhead.copyWith(color: LumiTokens.paper),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Use the Bluetooth barcode scanner instead — it works without '
                'the camera.',
                style: LumiType.body.copyWith(
                  color: LumiTokens.paper.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onClose,
                style: FilledButton.styleFrom(
                  backgroundColor: LumiTokens.green,
                  foregroundColor: LumiTokens.paper,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                  ),
                ),
                child: Text('Got it', style: LumiType.button),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Friendly "you've read this before" notice. Re-reading is allowed — the
/// student chooses to read it again or pick another book.
class _AlreadyReadSheet extends StatelessWidget {
  const _AlreadyReadSheet({
    required this.studentName,
    required this.bookTitle,
  });

  final String studentName;
  final String bookTitle;

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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: LumiTokens.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_edu_rounded,
                color: LumiTokens.orange, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            "You've read this one before!",
            style: LumiType.subhead,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '"$bookTitle" is already in your reading history. Want to read it again?',
            style: LumiType.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: LumiTokens.green,
                foregroundColor: LumiTokens.paper,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
              ),
              child: Text('Read it again', style: LumiType.button),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: LumiTokens.rule),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
              ),
              child: Text(
                'Pick another book',
                style: LumiType.button.copyWith(color: LumiTokens.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
