import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/utils/image_decode.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/student_avatar.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/bluetooth_settings_service.dart';
import '../../../services/hid_scanner_connection_service.dart';
import '../../../services/isbn_assignment_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

const Size _kKioskReticleSize = Size(260, 160);

@visibleForTesting
Rect kioskCameraScanWindowFor(Size surface) => Rect.fromCenter(
      center: Offset(surface.width / 2, surface.height / 2),
      width: _kKioskReticleSize.width,
      height: _kKioskReticleSize.height,
    );

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
    @visibleForTesting this.isbnAssignmentService,
    @visibleForTesting this.hidScannerConnectionService,
    @visibleForTesting this.bluetoothSettingsController,
  });

  final UserModel teacher;
  final ClassModel classModel;
  final StudentModel student;
  final IsbnAssignmentService? isbnAssignmentService;
  final HidScannerConnectionService? hidScannerConnectionService;
  final BluetoothSettingsController? bluetoothSettingsController;

  @override
  State<KioskScanSessionScreen> createState() => _KioskScanSessionScreenState();
}

class _KioskScanSessionScreenState extends State<KioskScanSessionScreen> {
  late final IsbnAssignmentService _service;
  late final HidScannerConnectionService _hidScannerConnectionService;
  late final BluetoothSettingsController _bluetoothSettingsController;
  final FocusNode _keyboardFocus = FocusNode();
  final StringBuffer _wedgeBuffer = StringBuffer();

  final List<_KioskScanEntry> _entries = <_KioskScanEntry>[];
  final Set<String> _sessionIsbns = <String>{};
  final Queue<String> _pendingCodes = Queue<String>();

  // Includes the active lookup as well as queued codes. Keeping the active
  // code here closes the small window where a rapid duplicate can arrive after
  // dequeue but before the resolved book reaches [_sessionIsbns].
  final Set<String> _pendingSet = <String>{};

  late final String _sessionId;
  bool _isProcessing = false;
  bool _isDraining = false;
  bool? _scannerConnected;
  bool _receivedScannerConnectionEvent = false;
  StreamSubscription<bool>? _scannerConnectionSub;
  String? _bannerMessage;
  Color _bannerColor = LumiTokens.green;

  /// Lumi book-mascot shown after a successful scan; null shows the scanner
  /// icon. [_celebrateTick] keys the animation so it replays on each success.
  String? _celebrateAsset;
  int _celebrateTick = 0;

  // Kids walk away the moment their books are scanned, so without this the next
  // child in line would scan onto the previous child's session. After a spell
  // of no activity we return to the roster; queued work keeps the screen open
  // until each accepted scan has finished saving.
  static const _idleTimeout = Duration(seconds: 30);
  Timer? _idleTimer;

  String get _schoolId => widget.teacher.schoolId ?? '';
  bool get _hasPendingWork => _isProcessing || _pendingCodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _service = widget.isbnAssignmentService ?? IsbnAssignmentService();
    _hidScannerConnectionService =
        widget.hidScannerConnectionService ?? HidScannerConnectionService();
    _bluetoothSettingsController =
        widget.bluetoothSettingsController ?? BluetoothSettingsService();
    _sessionId = 'kiosk_${DateTime.now().millisecondsSinceEpoch}';
    _scannerConnectionSub =
        _hidScannerConnectionService.connectionChanges().listen((connected) {
      _receivedScannerConnectionEvent = true;
      if (mounted) setState(() => _scannerConnected = connected);
    });
    unawaited(_seedScannerConnectionState());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
    _resetIdleTimer();
  }

  Future<void> _seedScannerConnectionState() async {
    final connected = await _hidScannerConnectionService.isConnected();
    // A streamed connect/disconnect event is newer than the one-shot result.
    if (!mounted || _receivedScannerConnectionEvent) return;
    setState(() => _scannerConnected = connected);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    unawaited(_scannerConnectionSub?.cancel());
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _onIdle);
  }

  void _onIdle() {
    if (!mounted) return;
    // Don't pop out from under a modal (camera / already-read sheet) or while a
    // lookup is mid-flight — reschedule instead.
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!isCurrent ||
        _isProcessing ||
        _isDraining ||
        _pendingCodes.isNotEmpty) {
      _resetIdleTimer();
      return;
    }
    Navigator.of(context).pop(_entries.length);
  }

  /// Confirmation feedback on a successful scan — a light system click plus a
  /// haptic tap. (Swap the click for a bundled chime via just_audio later if a
  /// richer sound is wanted.)
  void _playScanFeedback() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
  }

  void _refocus() {
    if (mounted) _keyboardFocus.requestFocus();
    _resetIdleTimer();
  }

  // ── Bluetooth keyboard-wedge capture ────────────────────────────────
  // HID scanners "type" the barcode digits followed by Enter. We buffer the
  // digits and flush on Enter. Using raw key events (not a TextField) keeps the
  // soft keyboard from popping up on the iPad.
  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    _resetIdleTimer();
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

  void _handleCode(String rawCode) {
    _resetIdleTimer();
    final normalized = IsbnAssignmentService.normalizeIsbn(rawCode);
    if (normalized == null) {
      _showBanner("That doesn't look like a book barcode.", LumiTokens.orange);
      return;
    }
    if (_sessionIsbns.contains(normalized) ||
        _pendingSet.contains(normalized)) {
      _showBanner('Already scanned just now.', LumiTokens.blue);
      return;
    }
    if (_schoolId.isEmpty) {
      _showBanner('Cannot scan: missing school.', LumiTokens.red);
      return;
    }

    setState(() {
      _pendingCodes.add(normalized);
      _pendingSet.add(normalized);
    });
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      while (_pendingCodes.isNotEmpty && mounted) {
        final code = _pendingCodes.removeFirst();
        if (_sessionIsbns.contains(code)) {
          _pendingSet.remove(code);
          continue;
        }

        setState(() => _isProcessing = true);
        try {
          final resolution = await _service.resolveIsbn(
            rawCode: code,
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
            case IsbnLookupUnavailable():
              _showBanner(
                "You're offline — try that book again once you're connected.",
                LumiTokens.orange,
              );
            case IsbnInvalid():
              _showBanner(
                "That doesn't look like a book barcode.",
                LumiTokens.orange,
              );
          }
        } catch (_) {
          if (mounted) {
            _showBanner('Something went wrong. Try again.', LumiTokens.red);
          }
        } finally {
          _pendingSet.remove(code);
          if (mounted) setState(() => _isProcessing = false);
        }
      }
    } finally {
      _isDraining = false;
      if (mounted) _refocus();
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
        _showBanner(
          '"${book.title}" is already on your list.',
          LumiTokens.blue,
        );
        return;
      case ScanClassification.renew:
        final queued = await _persist(book, renewed: true);
        _addEntry(book, _KioskOutcome.renewed);
        _showBanner(
          queued
              ? 'Saved "${book.title}" — it\'ll renew once you\'re back online.'
              : 'Renewed "${book.title}" for another week! 🎉',
          queued ? LumiTokens.blue : LumiTokens.green,
        );
        return;
      case ScanClassification.alreadyRead:
        final readAgain = await _showAlreadyReadSheet(book);
        if (!mounted || !readAgain) {
          _refocus();
          return;
        }
        final rereadQueued = await _persist(book);
        _addEntry(book, _KioskOutcome.reread);
        _showBanner(
          rereadQueued
              ? 'Saved "${book.title}" — it\'ll sync when you\'re back online.'
              : 'Reading "${book.title}" again — nice!',
          rereadQueued ? LumiTokens.blue : LumiTokens.green,
        );
        return;
      case ScanClassification.newBook:
        final addQueued = await _persist(book);
        _addEntry(book, _KioskOutcome.added);
        _showBanner(
          addQueued
              ? 'Saved "${book.title}" — it\'ll add once you\'re back online.'
              : 'Added "${book.title}"!',
          addQueued ? LumiTokens.blue : LumiTokens.green,
        );
        return;
    }
  }

  /// Returns true when the write was queued offline (will sync later) rather
  /// than confirmed online.
  Future<bool> _persist(ScannedIsbnBook book, {bool renewed = false}) async {
    final result = await _service.assignResolvedBooks(
      schoolId: _schoolId,
      classId: widget.classModel.id,
      studentId: widget.student.id,
      teacherId: widget.teacher.id,
      books: [book],
      targetMinutes: widget.classModel.defaultMinutesTarget,
      sessionId: _sessionId,
      renewedIsbns: renewed ? {book.isbn} : const <String>{},
    );
    return result.queuedOffline;
  }

  void _addEntry(ScannedIsbnBook book, _KioskOutcome outcome) {
    _sessionIsbns.add(book.isbn);
    _playScanFeedback();
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
    final capturedCodes = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KioskCameraScannerSheet(
        ignoredIsbns: _sessionIsbns,
        onCloseEmpty: () => Navigator.of(ctx).pop(),
      ),
    );
    if (capturedCodes != null && capturedCodes.isNotEmpty) {
      for (final code in capturedCodes) {
        if (!mounted) return;
        _handleCode(code);
      }
    } else {
      _refocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<int>(
      canPop: !_hasPendingWork,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasPendingWork) {
          CommonWidgets.showInfoSnackbar(
            context,
            'Please wait while your scanned books finish saving.',
          );
        }
      },
      child: _buildKioskScaffold(),
    );
  }

  Widget _buildKioskScaffold() {
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            if (_bannerMessage != null) _buildBanner(),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                              child: _buildScanPanel(),
                            ),
                            _buildEntriesPane(shrinkWrap: true),
                          ],
                        ),
                      ),
                    ),
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
      cacheHeight: decodeCacheSize(context, 120),
      key: ValueKey(_celebrateTick),
    )
        .animate(key: ValueKey(_celebrateTick))
        .scale(
          begin: const Offset(0.6, 0.6),
          end: const Offset(1, 1),
          duration: 320.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 200.ms)
        // A little wiggle + shimmer for personality on each scan.
        .then()
        .shake(hz: 4, rotation: 0.12, duration: 360.ms)
        .shimmer(
            duration: 700.ms, color: LumiTokens.paper.withValues(alpha: 0.6));
  }

  /// Opens the operating system's Bluetooth pairing route. Android can open
  /// the Bluetooth device list directly. iOS does not expose a public deep
  /// link to that pane, so explain the final tap before opening system Settings.
  Future<void> _openBluetoothSettings() async {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS) {
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => const _BluetoothSettingsDialog(),
      );
      if (shouldOpen != true || !mounted) return;
    }

    final destination =
        await _bluetoothSettingsController.openBluetoothSettings();
    if (!mounted) return;
    if (destination == BluetoothSettingsDestination.unavailable) {
      CommonWidgets.showInfoSnackbar(
        context,
        "Open your device's Settings app → Bluetooth to connect your scanner.",
      );
    }
  }

  /// Shared card chrome for the left-hand scan panel.
  Widget _panelCard(List<Widget> children) {
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
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _cameraButton() {
    return OutlinedButton.icon(
      onPressed: _isProcessing ? null : _scanWithCamera,
      icon: const Icon(Icons.photo_camera_rounded, color: LumiTokens.green),
      label: Text(
        'Use camera',
        style: LumiType.button.copyWith(color: LumiTokens.green),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: LumiTokens.green, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        ),
      ),
    );
  }

  Widget _buildScanPanel() {
    final heuristicShow =
        _entries.isEmpty && _celebrateAsset == null && !_isProcessing;
    final showConnectHelp = switch (_scannerConnected) {
      true => false,
      false => !_isProcessing && _pendingCodes.isEmpty,
      null => heuristicShow,
    };
    return showConnectHelp
        ? _buildConnectScannerPanel()
        : _buildActiveScanPanel();
  }

  /// Empty state shown when no scanner has fired yet — explains pairing a
  /// Bluetooth barcode scanner and offers a jump to Bluetooth settings.
  Widget _buildConnectScannerPanel() {
    return _panelCard([
      Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: LumiTokens.tintBlue.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.bluetooth_searching_rounded,
            size: 56, color: LumiTokens.indigo),
      ),
      const SizedBox(height: 20),
      Text(
        'Connect your scanner',
        style: LumiType.heading,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        "Pair your barcode scanner in your device's Bluetooth settings, then point "
        "it at a book's barcode to add it. Already paired? Just start scanning.",
        style: LumiType.body.copyWith(color: LumiTokens.muted),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: _openBluetoothSettings,
          icon: const Icon(Icons.settings_bluetooth_rounded),
          label: Text('Open Bluetooth settings', style: LumiType.button),
          style: FilledButton.styleFrom(
            backgroundColor: LumiTokens.green,
            foregroundColor: LumiTokens.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _cameraButton(),
    ]);
  }

  /// Active scan prompt (mascot + camera button) shown once scanning is under
  /// way or a book has been added.
  Widget _buildActiveScanPanel() {
    return _panelCard([
      _buildMascot(),
      const SizedBox(height: 20),
      Text(
        _isProcessing ? 'Looking up your book…' : 'Scan book barcodes',
        style: LumiType.heading,
        textAlign: TextAlign.center,
      ),
      if (_isProcessing && _pendingCodes.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          '${_pendingCodes.length} more waiting',
          style: LumiType.caption.copyWith(color: LumiTokens.muted),
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'Point the barcode scanner at each book — or use the camera to grab '
        'several barcodes at once.',
        style: LumiType.body.copyWith(color: LumiTokens.muted),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      _cameraButton(),
    ]);
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

  Widget _buildEntriesPane({bool shrinkWrap = false}) {
    return Column(
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
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
        if (shrinkWrap)
          _buildEntries(shrinkWrap: true)
        else
          Expanded(child: _buildEntries()),
      ],
    );
  }

  Widget _buildEntries({bool shrinkWrap = false}) {
    if (_entries.isEmpty) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, size: 48, color: LumiTokens.rule),
              const SizedBox(height: 12),
              Text(
                'Your scanned books\nwill appear here.',
                style: LumiType.body.copyWith(color: LumiTokens.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
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
          onPressed: _hasPendingWork
              ? null
              : () {
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
            _hasPendingWork
                ? 'Saving books…'
                : (_entries.isEmpty ? 'Done' : "I'm done!"),
            style: LumiType.button,
          ),
        ),
      ),
    );
  }
}

class _KioskCameraScannerSheet extends StatefulWidget {
  const _KioskCameraScannerSheet({
    required this.ignoredIsbns,
    required this.onCloseEmpty,
  });

  final Set<String> ignoredIsbns;
  final VoidCallback onCloseEmpty;

  @override
  State<_KioskCameraScannerSheet> createState() =>
      _KioskCameraScannerSheetState();
}

class _KioskCameraScannerSheetState extends State<_KioskCameraScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  final Set<String> _capturedIsbns = <String>{};

  bool _sawKnownCode = false;
  int _flashTick = 0;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    var addedAny = false;
    var sawKnown = false;

    for (final barcode in capture.barcodes) {
      final code = IsbnAssignmentService.normalizeIsbn(barcode.rawValue);
      if (code == null) continue;

      if (widget.ignoredIsbns.contains(code) || _capturedIsbns.contains(code)) {
        sawKnown = true;
        continue;
      }

      _capturedIsbns.add(code);
      addedAny = true;
    }

    if (!mounted) return;
    if (addedAny) {
      HapticFeedback.mediumImpact();
      setState(() {
        _sawKnownCode = false;
        _flashTick++;
      });
      return;
    }
    if (sawKnown && !_sawKnownCode) {
      setState(() => _sawKnownCode = true);
    }
  }

  void _finish() {
    Navigator.of(context).pop(List<String>.unmodifiable(_capturedIsbns));
  }

  @override
  Widget build(BuildContext context) {
    final foundCount = _capturedIsbns.length;
    final statusText = foundCount == 0
        ? (_sawKnownCode
            ? 'Already scanned this session'
            : 'No books found yet')
        : '$foundCount ${foundCount == 1 ? 'book' : 'books'} found';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.74,
        child: ColoredBox(
          color: LumiTokens.ink,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scanWindow = kioskCameraScanWindowFor(constraints.biggest);
              return Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    scanWindow: scanWindow,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => _CameraUnavailable(
                      onClose: widget.onCloseEmpty,
                    ),
                  ),
                  Center(child: _KioskCameraReticle(flashTick: _flashTick)),
                  Center(
                    child: _KioskScanSuccessTickOverlay(tick: _flashTick),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Material(
                      color: LumiTokens.paper,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: LumiTokens.ink,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: LumiTokens.paper.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: LumiTokens.tintGreen,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: LumiTokens.green,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        statusText,
                                        style: LumiType.subhead,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Place each book barcode inside the green box, then tap Done.',
                                        style: LumiType.caption.copyWith(
                                          color: LumiTokens.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: foundCount == 0 ? null : _finish,
                              icon: const Icon(Icons.check_rounded),
                              label: Text(
                                foundCount == 0
                                    ? 'Find book barcodes'
                                    : 'Done with $foundCount',
                                style: LumiType.button,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: LumiTokens.green,
                                foregroundColor: LumiTokens.paper,
                                disabledBackgroundColor: LumiTokens.rule,
                                disabledForegroundColor: LumiTokens.muted,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusPill,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _KioskCameraReticle extends StatelessWidget {
  const _KioskCameraReticle({required this.flashTick});

  final int flashTick;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: ValueKey(flashTick),
      duration: 160.ms,
      width: _kKioskReticleSize.width,
      height: _kKioskReticleSize.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: LumiTokens.green,
          width: flashTick == 0 ? 3 : 5,
        ),
      ),
    );
  }
}

class _KioskScanSuccessTickOverlay extends StatelessWidget {
  const _KioskScanSuccessTickOverlay({required this.tick});

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

/// iOS-only explainer shown before handing off to system Settings. Styled to
/// the Lumi surface language (paper card, XL radius, Lumi type + buttons)
/// rather than the platform [AlertDialog] the kiosk used previously.
class _BluetoothSettingsDialog extends StatelessWidget {
  const _BluetoothSettingsDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(LumiTokens.space5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(LumiTokens.space5),
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            border: Border.all(color: LumiTokens.rule),
            boxShadow: LumiTokens.shadowFloat,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: LumiTokens.tintBlue,
                  borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                ),
                child: const Icon(
                  Icons.bluetooth_searching_rounded,
                  color: LumiTokens.indigo,
                  size: 28,
                ),
              ),
              const SizedBox(height: LumiTokens.space4),
              Text(
                'Open Bluetooth on this device',
                style: LumiType.subhead,
              ),
              const SizedBox(height: LumiTokens.space2),
              Text(
                'Apple does not let Lumi jump reliably to the Bluetooth device '
                'list. Settings will open next — tap Bluetooth, then select '
                'your scanner to connect or disconnect it.',
                style: LumiType.body.copyWith(color: LumiTokens.muted),
              ),
              const SizedBox(height: LumiTokens.space5),
              LumiPrimaryButton(
                onPressed: () => Navigator.of(context).pop(true),
                text: 'Open Settings',
                icon: Icons.settings_rounded,
                isFullWidth: true,
              ),
              const SizedBox(height: LumiTokens.space2),
              LumiSecondaryButton(
                onPressed: () => Navigator.of(context).pop(false),
                text: 'Not now',
                isFullWidth: true,
                // Muted rather than the brand red: this is a dismissal, and
                // the accent belongs on the action that moves the task on.
                color: LumiTokens.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
