import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/dev_access.dart';
import '../../core/widgets/audio/comprehension_audio_player.dart';
import '../../core/widgets/comments/teacher_comments_sheet.dart';
import '../../core/widgets/inline_stream_error.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../data/models/class_model.dart';
import '../../data/models/comprehension_eval_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/user_model.dart';
import '../../data/providers/access_provider.dart';
import '../../data/providers/comprehension_eval_providers.dart';
import '../../data/providers/comprehension_recordings_provider.dart';
import '../../data/providers/school_settings_provider.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import 'student_detail/comprehension_section.dart'
    show ComprehensionLevelChip, ComprehensionFlagChip;
import 'student_detail/reading_log_snapshot.dart' show formatCommentDate;

enum _RecordingFilter { toReview, recent, reviewed }

/// The standard teacher inbox for retained child comprehension recordings.
///
/// This surface is independent of AI evaluation. It only creates its
/// Firestore subscriptions after both the school opt-in and platform switch
/// resolve positively; AI data is separately fail-closed, dev-gated during the
/// pilot, and not fetched until a teacher expands one recording's disclosure.
class ComprehensionRecordingsScreen extends ConsumerWidget {
  final UserModel teacher;
  final ClassModel classModel;
  final void Function(ReadingLogModel log, String studentName)?
      onReplyForTesting;

  const ComprehensionRecordingsScreen({
    super.key,
    required this.teacher,
    required this.classModel,
    this.onReplyForTesting,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = teacher.schoolId ?? '';
    final platform = ref.watch(platformComprehensionAudioEnabledProvider);
    final school = ref.watch(schoolByIdProvider(schoolId));

    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.cream,
        elevation: 0,
        foregroundColor: LumiTokens.ink,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comprehension recordings',
              style: LumiType.subhead,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              classModel.name,
              style: LumiType.caption.copyWith(color: LumiTokens.muted),
            ),
          ],
        ),
      ),
      body: platform.isLoading || school.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordingsEnabled(platform, school)
              ? _EnabledRecordingsInbox(
                  teacher: teacher,
                  classModel: classModel,
                  onReplyForTesting: onReplyForTesting,
                )
              : _UnavailableState(
                  hasError: platform.hasError || school.hasError,
                ),
    );
  }

  bool _recordingsEnabled(
    AsyncValue<bool> platform,
    AsyncValue<dynamic> school,
  ) {
    final platformOn = platform.value == true;
    final schoolModel = school.value;
    final audioSettings = schoolModel?.comprehensionRecordingSettings;
    return platformOn &&
        audioSettings?.enabled == true &&
        audioSettings?.previewOnly != true;
  }
}

class _UnavailableState extends StatelessWidget {
  final bool hasError;

  const _UnavailableState({required this.hasError});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LumiTokens.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_outlined, size: 36, color: LumiTokens.muted),
            const SizedBox(height: LumiTokens.space3),
            Text(
              hasError
                  ? "Comprehension recordings couldn't be checked right now."
                  : 'Comprehension recordings are not enabled for this school.',
              style: LumiType.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EnabledRecordingsInbox extends ConsumerStatefulWidget {
  final UserModel teacher;
  final ClassModel classModel;
  final void Function(ReadingLogModel log, String studentName)?
      onReplyForTesting;

  const _EnabledRecordingsInbox({
    required this.teacher,
    required this.classModel,
    this.onReplyForTesting,
  });

  @override
  ConsumerState<_EnabledRecordingsInbox> createState() =>
      _EnabledRecordingsInboxState();
}

class _EnabledRecordingsInboxState
    extends ConsumerState<_EnabledRecordingsInbox> {
  _RecordingFilter _filter = _RecordingFilter.toReview;
  bool _selectionMode = false;
  bool _isUpdatingReviewStatus = false;
  final Set<String> _selectedRecordingIds = <String>{};
  final ComprehensionRecordingReviewService _reviewService =
      ComprehensionRecordingReviewService();

  String get _schoolId => widget.teacher.schoolId ?? '';

  ComprehensionRecordingsLookup get _recordingLookup =>
      ComprehensionRecordingsLookup(
        schoolId: _schoolId,
        classId: widget.classModel.id,
      );

  @override
  Widget build(BuildContext context) {
    final recordingsAsync =
        ref.watch(classComprehensionRecordingsProvider(_recordingLookup));
    final pendingAsync =
        ref.watch(pendingComprehensionRecordingsProvider(_recordingLookup));
    final names = ref
            .watch(comprehensionRecordingStudentNamesProvider(_recordingLookup))
            .value ??
        const <String, String>{};
    final aiEnabled =
        hasDevAccess() && ref.watch(aiEvaluationEnabledProvider(_schoolId));

    return recordingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: InlineStreamError(
          message: "Couldn't load comprehension recordings.",
          onRetry: () => ref.invalidate(
            classComprehensionRecordingsProvider(_recordingLookup),
          ),
        ),
      ),
      data: (recordings) {
        final pending = pendingAsync.value;
        if (pending == null && pendingAsync.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (pendingAsync.hasError) {
          return Center(
            child: InlineStreamError(
              message: "Couldn't load recordings to review.",
              onRetry: () => ref.invalidate(
                pendingComprehensionRecordingsProvider(_recordingLookup),
              ),
            ),
          );
        }
        final pendingById = <String, ReadingLogModel>{
          for (final recording in pending ?? const <ReadingLogModel>[])
            recording.id: recording,
          // Keep recent pre-migration rows visible until the explicit backfill
          // normalises their missing status to pending.
          for (final recording in recordings)
            if (recording.comprehensionAudioReviewStatus == null)
              recording.id: recording,
        };
        final toReviewRows = pendingById.values.toList(growable: false)
          ..sort((a, b) => (b.comprehensionAudioUploadedAt ?? b.date)
              .compareTo(a.comprehensionAudioUploadedAt ?? a.date));
        final reviewedRows = recordings
            .where((recording) => recording.isComprehensionAudioReviewed)
            .toList(growable: false);
        final visible = switch (_filter) {
          _RecordingFilter.toReview => toReviewRows,
          _RecordingFilter.recent => recordings,
          _RecordingFilter.reviewed => reviewedRows,
        };
        final selectedVisible = visible
            .where((recording) => _selectedRecordingIds.contains(recording.id))
            .toList(growable: false);
        final selectedToReviewCount = selectedVisible
            .where((recording) => !recording.isComprehensionAudioReviewed)
            .length;
        final selectedReviewedCount = selectedVisible
            .where((recording) => recording.isComprehensionAudioReviewed)
            .length;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(
              classComprehensionRecordingsProvider(_recordingLookup),
            );
            ref.invalidate(
              pendingComprehensionRecordingsProvider(_recordingLookup),
            );
            await ref.read(
              pendingComprehensionRecordingsProvider(_recordingLookup).future,
            );
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _InboxSummary(
                  toReview: toReviewRows.length,
                  reviewed: reviewedRows.length,
                ),
              ),
              SliverToBoxAdapter(
                child: _buildFilters(canSelect: visible.isNotEmpty),
              ),
              if (_selectionMode)
                SliverToBoxAdapter(
                  child: _SelectionToolbar(
                    selectedCount: selectedVisible.length,
                    visibleCount: visible.length,
                    selectedToReviewCount: selectedToReviewCount,
                    selectedReviewedCount: selectedReviewedCount,
                    isUpdating: _isUpdatingReviewStatus,
                    onToggleAll: () => _toggleAllVisible(visible),
                    onMarkReviewed: () => _updateSelectedReviewStatus(
                      visible: visible,
                      reviewed: true,
                    ),
                    onMarkToReview: () => _updateSelectedReviewStatus(
                      visible: visible,
                      reviewed: false,
                    ),
                  ),
                ),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyInbox(
                    filter: _filter,
                    hasAnyRecordings: recordings.isNotEmpty,
                    onViewAll: () =>
                        setState(() => _filter = _RecordingFilter.recent),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: LumiTokens.space2),
                    itemBuilder: (context, index) {
                      final recording = visible[index];
                      final studentName =
                          names[recording.studentId] ?? 'Student';
                      return _RecordingRow(
                        recording: recording,
                        studentName: studentName,
                        selectionMode: _selectionMode,
                        isSelected:
                            _selectedRecordingIds.contains(recording.id),
                        onTap: _selectionMode
                            ? () => _toggleRecording(recording.id)
                            : () => _openRecording(
                                  recordings: visible,
                                  initialIndex: index,
                                  names: names,
                                  aiEnabled: aiEnabled,
                                ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters({required bool canSelect}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TeacherFilterChip(
                    label: 'To review',
                    isActive: _filter == _RecordingFilter.toReview,
                    activeColor: LumiTokens.red,
                    onTap: _isUpdatingReviewStatus
                        ? null
                        : () => _setFilter(_RecordingFilter.toReview),
                  ),
                  const SizedBox(width: 6),
                  TeacherFilterChip(
                    label: 'Recent',
                    isActive: _filter == _RecordingFilter.recent,
                    activeColor: LumiTokens.blue,
                    onTap: _isUpdatingReviewStatus
                        ? null
                        : () => _setFilter(_RecordingFilter.recent),
                  ),
                  const SizedBox(width: 6),
                  TeacherFilterChip(
                    label: 'Reviewed',
                    isActive: _filter == _RecordingFilter.reviewed,
                    activeColor: LumiTokens.green,
                    onTap: _isUpdatingReviewStatus
                        ? null
                        : () => _setFilter(_RecordingFilter.reviewed),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: _selectionMode
                ? 'Finish selecting recordings'
                : 'Select recordings',
            button: true,
            child: TeacherFilterChip(
              label: _selectionMode ? 'Done' : 'Select',
              icon: _selectionMode
                  ? Icons.check_rounded
                  : Icons.checklist_rounded,
              isActive: _selectionMode,
              activeColor: LumiTokens.blue,
              activeForegroundColor: LumiTokens.ink,
              onTap: _isUpdatingReviewStatus || (!canSelect && !_selectionMode)
                  ? null
                  : _toggleSelectionMode,
            ),
          ),
        ],
      ),
    );
  }

  void _setFilter(_RecordingFilter filter) {
    setState(() {
      _filter = filter;
      // Selection belongs to the current view. Clearing it when switching
      // filters prevents an accidental mixed-status bulk action.
      _selectedRecordingIds.clear();
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedRecordingIds.clear();
    });
  }

  void _toggleRecording(String recordingId) {
    if (_isUpdatingReviewStatus) return;
    setState(() {
      if (!_selectedRecordingIds.add(recordingId)) {
        _selectedRecordingIds.remove(recordingId);
      }
    });
  }

  void _toggleAllVisible(List<ReadingLogModel> visible) {
    if (_isUpdatingReviewStatus || visible.isEmpty) return;
    final visibleIds = visible.map((recording) => recording.id).toSet();
    final allSelected = visibleIds.every(_selectedRecordingIds.contains);
    setState(() {
      if (allSelected) {
        _selectedRecordingIds.removeAll(visibleIds);
      } else {
        _selectedRecordingIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _updateSelectedReviewStatus({
    required List<ReadingLogModel> visible,
    required bool reviewed,
  }) async {
    if (_isUpdatingReviewStatus) return;
    final targets = visible
        .where((recording) => _selectedRecordingIds.contains(recording.id))
        .where(
          (recording) => recording.isComprehensionAudioReviewed != reviewed,
        )
        .toList(growable: false);
    if (targets.isEmpty) return;

    setState(() => _isUpdatingReviewStatus = true);
    final completedIds = <String>{};
    var failures = 0;
    // A small window keeps select-all responsive without opening an unbounded
    // number of Firestore transactions for the 200-row inbox cap.
    const writesAtOnce = 8;
    for (var start = 0; start < targets.length; start += writesAtOnce) {
      final results = await Future.wait(
        targets.skip(start).take(writesAtOnce).map((recording) async {
          try {
            if (reviewed) {
              await _reviewService.markReviewed(
                schoolId: recording.schoolId,
                logId: recording.id,
              );
            } else {
              await _reviewService.markToReview(
                schoolId: recording.schoolId,
                logId: recording.id,
              );
            }
            return recording.id;
          } catch (_) {
            return null;
          }
        }),
      );
      for (final id in results) {
        if (id == null) {
          failures++;
        } else {
          completedIds.add(id);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _isUpdatingReviewStatus = false;
      _selectedRecordingIds.removeAll(completedIds);
    });
    final action = reviewed ? 'reviewed' : 'back to review';
    if (failures == 0) {
      showLumiToast(
        message:
            '${completedIds.length} recording${completedIds.length == 1 ? '' : 's'} marked $action.',
        type: LumiToastType.success,
      );
    } else {
      showLumiToast(
        message:
            'Updated ${completedIds.length} of ${targets.length} recordings. Please try the rest again.',
        type: LumiToastType.warning,
      );
    }
  }

  void _openRecording({
    required List<ReadingLogModel> recordings,
    required int initialIndex,
    required Map<String, String> names,
    required bool aiEnabled,
  }) {
    showComprehensionRecordingSheet(
      context,
      recordings: recordings,
      initialIndex: initialIndex,
      studentNames: names,
      aiEnabled: aiEnabled,
      onReply: (log, studentName) {
        if (!mounted) return;
        final testCallback = widget.onReplyForTesting;
        if (testCallback != null) {
          testCallback(log, studentName);
          return;
        }
        openTeacherCommentsSheet(
          context,
          log: log,
          studentName: studentName,
        );
      },
    );
  }
}

class _InboxSummary extends StatelessWidget {
  final int toReview;
  final int reviewed;

  const _InboxSummary({required this.toReview, required this.reviewed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                size: 18,
                color: LumiTokens.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Review status is shared with co-teachers.',
                  style: LumiType.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InboxMetricTile(
                  value: toReview >= 200 ? '200+' : '$toReview',
                  label: 'To review',
                  icon: Icons.pending_outlined,
                  backgroundColor: LumiTokens.tintBlue,
                  accentColor: LumiTokens.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InboxMetricTile(
                  value: '$reviewed',
                  label: 'Reviewed',
                  icon: Icons.check_circle_outline_rounded,
                  backgroundColor: LumiTokens.tintGreen,
                  accentColor: LumiTokens.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InboxMetricTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color accentColor;

  const _InboxMetricTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: LumiTokens.paper,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(height: 12),
          Text(value, style: LumiType.heading.copyWith(color: accentColor)),
          Text(
            label,
            style: LumiType.body.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  final int selectedCount;
  final int visibleCount;
  final int selectedToReviewCount;
  final int selectedReviewedCount;
  final bool isUpdating;
  final VoidCallback onToggleAll;
  final VoidCallback onMarkReviewed;
  final VoidCallback onMarkToReview;

  const _SelectionToolbar({
    required this.selectedCount,
    required this.visibleCount,
    required this.selectedToReviewCount,
    required this.selectedReviewedCount,
    required this.isUpdating,
    required this.onToggleAll,
    required this.onMarkReviewed,
    required this.onMarkToReview,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = visibleCount > 0 && selectedCount == visibleCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: LumiTokens.tintBlue,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(color: LumiTokens.blue.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: LumiTokens.paper,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$selectedCount',
                    style: LumiType.body.copyWith(color: LumiTokens.blue),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$selectedCount selected',
                        style: LumiType.body,
                      ),
                      Text(
                        'Update their shared review status.',
                        style:
                            LumiType.caption.copyWith(color: LumiTokens.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed:
                      isUpdating || visibleCount == 0 ? null : onToggleAll,
                  style: TextButton.styleFrom(
                    foregroundColor: LumiTokens.ink,
                    textStyle: LumiType.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(allSelected ? 'Clear' : 'Select all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isUpdating) ...[
              const LinearProgressIndicator(color: LumiTokens.blue),
            ] else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ReviewStatusAction(
                    label: 'Mark reviewed',
                    icon: Icons.check_circle_outline_rounded,
                    color: LumiTokens.green,
                    foregroundColor: LumiTokens.paper,
                    enabled: selectedToReviewCount > 0,
                    onPressed: onMarkReviewed,
                  ),
                  _ReviewStatusAction(
                    label: 'To review',
                    icon: Icons.undo_rounded,
                    color: LumiTokens.tintYellow,
                    foregroundColor: LumiTokens.ink,
                    enabled: selectedReviewedCount > 0,
                    onPressed: onMarkToReview,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStatusAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final bool enabled;
  final VoidCallback onPressed;

  const _ReviewStatusAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.foregroundColor,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
    );
    final textStyle = LumiType.caption.copyWith(fontWeight: FontWeight.w700);

    // Disabled → a faint ghost outline (no fill), so it reads clearly as
    // "unavailable" rather than as a secondary solid button. The old pale-solid
    // treatment nearly matched the selection panel behind it.
    if (!enabled) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: LumiTokens.muted.withValues(alpha: 0.45),
          side: BorderSide(color: LumiTokens.rule.withValues(alpha: 0.8)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          shape: shape,
          textStyle: textStyle,
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: shape,
        textStyle: textStyle,
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  final ReadingLogModel recording;
  final String studentName;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecordingRow({
    required this.recording,
    required this.studentName,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reviewed = recording.isComprehensionAudioReviewed;
    final books = recording.bookTitles.isEmpty
        ? 'Free reading'
        : recording.bookTitles.join(', ');
    final date = recording.comprehensionAudioUploadedAt ?? recording.date;

    return Material(
      color: LumiTokens.paper,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
            border: Border.all(
              color: isSelected
                  ? LumiTokens.blue
                  : reviewed
                      ? LumiTokens.rule
                      : LumiTokens.tintBlue,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor:
                    reviewed ? LumiTokens.cream : LumiTokens.tintBlue,
                child: Text(
                  _initials(studentName),
                  style: LumiType.caption.copyWith(
                    color: LumiTokens.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studentName, style: LumiType.body),
                    Text(
                      books,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LumiType.caption.copyWith(color: LumiTokens.muted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatCommentDate(date)} · '
                      '${_formatDuration(recording.comprehensionAudioDurationSec)}',
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selectionMode)
                Semantics(
                  label: 'Select $studentName',
                  selected: isSelected,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onTap(),
                    activeColor: LumiTokens.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ReviewChip(reviewed: reviewed),
                    const SizedBox(height: 5),
                    Icon(
                      Icons.play_circle_fill_rounded,
                      size: 26,
                      color: reviewed ? LumiTokens.muted : LumiTokens.red,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewChip extends StatelessWidget {
  final bool reviewed;

  const _ReviewChip({required this.reviewed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: reviewed ? LumiTokens.tintGreen : LumiTokens.tintYellow,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
      child: Text(
        reviewed ? 'Reviewed' : 'To review',
        style: LumiType.caption.copyWith(
          color: LumiTokens.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  final _RecordingFilter filter;
  final bool hasAnyRecordings;
  final VoidCallback onViewAll;

  const _EmptyInbox({
    required this.filter,
    required this.hasAnyRecordings,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final caughtUp = filter == _RecordingFilter.toReview && hasAnyRecordings;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              caughtUp ? Icons.check_circle_outline : Icons.mic_none_rounded,
              size: 38,
              color: caughtUp ? LumiTokens.green : LumiTokens.muted,
            ),
            const SizedBox(height: 10),
            Text(
              caughtUp
                  ? "You're all caught up"
                  : hasAnyRecordings
                      ? 'No recordings match this view.'
                      : 'No comprehension recordings yet.',
              style: LumiType.subhead,
              textAlign: TextAlign.center,
            ),
            if (caughtUp) ...[
              const SizedBox(height: 6),
              TextButton(onPressed: onViewAll, child: const Text('View all')),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showComprehensionRecordingSheet(
  BuildContext parentContext, {
  required List<ReadingLogModel> recordings,
  required int initialIndex,
  required Map<String, String> studentNames,
  required bool aiEnabled,
  required void Function(ReadingLogModel log, String studentName) onReply,
}) {
  return showModalBottomSheet<void>(
    context: parentContext,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ComprehensionRecordingSheet(
      recordings: recordings,
      initialIndex: initialIndex,
      studentNames: studentNames,
      aiEnabled: aiEnabled,
      onReply: (log, studentName) {
        Navigator.of(sheetContext).pop();
        Future<void>.delayed(Duration.zero, () {
          if (parentContext.mounted) onReply(log, studentName);
        });
      },
    ),
  );
}

class _ComprehensionRecordingSheet extends ConsumerStatefulWidget {
  final List<ReadingLogModel> recordings;
  final int initialIndex;
  final Map<String, String> studentNames;
  final bool aiEnabled;
  final void Function(ReadingLogModel log, String studentName) onReply;

  const _ComprehensionRecordingSheet({
    required this.recordings,
    required this.initialIndex,
    required this.studentNames,
    required this.aiEnabled,
    required this.onReply,
  });

  @override
  ConsumerState<_ComprehensionRecordingSheet> createState() =>
      _ComprehensionRecordingSheetState();
}

class _ComprehensionRecordingSheetState
    extends ConsumerState<_ComprehensionRecordingSheet> {
  late int _index;
  final Set<String> _locallyReviewed = {};
  final ComprehensionRecordingReviewService _reviewService =
      ComprehensionRecordingReviewService();

  ReadingLogModel get _recording => widget.recordings[_index];
  String get _studentName =>
      widget.studentNames[_recording.studentId] ?? 'Student';
  bool get _reviewed =>
      _recording.isComprehensionAudioReviewed ||
      _locallyReviewed.contains(_recording.id);
  bool get _hasNext => _index + 1 < widget.recordings.length;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final recording = _recording;
    ref.listen<bool>(comprehensionAudioEnabledProvider(recording.schoolId),
        (previous, next) {
      if (previous == true && !next && mounted) {
        Navigator.of(context).pop();
        showLumiToast(
          message:
              'Comprehension recordings have been turned off for this school.',
          type: LumiToastType.info,
        );
      }
    });
    final messagingOn = ref.watch(messagingEnabledProvider(recording.schoolId));
    final books = recording.bookTitles.isEmpty
        ? 'Free reading'
        : recording.bookTitles.join(', ');

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusXL)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: LumiTokens.rule,
                borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_studentName, style: LumiType.subhead),
                        Text(
                          '$books · ${formatCommentDate(recording.date)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LumiType.caption
                              .copyWith(color: LumiTokens.muted),
                        ),
                      ],
                    ),
                  ),
                  _ReviewChip(reviewed: _reviewed),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: LumiTokens.rule),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                children: [
                  if (recording.comprehensionQuestionText?.trim().isNotEmpty ==
                      true) ...[
                    _BentoSection(
                      icon: Icons.quiz_outlined,
                      label: 'Question asked',
                      child: Text(
                        recording.comprehensionQuestionText!,
                        style: LumiType.body,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _BentoSection(
                    icon: Icons.graphic_eq_rounded,
                    label: 'Recording',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ComprehensionAudioPlayer(
                          key: ValueKey(
                            '${recording.id}-'
                            '${recording.comprehensionAudioObjectGeneration}',
                          ),
                          storagePath: recording.comprehensionAudioPath!,
                          durationSec: recording.comprehensionAudioDurationSec,
                          schoolId: recording.schoolId,
                          logId: recording.id,
                          onMostlyPlayed: _markReviewed,
                          onDeleted: _afterDelete,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _reviewed
                              ? 'Reviewed for the teaching team.'
                              : '80% playback marks this automatically. You can also update it from the inbox.',
                          style: LumiType.caption
                              .copyWith(color: LumiTokens.muted),
                        ),
                      ],
                    ),
                  ),
                  if (widget.aiEnabled) ...[
                    const SizedBox(height: 12),
                    _AiSummaryDisclosure(
                      key: ValueKey('ai-${recording.id}'),
                      schoolId: recording.schoolId,
                      logId: recording.id,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      if (messagingOn)
                        TextButton.icon(
                          onPressed: () =>
                              widget.onReply(recording, _studentName),
                          icon:
                              const Icon(Icons.mode_comment_outlined, size: 18),
                          label: const Text('Reply to family'),
                          style: TextButton.styleFrom(
                            foregroundColor: LumiTokens.muted,
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _hasNext ? _next : null,
                        icon: const Icon(Icons.skip_next_rounded, size: 18),
                        label: const Text('Next recording'),
                        style: FilledButton.styleFrom(
                          backgroundColor: LumiTokens.blue,
                          foregroundColor: LumiTokens.ink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() {
    if (!_hasNext) return;
    setState(() => _index++);
  }

  void _afterDelete() {
    if (_hasNext) {
      _next();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _markReviewed() {
    final recording = _recording;
    if (_reviewed) return;
    setState(() => _locallyReviewed.add(recording.id));
    unawaited(
      _reviewService
          .markReviewed(schoolId: recording.schoolId, logId: recording.id)
          .catchError((_) {
        if (!mounted) return;
        setState(() => _locallyReviewed.remove(recording.id));
        showLumiToast(
          message: "Couldn't save the shared review status.",
          type: LumiToastType.error,
        );
      }),
    );
  }
}

class _BentoSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _BentoSection({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: LumiTokens.blue),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: LumiType.sectionLabel.copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _AiSummaryDisclosure extends ConsumerStatefulWidget {
  final String schoolId;
  final String logId;

  const _AiSummaryDisclosure({
    super.key,
    required this.schoolId,
    required this.logId,
  });

  @override
  ConsumerState<_AiSummaryDisclosure> createState() =>
      _AiSummaryDisclosureState();
}

class _AiSummaryDisclosureState extends ConsumerState<_AiSummaryDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _expanded = true),
          icon: const Icon(Icons.auto_awesome_outlined, size: 17),
          label: const Text('View AI summary'),
          style: OutlinedButton.styleFrom(foregroundColor: LumiTokens.muted),
        ),
      );
    }

    final evaluation = ref.watch(recordingEvalProvider(RecordingEvalLookup(
      schoolId: widget.schoolId,
      logId: widget.logId,
    )));
    return _BentoSection(
      icon: Icons.auto_awesome_outlined,
      label: 'AI summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          evaluation.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => Text(
              "The AI summary couldn't be loaded.",
              style: LumiType.caption,
            ),
            data: (eval) => _AiSummaryContent(evaluation: eval),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _expanded = false),
            child: const Text('Hide AI summary'),
          ),
        ],
      ),
    );
  }
}

class _AiSummaryContent extends StatelessWidget {
  final ComprehensionEvalModel? evaluation;

  const _AiSummaryContent({required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final eval = evaluation;
    if (eval == null) {
      return Text('No AI summary is available.', style: LumiType.caption);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ComprehensionLevelChip(
              level: eval.overallLevel,
              status: eval.status,
            ),
            for (final flag in eval.flags.take(2))
              ComprehensionFlagChip(flag: flag),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          eval.summary?.trim().isNotEmpty == true
              ? eval.summary!
              : 'No written summary is available.',
          style: LumiType.body,
        ),
        const SizedBox(height: 8),
        Text(
          'AI-generated and may be inaccurate. Listen to the recording and '
          'use your professional judgement.',
          style: LumiType.caption.copyWith(color: LumiTokens.muted),
        ),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

String _formatDuration(int? seconds) {
  final value = seconds ?? 0;
  final minutes = value ~/ 60;
  final remainder = (value % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}
