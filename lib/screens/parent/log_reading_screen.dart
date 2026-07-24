import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../theme/lumi_tokens.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/school_time.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/blob_selector.dart';
import '../../core/widgets/lumi/comment_chips.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/allocation_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/comprehension_recording_settings.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/school_model.dart';
import '../../data/models/parent_comment_settings.dart';
import '../../services/firebase_service.dart';
import '../../services/guardian_quick_log_prefs_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/offline_service.dart';
import '../../services/platform_config_service.dart';
import '../../services/logging_engagement_service.dart';
import '../../services/reading_log_service.dart';
import 'widgets/comprehension_recording_step.dart';

class LogReadingScreen extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;
  final List<AllocationModel> allocations;

  const LogReadingScreen({
    super.key,
    required this.student,
    required this.parent,
    this.allocations = const [],
  });

  @override
  State<LogReadingScreen> createState() => _LogReadingScreenState();
}

class _LogReadingScreenState extends State<LogReadingScreen>
    with WidgetsBindingObserver {
  final FirebaseService _firebaseService = FirebaseService.instance;
  final PageController _pageController = PageController();
  final TextEditingController _bookTitleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  int _currentStep = 0;

  // Pre-generated id reused as the storage filename for the comprehension
  // audio, so the path is stable across wizard, upload, and teacher player.
  final String _logId = ReadingLogService.generateLogId();

  // Parent comment settings (loaded from school doc)
  ParentCommentSettings _commentSettings = ParentCommentSettings.defaults();

  // Comprehension recording settings (school toggle + per-class question)
  ComprehensionRecordingSettings _comprehensionSettings =
      ComprehensionRecordingSettings.defaults();
  String _comprehensionQuestion = ClassModel.defaultComprehensionQuestion;
  ComprehensionRecordingResult? _comprehensionRecording;
  bool _demoAudioPreviewOnly = false;

  bool get _commentsEnabled => _commentSettings.enabled;
  bool get _comprehensionEnabled => _comprehensionSettings.enabled;

  // Tonight's reading (book + duration + how it felt) → [optional detail] →
  // Review. The middle "Add detail" page (voice reflection + comment tags +
  // notes) only appears when the school enables one of those features, so the
  // flow is three steps in the common case and two when there's nothing
  // optional to collect — never an empty page.
  bool get _hasOptionalDetail => _commentsEnabled || _comprehensionEnabled;
  int get _totalSteps => _hasOptionalDetail ? 3 : 2;

  // Step 1: Book selection
  final List<String> _assignedBookTitles = [];
  final Set<String> _selectedBookTitles = {};
  final List<String> _customBookTitles = [];
  int _selectedMinutes = 20;

  // A large class library is collapsed to the first few rows so it doesn't
  // push Reading time + feeling below the fold; expanded on demand.
  bool _showAllAssignedBooks = false;
  static const int _kCollapsedBookCount = 4;

  // When the child has assigned books, the manual "add a book" entry is a
  // secondary path — collapsed to a slim row until tapped.
  bool _showAddBookField = false;

  // Step 2: Child feeling
  ReadingFeeling? _selectedFeeling;

  // Step 3: Parent comment (skipped when comments disabled)
  List<String> _selectedComments = [];

  // Step 4 (or 3): Confirmation
  bool _isLoading = false;
  String? _errorMessage;

  // ---- Submit progress -----------------------------------------------------
  // A log with a comprehension recording can sit on the save button for a
  // while on a slow connection, and an indeterminate spinner gives the parent
  // no idea whether it is nearly done or stuck. Only the Storage upload
  // reports real bytes; the confirm callable that follows decodes and
  // transcodes server-side and reports nothing. So the bar reserves its last
  // stretch for that leg and creeps through it, rather than sitting at 100%
  // looking frozen — or claiming done before it is.
  static const double _kSavingEnd = 0.10;
  static const double _kUploadEnd = 0.85;
  static const double _kCreepCeiling = 0.97;

  _SubmitPhase _phase = _SubmitPhase.idle;
  double _progress = 0;
  Timer? _creepTimer;

  /// Only true when there are bytes to upload. A log without a recording
  /// finishes in well under a second, where a bar would just flash — those
  /// keep the plain spinner.
  bool _useProgressBar = false;

  // Soft, non-blocking notice when another guardian already logged today.
  String? _alreadyLoggedNotice;

  // ---- Occurrence day (D1: Yesterday backdating) --------------------------
  // The detailed flow may record Today or Yesterday — nothing further back
  // (accountability decision). Gated on platformConfig/parentBackdating so
  // it can be turned off without an app release. All day math is in the
  // SCHOOL's timezone.
  bool _backdatingEnabled = false;
  bool _isYesterday = false;
  String _schoolTimezone = SchoolTime.defaultTimezone;

  String get _occurredOn {
    final today = SchoolTime.todayFor(_schoolTimezone);
    return _isYesterday ? SchoolTime.shiftDays(today, -1) : today;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedMinutes = widget.allocations.isNotEmpty
        ? widget.allocations.first.targetMinutes
        : 20;

    final seen = <String>{};
    for (final allocation in widget.allocations) {
      for (final item
          in allocation.effectiveAssignmentItemsForStudent(widget.student.id)) {
        final title = item.title.trim();
        if (title.isNotEmpty && seen.add(title.toLowerCase())) {
          _assignedBookTitles
              .add(IsbnAssignmentService.sanitizeDisplayTitle(title));
        }
      }
    }

    // Rec 5a: restore an interrupted draft (validated against current books).
    _restoreDraft();

    _loadCommentSettings();
    _checkAlreadyLoggedToday();
    PlatformConfigService().isParentBackdatingEnabled().then((enabled) {
      if (mounted && enabled != _backdatingEnabled) {
        setState(() => _backdatingEnabled = enabled);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Persist a draft when the app is backgrounded mid-wizard so an
    // interruption (call, notification, app switch) doesn't lose progress.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_hasDraftContent && !_isLoading) {
        OfflineService.instance.saveLogDraft(widget.student.id, _buildDraft());
      }
    }
  }

  /// True when the wizard holds enough input to be worth keeping as a draft.
  bool get _hasDraftContent =>
      _selectedBookTitles.isNotEmpty ||
      _customBookTitles.isNotEmpty ||
      _selectedFeeling != null ||
      _selectedComments.isNotEmpty ||
      _notesController.text.trim().isNotEmpty;

  Map<String, dynamic> _buildDraft() => {
        'currentStep': _currentStep,
        'selectedMinutes': _selectedMinutes,
        'selectedBookTitles': _selectedBookTitles.toList(),
        'customBookTitles': List<String>.from(_customBookTitles),
        'selectedFeeling': _selectedFeeling?.name,
        'selectedComments': List<String>.from(_selectedComments),
        'notes': _notesController.text,
        'comprehensionAudioPath': _comprehensionRecording?.localPath,
        'comprehensionAudioDurationSec': _comprehensionRecording?.durationSec,
        'savedAt': DateTime.now().toIso8601String(),
      };

  /// Restores a previously-saved draft for this student, if one exists.
  /// Restored assigned-book titles are re-validated against the current
  /// allocations so stale assignments are silently dropped.
  void _restoreDraft() {
    final draft = OfflineService.instance.getLogDraft(widget.student.id);
    if (draft == null) return;

    final validAssigned = _assignedBookTitles.toSet();
    _selectedBookTitles.addAll(
      (draft['selectedBookTitles'] as List?)
              ?.whereType<String>()
              .where(validAssigned.contains) ??
          const <String>[],
    );
    _customBookTitles.addAll(
      (draft['customBookTitles'] as List?)?.whereType<String>() ??
          const <String>[],
    );
    _selectedMinutes = draft['selectedMinutes'] as int? ?? _selectedMinutes;

    final feelingName = draft['selectedFeeling'] as String?;
    if (feelingName != null) {
      for (final feeling in ReadingFeeling.values) {
        if (feeling.name == feelingName) {
          _selectedFeeling = feeling;
          break;
        }
      }
    }
    _selectedComments =
        (draft['selectedComments'] as List?)?.whereType<String>().toList() ??
            [];
    _notesController.text = draft['notes'] as String? ?? '';

    final draftAudioPath = draft['comprehensionAudioPath'] as String?;
    final draftAudioDuration = draft['comprehensionAudioDurationSec'] as int?;
    if (draftAudioPath != null && draftAudioDuration != null) {
      _comprehensionRecording = ComprehensionRecordingResult(
        localPath: draftAudioPath,
        durationSec: draftAudioDuration,
      );
    }

    final step = draft['currentStep'] as int? ?? 0;
    _currentStep = step.clamp(0, _totalSteps - 1);
    if (_currentStep > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentStep);
        }
      });
    }
  }

  /// Close handler: when the wizard holds unsaved input, ask whether to keep
  /// the draft for later or discard it.
  Future<void> _handleClose() async {
    if (!_hasDraftContent) {
      context.pop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Discard draft?', style: LumiTextStyles.h3()),
        content: Text(
          'Keep your progress to finish logging later, or discard it.',
          style: LumiTextStyles.bodyMedium(color: LumiTokens.muted),
        ),
        actions: [
          LumiDialogAction(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            label: 'Keep draft',
            variant: LumiDialogActionVariant.cancel,
          ),
          LumiDialogAction(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            label: 'Discard',
            variant: LumiDialogActionVariant.destructive,
          ),
        ],
      ),
    );
    if (action == null) return; // Dismissed — stay on the wizard.
    if (action == 'keep') {
      await OfflineService.instance
          .saveLogDraft(widget.student.id, _buildDraft());
    } else {
      await OfflineService.instance.clearLogDraft(widget.student.id);
    }
    if (mounted) context.pop();
  }

  /// Soft check: did another guardian already log reading for this student
  /// today? Surfaces a dismissible, non-blocking notice — duplicate logs are
  /// allowed and stats aggregation sums them correctly.
  Future<void> _checkAlreadyLoggedToday() async {
    try {
      // Only read today's logs — the old query pulled the child's ENTIRE
      // reading history on every open just to check one day. Bounded by a
      // date >= start-of-today filter (uses the studentId + date index).
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final snapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.student.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.student.id)
          .where('date', isGreaterThanOrEqualTo: startOfDay)
          .get();

      for (final doc in snapshot.docs) {
        final log = ReadingLogModel.fromFirestore(doc);
        final sameDay = log.date.year == now.year &&
            log.date.month == now.month &&
            log.date.day == now.day;
        if (sameDay && log.parentId != widget.parent.id) {
          if (mounted) {
            setState(() {
              _alreadyLoggedNotice =
                  '${log.loggedByDisplay} already logged ${log.minutesRead} '
                  'min for ${widget.student.firstName} today. '
                  'You can still add another session.';
            });
          }
          return;
        }
      }
    } catch (_) {
      // Non-critical — the notice is purely informational.
    }
  }

  Future<void> _loadCommentSettings() async {
    try {
      final schoolFuture = _firebaseService.firestore
          .collection('schools')
          .doc(widget.parent.schoolId)
          .get();
      final classFuture = widget.student.classId.isNotEmpty
          ? _firebaseService.firestore
              .collection('schools')
              .doc(widget.parent.schoolId)
              .collection('classes')
              .doc(widget.student.classId)
              .get()
          : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null);
      // Platform kill switch fetched alongside; never throws (fails open).
      final platformEnabledFuture =
          PlatformConfigService().isComprehensionRecordingEnabled();
      final results = await Future.wait([schoolFuture, classFuture]);
      final platformEnabled = await platformEnabledFuture;
      if (!mounted) return;
      final schoolDoc = results[0]!;
      final classDoc = results[1];
      setState(() {
        if (schoolDoc.exists) {
          final school = SchoolModel.fromFirestore(schoolDoc);
          final schoolAudio = school.comprehensionRecordingSettings;
          _schoolTimezone = school.timezone;
          _commentSettings = school.parentCommentSettings;
          _comprehensionSettings = ComprehensionRecordingSettings(
            enabled: platformEnabled && schoolAudio.enabled,
            previewOnly: schoolAudio.previewOnly,
          );
          _demoAudioPreviewOnly = schoolAudio.previewOnly;
        }
        if (classDoc != null && classDoc.exists) {
          _comprehensionQuestion =
              ClassModel.fromFirestore(classDoc).comprehensionQuestion;
        }
        // Settings can shrink the flow (comments + voice both off → 2 steps);
        // keep a restored/active page index in range.
        _currentStep = _currentStep.clamp(0, _totalSteps - 1);
      });
    } catch (_) {
      // Defaults are already set; safe to proceed with them.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _creepTimer?.cancel();
    _pageController.dispose();
    _bookTitleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _nextStep() {
    // Drop the keyboard before moving on, otherwise a field focused on an
    // earlier step (book title, parent comment) keeps it up across the rest
    // of the flow — including steps with no text field at all.
    FocusScope.of(context).unfocus();
    if (_currentStep == 0 &&
        _selectedBookTitles.isEmpty &&
        _customBookTitles.isEmpty) {
      setState(() => _errorMessage = 'Please select or enter a book');
      return;
    }
    setState(() => _errorMessage = null);

    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  List<String> get _finalBookTitles {
    return [..._selectedBookTitles, ..._customBookTitles];
  }

  String get _loadingLabel {
    switch (_phase) {
      case _SubmitPhase.saving:
        return 'Saving log';
      case _SubmitPhase.uploading:
        return 'Uploading recording';
      case _SubmitPhase.finishing:
        return 'Finishing up';
      case _SubmitPhase.idle:
        return '';
    }
  }

  void _setPhase(_SubmitPhase phase) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      switch (phase) {
        case _SubmitPhase.saving:
          // Start slightly filled so the bar reads as "started", not stalled.
          _progress = 0.04;
          break;
        case _SubmitPhase.uploading:
          _progress = _kSavingEnd;
          break;
        case _SubmitPhase.finishing:
          _progress = _kUploadEnd;
          break;
        case _SubmitPhase.idle:
          _progress = 0;
          break;
      }
    });
    if (phase == _SubmitPhase.finishing) {
      _startCreep();
    } else {
      _creepTimer?.cancel();
      _creepTimer = null;
    }
  }

  /// Eases asymptotically toward [_kCreepCeiling] so the bar keeps moving
  /// while the server works but never reaches the end before it actually
  /// finishes.
  void _startCreep() {
    _creepTimer?.cancel();
    _creepTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      setState(() {
        _progress += (_kCreepCeiling - _progress) * 0.03;
      });
    });
  }

  void _onUploadProgress(double fraction) {
    if (!mounted) return;
    final mapped =
        _kSavingEnd + (_kUploadEnd - _kSavingEnd) * fraction.clamp(0.0, 1.0);
    // Bytes land often; skip sub-pixel rebuilds.
    if ((mapped - _progress).abs() < 0.005 && fraction < 1) return;
    if (fraction >= 0.999) {
      // Bytes are in — everything left is the opaque server confirm.
      _setPhase(_SubmitPhase.finishing);
      return;
    }
    setState(() => _progress = mapped);
  }

  Future<void> _saveReadingLog() async {
    final pendingRecording = _comprehensionRecording;
    _useProgressBar = pendingRecording != null && !_demoAudioPreviewOnly;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _setPhase(_SubmitPhase.saving);

    try {
      final recording = _comprehensionRecording;
      final previewOnly = recording != null && _demoAudioPreviewOnly;
      final storagePath = recording == null || previewOnly
          ? null
          : ReadingLogService.comprehensionAudioUploadStoragePath(
              schoolId: widget.student.schoolId,
              logId: _logId,
            );

      final result = await ReadingLogService.instance.logReading(
        student: widget.student,
        parent: widget.parent,
        allocations: widget.allocations,
        minutesRead: _selectedMinutes,
        bookTitles: _finalBookTitles,
        feeling: _selectedFeeling,
        commentSelections:
            _selectedComments.take(kMaxParentCommentChips).toList(),
        freeText: _notesController.text,
        id: _logId,
        comprehensionAudioPath: storagePath,
        comprehensionAudioDurationSec:
            previewOnly ? null : recording?.durationSec,
        schoolTimezone: _schoolTimezone,
        occurredOn: _occurredOn,
      );

      // Hand the audio file off: directly online, or via the offline queue.
      // Failures here are swallowed to the queue — the log itself succeeded
      // and showing a "save failed" screen would mislead the parent.
      if (previewOnly) {
        await discardComprehensionRecordingPreview(recording);
      } else if (recording != null && storagePath != null) {
        _setPhase(_SubmitPhase.uploading);
        if (result.savedOffline) {
          // Queued, not uploaded — there is no transfer to track, so skip
          // straight to the closing phase rather than pretending to upload.
          _setPhase(_SubmitPhase.finishing);
          await OfflineService.instance.enqueueComprehensionAudioUpload(
            logId: result.log.id,
            schoolId: result.log.schoolId,
            studentId: result.log.studentId,
            storagePath: storagePath,
            localFilePath: recording.localPath,
            durationSec: recording.durationSec,
          );
        } else {
          try {
            await ReadingLogService.instance.uploadComprehensionAudio(
              log: result.log,
              localFilePath: recording.localPath,
              onProgress: _onUploadProgress,
            );
          } catch (e, st) {
            // Falling back to the queue: the bar should stop advancing on
            // bytes that are no longer being sent.
            _setPhase(_SubmitPhase.finishing);
            debugPrint(
                '[CompAudioSync] step=direct_upload failed logId=${result.log.id} '
                'type=${e.runtimeType} err=$e\n$st');
            await OfflineService.instance.enqueueComprehensionAudioUpload(
              logId: result.log.id,
              schoolId: result.log.schoolId,
              studentId: result.log.studentId,
              storagePath: storagePath,
              localFilePath: recording.localPath,
              durationSec: recording.durationSec,
            );
          }
        }
      }

      // Everything that can fail has succeeded — snap the bar full before the
      // success screen takes over.
      _creepTimer?.cancel();
      _creepTimer = null;
      if (mounted) setState(() => _progress = 1);

      // Rec 5a: a completed log supersedes any saved draft.
      await OfflineService.instance.clearLogDraft(widget.student.id);

      // Recognise the richer logging path (powers the occasional nudge +
      // positive recognition). Best-effort — never blocks the success screen.
      await LoggingEngagementService.instance.recordDetailedLog();

      // D5: the usual duration never changes silently. Track this session's
      // minutes against the guardian's usual; only after 3 consecutive
      // sessions at the same different value does the app ASK (§6.4).
      final currentUsual =
          widget.parent.usualMinutesFor(widget.student.id) ??
              (widget.allocations.isNotEmpty
                  ? widget.allocations.first.targetMinutes
                  : 20);
      // Guardian prefs live on the parent doc — schoolId is always present
      // for a linked parent, but the model keeps it nullable.
      final prefsSchoolId = widget.parent.schoolId ?? widget.student.schoolId;
      final shouldAskUsual =
          await GuardianQuickLogPrefsService.instance.recordSessionMinutes(
        schoolId: prefsSchoolId,
        parentId: widget.parent.id,
        studentId: widget.student.id,
        minutes: _selectedMinutes,
        currentUsual: currentUsual,
      );
      if (shouldAskUsual && mounted) {
        final make = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Make $_selectedMinutes minutes '
                "${widget.student.firstName}'s usual quick-log time?"),
            content: const Text(
                "You've logged this length a few times in a row. The quick "
                'log button can use it as the default.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep current'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Make it usual'),
              ),
            ],
          ),
        );
        if (make == true) {
          await GuardianQuickLogPrefsService.instance.setUsualMinutes(
            schoolId: prefsSchoolId,
            parentId: widget.parent.id,
            studentId: widget.student.id,
            minutes: _selectedMinutes,
          );
        }
      }

      if (mounted) {
        context.go('/parent/reading-success', extra: {
          'student': widget.student,
          'parent': widget.parent,
          'readingLog': result.log,
          'updatedStats': result.updatedStats,
          'savedOffline': result.savedOffline,
          'restDayApplied': result.restDayApplied,
        });
      }
    } catch (e) {
      _creepTimer?.cancel();
      _creepTimer = null;
      setState(() {
        _errorMessage = 'Failed to save reading log. Please try again.';
        _isLoading = false;
        _phase = _SubmitPhase.idle;
        _progress = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.paper,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _handleClose,
        ),
        // Child's name kept for context, but quieter than a page heading.
        title: Text(
          widget.student.firstName,
          style: LumiTextStyles.bodyMedium(color: LumiTokens.ink)
              .copyWith(fontWeight: FontWeight.w600),
        ),
        // Progress lives in the app bar (a thin bar + a compact count), so the
        // body can start straight at the step content.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(child: _buildProgressBars()),
                const SizedBox(width: 12),
                Text(
                  'Step ${_currentStep + 1} of $_totalSteps',
                  style: LumiTextStyles.caption(color: LumiTokens.muted),
                ),
              ],
            ),
          ),
        ),
      ),
      // Tap anywhere outside a field to dismiss the keyboard — the comment and
      // book-title fields otherwise had no way to close it.
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        // Local red focus border so the book-title and notes fields brand to
        // the parent red rather than the global rosePink input theme.
        child: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme:
                Theme.of(context).inputDecorationTheme.copyWith(
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: LumiTokens.red, width: 2),
                      ),
                    ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Soft notice: another guardian already logged today.
                if (_alreadyLoggedNotice != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: LumiTokens.yellow.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: LumiTokens.yellow, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _alreadyLoggedNotice!,
                              style: LumiTextStyles.bodySmall(
                                color: LumiTokens.ink,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _alreadyLoggedNotice = null),
                            child: const Icon(Icons.close,
                                color: LumiTokens.yellow, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Page content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildStep1BookSelection(),
                      if (_hasOptionalDetail) _buildStepDetail(),
                      _buildStep4Confirmation(),
                    ],
                  ),
                ),

                // Error message
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: LumiTokens.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: LumiTokens.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: LumiTextStyles.bodySmall(
                                  color: LumiTokens.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Navigation buttons
                _buildNavigationButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The three-segment progress bar, rendered in the app bar bottom.
  Widget _buildProgressBars() {
    return Row(
      children: List.generate(_totalSteps, (index) {
        final isActive = index == _currentStep;
        final isCompleted = index < _currentStep;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < _totalSteps - 1 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: isCompleted
                    ? LumiTokens.red
                    : isActive
                        ? LumiTokens.red.withValues(alpha: 0.6)
                        : LumiTokens.ink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ─── Step 1: Book Selection ──────────────────────────────

  Widget _buildStep1BookSelection() {
    final hasAssigned = _assignedBookTitles.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isYesterday ? 'Last night\'s reading' : 'Tonight\'s reading',
            style: LumiTextStyles.h2(),
          ),
          const SizedBox(height: 16),

          // D1: bounded backdating — Today or Yesterday only, school time,
          // and only while platformConfig/parentBackdating allows it.
          if (_backdatingEnabled) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Today')),
                ButtonSegment(value: true, label: Text('Yesterday')),
              ],
              selected: {_isYesterday},
              onSelectionChanged: _isLoading
                  ? null
                  : (selection) =>
                      setState(() => _isYesterday = selection.first),
            ),
            const SizedBox(height: 16),
          ],

          // Assigned books — collapsed to the first few so a large class
          // library doesn't bury Reading time + feeling. Any selected title
          // stays visible even when collapsed.
          if (hasAssigned) ...[
            _bentoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardHeader(Icons.assignment_outlined, 'Assigned books'),
                  const SizedBox(height: 4),
                  ..._visibleAssignedBooks().map((title) => CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(title, style: LumiTextStyles.body()),
                        value: _selectedBookTitles.contains(title),
                        activeColor: LumiTokens.red,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedBookTitles.add(title);
                            } else {
                              _selectedBookTitles.remove(title);
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      )),
                  if (_assignedBookTitles.length > _kCollapsedBookCount + 1)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() =>
                            _showAllAssignedBooks = !_showAllAssignedBooks),
                        style: TextButton.styleFrom(
                          foregroundColor: LumiTokens.red,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          _showAllAssignedBooks
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                        ),
                        label: Text(
                          _showAllAssignedBooks
                              ? 'Show fewer'
                              : 'Show all ${_assignedBookTitles.length} books',
                          style:
                              LumiTextStyles.bodySmall(color: LumiTokens.red),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Manual entry — a secondary path when books are assigned, so it
          // collapses to a slim, still-visible row (one tap to open). Always
          // open when nothing is assigned, or once a custom title is added.
          _bentoCard(
            child:
                (hasAssigned && !_showAddBookField && _customBookTitles.isEmpty)
                    ? InkWell(
                        onTap: () => setState(() => _showAddBookField = true),
                        child: Row(
                          children: [
                            const Icon(Icons.add_rounded,
                                size: 18, color: LumiTokens.red),
                            const SizedBox(width: 8),
                            Text("Add a book that isn't listed",
                                style: LumiTextStyles.label()),
                            const Spacer(),
                            const Icon(Icons.expand_more_rounded,
                                size: 20, color: LumiTokens.muted),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _cardHeader(
                            Icons.add_rounded,
                            hasAssigned ? 'Or add a book' : 'Add a book',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bookTitleController,
                                  cursorColor: LumiTokens.ink,
                                  decoration: _bookFieldDecoration(),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: _addCustomBook,
                                ),
                              ),
                              const SizedBox(width: 10),
                              _RoundAddButton(
                                onTap: () =>
                                    _addCustomBook(_bookTitleController.text),
                              ),
                            ],
                          ),
                          if (_customBookTitles.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _customBookTitles
                                    .map((title) => _RemovableBookChip(
                                          label: title,
                                          onDeleted: () => setState(() =>
                                              _customBookTitles.remove(title)),
                                        ))
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
          ),

          const SizedBox(height: 16),

          // Reading time — value + fine-adjust live on the header row so the
          // card stays slim; the preset chips below remain the primary,
          // big-tap control (the ± just covers the rare non-preset value).
          _bentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 18, color: LumiTokens.red),
                    const SizedBox(width: 8),
                    Text('Reading time', style: LumiTextStyles.label()),
                    const Spacer(),
                    IconButton(
                      onPressed: _selectedMinutes > 5
                          ? () => setState(() => _selectedMinutes -= 5)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      color: LumiTokens.red,
                      iconSize: 24,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(
                        '$_selectedMinutes min',
                        textAlign: TextAlign.center,
                        style: LumiTextStyles.h3(color: LumiTokens.red),
                      ),
                    ),
                    IconButton(
                      onPressed: _selectedMinutes < 120
                          ? () => setState(() => _selectedMinutes += 5)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                      color: LumiTokens.red,
                      iconSize: 24,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [10, 15, 20, 25, 30]
                        .map((minutes) => _MinuteChip(
                              minutes: minutes,
                              selected: _selectedMinutes == minutes,
                              onTap: () =>
                                  setState(() => _selectedMinutes = minutes),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // How did reading feel? — on the core page so the child's emotion is
          // captured up front, which frees the optional detail page to lead
          // with the easily-missed voice reflection.
          _bentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardHeader(
                  Icons.sentiment_satisfied_alt_outlined,
                  'How did reading feel?',
                ),
                const SizedBox(height: 2),
                Text(
                  'Let your child choose',
                  style: LumiTextStyles.bodySmall(color: LumiTokens.muted),
                ),
                const SizedBox(height: 16),
                BlobSelector(
                  showHeader: false,
                  selectedFeeling: _selectedFeeling,
                  onFeelingSelected: (feeling) {
                    setState(() => _selectedFeeling = feeling);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ─── Step 1 helpers ──────────────────────────────────────

  /// Assigned-book rows to show: when collapsed, the first few plus any
  /// already-selected titles (so a selection is never hidden off-screen).
  List<String> _visibleAssignedBooks() {
    if (_showAllAssignedBooks ||
        _assignedBookTitles.length <= _kCollapsedBookCount + 1) {
      return _assignedBookTitles;
    }
    return [
      for (var i = 0; i < _assignedBookTitles.length; i++)
        if (i < _kCollapsedBookCount ||
            _selectedBookTitles.contains(_assignedBookTitles[i]))
          _assignedBookTitles[i],
    ];
  }

  void _addCustomBook(String raw) {
    final value = raw.trim();
    if (value.isNotEmpty && !_customBookTitles.contains(value)) {
      setState(() {
        _customBookTitles.add(value);
        _bookTitleController.clear();
      });
    }
  }

  InputDecoration _bookFieldDecoration() {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: 'Enter book title',
      filled: true,
      fillColor: LumiTokens.cream,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(LumiTokens.rule, 1),
      enabledBorder: border(LumiTokens.rule, 1),
      focusedBorder: border(LumiTokens.red, 2),
    );
  }

  /// Flat bento tile: paper surface, hairline rule border, no shadow.
  Widget _bentoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: child,
    );
  }

  Widget _cardHeader(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: LumiTokens.red),
        const SizedBox(width: 8),
        Text(label, style: LumiTextStyles.label()),
      ],
    );
  }

  // ─── Step 2: Add detail (optional voice + tags + notes) ────────────
  //
  // The emotion now lives on the core first page, so this page is pure
  // optional detail. It leads with the voice reflection (an easily-missed
  // feature) in a prominent card, then the quick comment tags and notes.
  // Shown only when the school enables at least one of these.

  Widget _buildStepDetail() {
    final customPresets = _commentSettings.effectivePresets;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Anything to add?', style: LumiTextStyles.h2()),
          const SizedBox(height: 8),
          Text(
            'All optional — these help your child\'s teacher',
            style: LumiTextStyles.bodySmall(color: LumiTokens.muted),
          ),
          const SizedBox(height: 20),

          // Comprehension question first, in its own card, so it isn't missed.
          // The teacher's question is the hero — the child records an answer.
          if (_comprehensionEnabled) ...[
            _bentoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardHeader(Icons.mic_none_rounded, 'Comprehension question'),
                  const SizedBox(height: 10),
                  // The teacher's question — prominent, so the child knows
                  // exactly what they're answering.
                  Text(
                    _comprehensionQuestion,
                    style: LumiTextStyles.bodyLarge(color: LumiTokens.ink)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ask ${widget.student.firstName} to answer out loud — '
                    'optional.',
                    style: LumiTextStyles.bodySmall(color: LumiTokens.muted),
                  ),
                  const SizedBox(height: 16),
                  ComprehensionRecordingStep(
                    key: ValueKey('comprehension_$_logId'),
                    embedded: true,
                    question: _comprehensionQuestion,
                    logId: _logId,
                    initialLocalPath: _comprehensionRecording?.localPath,
                    initialDurationSec: _comprehensionRecording?.durationSec,
                    previewOnly: _demoAudioPreviewOnly,
                    onRecordingChanged: (result) {
                      setState(() => _comprehensionRecording = result);
                    },
                    onSkip: () {},
                  ),
                ],
              ),
            ),
            if (_commentsEnabled) const SizedBox(height: 24),
          ],

          // Comment tags — CommentChips owns its "How did it go?" heading and
          // the "select up to N" hint, and is fed the school's live presets, so
          // this section is identical to (and stays in sync with) the quick-log
          // success screen's comment card.
          if (_commentsEnabled)
            CommentChips(
              selectedComments: _selectedComments,
              onCommentsChanged: (comments) {
                setState(() => _selectedComments = comments);
              },
              categories: customPresets.isNotEmpty ? customPresets : null,
            ),

          // Free-text notes (only when comments + free text on).
          if (_commentsEnabled && _commentSettings.freeTextEnabled) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Additional notes', style: LumiTextStyles.label()),
            ),
            const SizedBox(height: 8),
            _buildNotesField(),
          ],
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      cursorColor: LumiTokens.ink,
      decoration: InputDecoration(
        hintText: 'Anything else to add? (optional)',
        filled: true,
        fillColor: LumiTokens.cream,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: const BorderSide(color: LumiTokens.red, width: 2),
        ),
      ),
    );
  }

  // ─── Step 4: Confirmation ────────────────────────────────

  /// Human description of the day being saved, flagged with '(school time)'
  /// whenever the device's calendar date disagrees with the school's.
  String _describeOccurredOn() {
    final label = DateFormat('EEE d MMM')
        .format(DateTime.parse('${_occurredOn}T12:00:00'));
    final dayWord = _isYesterday ? 'Yesterday' : 'Today';
    final mismatch = SchoolTime.deviceDayDiffers(_schoolTimezone);
    return mismatch ? '$dayWord · $label (school time)' : '$dayWord · $label';
  }

  Widget _buildStep4Confirmation() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Review reading', style: LumiTextStyles.h2()),
          const SizedBox(height: 8),
          Text(
            _isYesterday
                ? 'Check the details, then save last night\'s reading'
                : 'Check the details, then save tonight\'s reading',
            style: LumiTextStyles.bodySmall(
              color: LumiTokens.ink.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Summary card — the exact payload the save writes. The date row
          // states the school-local occurrence day so a backdated or
          // travelling save can never be a surprise (§6.5).
          _bentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow(
                  Icons.event,
                  'Reading day',
                  _describeOccurredOn(),
                ),
                const Divider(height: 24),
                _buildSummaryRow(
                  Icons.menu_book,
                  _finalBookTitles.length == 1 ? 'Book' : 'Books',
                  _finalBookTitles.isNotEmpty
                      ? _finalBookTitles.join(', ')
                      : 'Not selected',
                ),
                const Divider(height: 24),
                _buildSummaryRow(
                  Icons.timer,
                  'Duration',
                  '$_selectedMinutes minutes',
                ),
                if (_selectedFeeling != null) ...[
                  const Divider(height: 24),
                  _buildSummaryRow(
                    Icons.emoji_emotions,
                    'How it felt',
                    _selectedFeeling!.name[0].toUpperCase() +
                        _selectedFeeling!.name.substring(1),
                  ),
                ],
                if (_selectedComments.isNotEmpty) ...[
                  const Divider(height: 24),
                  _buildSummaryRow(
                    Icons.chat_bubble_outline,
                    'Comments',
                    _selectedComments.join(', '),
                  ),
                ],
                if (_notesController.text.isNotEmpty) ...[
                  const Divider(height: 24),
                  _buildSummaryRow(
                    Icons.note,
                    'Notes',
                    _notesController.text,
                  ),
                ],
                if (_comprehensionRecording != null) ...[
                  const Divider(height: 24),
                  _buildSummaryRow(
                    Icons.mic_none_rounded,
                    'Comprehension answer',
                    'Recorded · ${_comprehensionRecording!.durationSec}s',
                  ),
                ],
                const Divider(height: 24),
                _buildSummaryRow(
                  Icons.favorite_outline,
                  'Read together',
                  'Yes, with ${widget.student.firstName}',
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Primary submit — an unmistakable "Save" action (not a status).
          // Solid Lumi green marks the positive completion of the flow.
          LumiPrimaryButton(
            onPressed: _isLoading ? null : _saveReadingLog,
            text: 'Save reading log',
            icon: Icons.check_rounded,
            isLoading: _isLoading,
            // Determinate only when there is a recording to upload; a
            // text-only log finishes too fast for a bar to mean anything.
            progress: _isLoading && _useProgressBar ? _progress : null,
            loadingLabel: _loadingLabel,
            isFullWidth: true,
            color: LumiTokens.green,
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: LumiTokens.red),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: LumiTextStyles.caption(
                  color: LumiTokens.ink.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: LumiTextStyles.body()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    // Capped and centered on tablets so these wizard buttons don't stretch
    // edge-to-edge on iPad, matching the auth screens' width cap.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isTablet(context) ? 480.0 : double.infinity,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: LumiSecondaryButton(
                    onPressed: _previousStep,
                    text: 'Back',
                    icon: Icons.arrow_back,
                    color: LumiTokens.red,
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 12),
              if (_currentStep < _totalSteps - 1)
                Expanded(
                  child: LumiPrimaryButton(
                    onPressed: _nextStep,
                    text: _currentStep == _totalSteps - 2 ? 'Review' : 'Next',
                    isFullWidth: true,
                    color: LumiTokens.red,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flat Lumi pill for the quick-pick reading minutes. Selected = red fill
/// with a white check; unselected = paper with a hairline rule border.
class _MinuteChip extends StatelessWidget {
  const _MinuteChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? LumiTokens.red : LumiTokens.paper,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? LumiTokens.red : LumiTokens.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 14, color: LumiTokens.paper),
                const SizedBox(width: 4),
              ],
              Text(
                '$minutes',
                style: LumiTextStyles.body().copyWith(
                  color: selected ? LumiTokens.paper : LumiTokens.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red circular "add" affordance next to the book-title field.
class _RoundAddButton extends StatelessWidget {
  const _RoundAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LumiTokens.red,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(11),
          child: Icon(Icons.add, color: LumiTokens.paper, size: 22),
        ),
      ),
    );
  }
}

/// A custom-added book title shown as a soft red removable chip.
class _RemovableBookChip extends StatelessWidget {
  const _RemovableBookChip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: LumiTokens.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: LumiTextStyles.bodySmall(color: LumiTokens.ink)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDeleted,
            child: const Icon(Icons.close, size: 16, color: LumiTokens.red),
          ),
        ],
      ),
    );
  }
}

/// Stages of a reading-log submit, in order. Only [uploading] has real
/// measurable progress; [finishing] covers the server confirm, which reports
/// nothing back.
enum _SubmitPhase { idle, saving, uploading, finishing }
