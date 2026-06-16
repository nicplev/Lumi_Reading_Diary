import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
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
import '../../services/isbn_assignment_service.dart';
import '../../services/offline_service.dart';
import '../../services/platform_config_service.dart';
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
  final String _logId = DateTime.now().millisecondsSinceEpoch.toString();

  // Parent comment settings (loaded from school doc)
  ParentCommentSettings _commentSettings = ParentCommentSettings.defaults();

  // Comprehension recording settings (school toggle + per-class question)
  ComprehensionRecordingSettings _comprehensionSettings =
      ComprehensionRecordingSettings.defaults();
  String _comprehensionQuestion = ClassModel.defaultComprehensionQuestion;
  ComprehensionRecordingResult? _comprehensionRecording;

  bool get _commentsEnabled => _commentSettings.enabled;
  bool get _comprehensionEnabled => _comprehensionSettings.enabled;
  int get _totalSteps {
    var n = 3; // book, feeling, confirm
    if (_commentsEnabled) n += 1;
    if (_comprehensionEnabled) n += 1;
    return n;
  }

  // Step 1: Book selection
  final List<String> _assignedBookTitles = [];
  final Set<String> _selectedBookTitles = {};
  final List<String> _customBookTitles = [];
  int _selectedMinutes = 20;

  // Step 2: Child feeling
  ReadingFeeling? _selectedFeeling;

  // Step 3: Parent comment (skipped when comments disabled)
  List<String> _selectedComments = [];

  // Step 4 (or 3): Confirmation
  bool _isLoading = false;
  String? _errorMessage;

  // Soft, non-blocking notice when another guardian already logged today.
  String? _alreadyLoggedNotice;

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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Persist a draft when the app is backgrounded mid-wizard so an
    // interruption (call, notification, app switch) doesn't lose progress.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_hasDraftContent && !_isLoading) {
        OfflineService.instance
            .saveLogDraft(widget.student.id, _buildDraft());
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
        title: const Text('Discard draft?'),
        content: const Text(
          'Keep your progress to finish logging later, or discard it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('Keep draft'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
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
      final snapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.student.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.student.id)
          .get();

      final now = DateTime.now();
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
          _commentSettings = school.parentCommentSettings;
          _comprehensionSettings = ComprehensionRecordingSettings(
            enabled: platformEnabled &&
                school.comprehensionRecordingSettings.enabled,
          );
        }
        if (classDoc != null && classDoc.exists) {
          _comprehensionQuestion =
              ClassModel.fromFirestore(classDoc).comprehensionQuestion;
        }
      });
    } catch (_) {
      // Defaults are already set; safe to proceed with them.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _saveReadingLog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final recording = _comprehensionRecording;
      final storagePath = recording == null
          ? null
          : ReadingLogService.comprehensionAudioStoragePath(
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
        commentSelections: List<String>.from(_selectedComments),
        freeText: _notesController.text,
        id: _logId,
        comprehensionAudioPath: storagePath,
        comprehensionAudioDurationSec: recording?.durationSec,
      );

      // Hand the audio file off: directly online, or via the offline queue.
      // Failures here are swallowed to the queue — the log itself succeeded
      // and showing a "save failed" screen would mislead the parent.
      if (recording != null && storagePath != null) {
        if (result.savedOffline) {
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
            );
          } catch (_) {
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

      // Rec 5a: a completed log supersedes any saved draft.
      await OfflineService.instance.clearLogDraft(widget.student.id);

      if (mounted) {
        context.go('/parent/reading-success', extra: {
          'student': widget.student,
          'parent': widget.parent,
          'readingLog': result.log,
          'updatedStats': result.updatedStats,
          'restDayApplied': result.restDayApplied,
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save reading log. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text(
          'Log Reading - ${widget.student.firstName}',
          style: LumiTextStyles.h3(),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _handleClose,
        ),
      ),
      // Tap anywhere outside a field to dismiss the keyboard — the comment and
      // book-title fields otherwise had no way to close it.
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
        child: Column(
          children: [
            // Step indicator
            _buildStepIndicator(),

            // Soft notice: another guardian already logged today.
            if (_alreadyLoggedNotice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warmOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.warmOrange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _alreadyLoggedNotice!,
                          style: LumiTextStyles.bodySmall(
                            color: AppColors.charcoal,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _alreadyLoggedNotice = null),
                        child: const Icon(Icons.close,
                            color: AppColors.warmOrange, size: 18),
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
                  _buildStep2ChildAssessment(),
                  if (_commentsEnabled) _buildStep3ParentComment(),
                  if (_comprehensionEnabled) _buildStepComprehension(),
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
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style:
                              LumiTextStyles.bodySmall(color: AppColors.error),
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
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.rosePink
                      : isActive
                          ? AppColors.rosePink.withValues(alpha: 0.6)
                          : AppColors.charcoal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Step 1: Book Selection ──────────────────────────────

  Widget _buildStep1BookSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What did you read?', style: LumiTextStyles.h2()),
          const SizedBox(height: 8),
          Text(
            'Select a book or add your own',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Assigned books as checkbox list
          if (_assignedBookTitles.isNotEmpty) ...[
            LumiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assigned Books', style: LumiTextStyles.label()),
                  const SizedBox(height: 12),
                  ..._assignedBookTitles.map((title) => CheckboxListTile(
                        title: Text(title, style: LumiTextStyles.body()),
                        value: _selectedBookTitles.contains(title),
                        activeColor: AppColors.rosePink,
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
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Manual entry
          LumiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _assignedBookTitles.isNotEmpty
                      ? 'Or add a book'
                      : 'Add a book',
                  style: LumiTextStyles.label(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bookTitleController,
                        decoration: const InputDecoration(
                          hintText: 'Enter book title',
                          prefixIcon: Icon(Icons.add),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) {
                          if (value.isNotEmpty &&
                              !_customBookTitles.contains(value)) {
                            setState(() {
                              _customBookTitles.add(value);
                              _bookTitleController.clear();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        final value = _bookTitleController.text.trim();
                        if (value.isNotEmpty &&
                            !_customBookTitles.contains(value)) {
                          setState(() {
                            _customBookTitles.add(value);
                            _bookTitleController.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add_circle),
                      color: AppColors.rosePink,
                      iconSize: 32,
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
                          .map((title) => Chip(
                                label: Text(title),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () {
                                  setState(
                                      () => _customBookTitles.remove(title));
                                },
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Minutes selector
          LumiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer, color: AppColors.rosePink),
                    const SizedBox(width: 8),
                    Text('Reading Time', style: LumiTextStyles.label()),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _selectedMinutes > 5
                          ? () => setState(() => _selectedMinutes -= 5)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      color: AppColors.rosePink,
                      iconSize: 28,
                    ),
                    SizedBox(
                      width: 140,
                      child: Center(
                        child: Text(
                          '$_selectedMinutes min',
                          style: LumiTextStyles.displayMedium(
                              color: AppColors.rosePink),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _selectedMinutes < 120
                          ? () => setState(() => _selectedMinutes += 5)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                      color: AppColors.rosePink,
                      iconSize: 28,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [10, 15, 20, 25, 30].map((minutes) {
                      return ChoiceChip(
                        label: Text('$minutes'),
                        selected: _selectedMinutes == minutes,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedMinutes = minutes);
                          }
                        },
                        selectedColor: AppColors.rosePink,
                        labelStyle: TextStyle(
                          color: _selectedMinutes == minutes
                              ? AppColors.white
                              : AppColors.charcoal,
                          fontWeight: _selectedMinutes == minutes
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ─── Step 2: Child Assessment ────────────────────────────

  Widget _buildStep2ChildAssessment() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: BlobSelector(
          selectedFeeling: _selectedFeeling,
          onFeelingSelected: (feeling) {
            setState(() => _selectedFeeling = feeling);
          },
        ),
      ),
    ).animate().fadeIn();
  }

  // ─── Step 3: Parent Comment ──────────────────────────────

  Widget _buildStep3ParentComment() {
    final customPresets = _commentSettings.effectivePresets;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentChips(
            selectedComments: _selectedComments,
            onCommentsChanged: (comments) {
              setState(() => _selectedComments = comments);
            },
            categories: customPresets.isNotEmpty ? customPresets : null,
          ),
          if (_commentSettings.freeTextEnabled) ...[
            const SizedBox(height: 24),
            Text('Additional notes', style: LumiTextStyles.label()),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Anything else to add? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn();
  }

  // ─── Optional Step: Comprehension Recording ──────────────

  Widget _buildStepComprehension() {
    return ComprehensionRecordingStep(
      key: ValueKey('comprehension_$_logId'),
      question: _comprehensionQuestion,
      logId: _logId,
      initialLocalPath: _comprehensionRecording?.localPath,
      initialDurationSec: _comprehensionRecording?.durationSec,
      onRecordingChanged: (result) {
        setState(() => _comprehensionRecording = result);
      },
      onSkip: _nextStep,
    ).animate().fadeIn();
  }

  // ─── Step 4: Confirmation ────────────────────────────────

  Widget _buildStep4Confirmation() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Confirm Reading', style: LumiTextStyles.h2()),
          const SizedBox(height: 8),
          Text(
            'Review and confirm tonight\'s reading',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Summary card
          LumiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Confirmation button with green gradient
          SizedBox(
            width: double.infinity,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveReadingLog,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.white),
                        ),
                      )
                    : const Icon(Icons.check, color: AppColors.white),
                label: Text(
                  'I read with my child tonight',
                  style: LumiTextStyles.button(),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.rosePink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: LumiTextStyles.caption(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: LumiSecondaryButton(
                onPressed: _previousStep,
                text: 'Back',
                icon: Icons.arrow_back,
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          if (_currentStep < _totalSteps - 1)
            Expanded(
              child: LumiPrimaryButton(
                onPressed: _nextStep,
                text: _currentStep == _totalSteps - 2
                    ? 'Review'
                    : _currentStep == 1
                        ? (_selectedFeeling != null ? 'Next' : 'Skip')
                        : 'Next',
                isFullWidth: true,
              ),
            ),
        ],
      ),
    );
  }
}
