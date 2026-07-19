import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/dev_access.dart';
import '../../../core/widgets/inline_stream_error.dart';
import '../../../data/models/comprehension_eval_model.dart';
import '../../../data/providers/comprehension_eval_providers.dart';
import '../../../data/providers/student_detail_providers.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../widgets/comprehension_eval_sheet.dart';
import 'reading_log_snapshot.dart';

/// "Comprehension" section on the teacher student-detail screen.
///
/// Pilot-gated: rendered only when the AI-evaluation entitlement is on for
/// the school AND the signed-in user has dev access (un-gating for pilot
/// teachers = removing the hasDevAccess clause). Shows the latest AI
/// evaluation (level + confidence + summary + flags), a 5-dot level trend,
/// a pending line for recordings still awaiting evaluation, and a banner
/// when the recording was replaced after its evaluation ran.
class ComprehensionSection extends ConsumerWidget {
  final StudentDetailLookup lookup;
  final String studentName;
  final VoidCallback? onViewAll;

  const ComprehensionSection({
    super.key,
    required this.lookup,
    required this.studentName,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(aiEvaluationEnabledProvider(lookup.schoolId));
    if (!enabled || !hasDevAccess()) return const SizedBox.shrink();

    final evalsAsync = ref.watch(studentEvalsProvider(lookup));
    final logsAsync = ref.watch(studentRecentLogsProvider(lookup));

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Comprehension', style: LumiType.subhead),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  child: Text(
                    'View all',
                    style: LumiType.caption.copyWith(
                      color: LumiTokens.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          evalsAsync.when(
            error: (_, __) => InlineStreamError(
              message: "Couldn't load comprehension evaluations.",
              onRetry: () => ref.invalidate(studentEvalsProvider(lookup)),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            data: (evals) {
              final logs = logsAsync.value == null
                  ? const <ReadingLogSnapshot>[]
                  : toReadingLogSnapshots(logsAsync.value!);
              return _SectionBody(
                lookup: lookup,
                studentName: studentName,
                evals: evals,
                recentLogs: logs,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  final StudentDetailLookup lookup;
  final String studentName;
  final List<ComprehensionEvalModel> evals;
  final List<ReadingLogSnapshot> recentLogs;

  const _SectionBody({
    required this.lookup,
    required this.studentName,
    required this.evals,
    required this.recentLogs,
  });

  /// Recordings uploaded in the last 48h with no evaluation yet — keeps
  /// morning triage from reading "queued" as "the AI missed my student".
  int get _pendingCount {
    final evaluated = evals.map((e) => e.logId).toSet();
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    return recentLogs
        .where((log) =>
            log.comprehensionAudioUploaded &&
            (log.comprehensionAudioUploadedAt ?? log.createdAt)
                .isAfter(cutoff) &&
            !evaluated.contains(log.id))
        .length;
  }

  bool get _latestReplaced {
    if (evals.isEmpty) return false;
    final latest = evals.first;
    for (final log in recentLogs) {
      if (log.id == latest.logId) {
        return latest.audioReplacedSince(log.comprehensionAudioUploadedAt);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingCount;
    if (evals.isEmpty && pending == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(color: LumiTokens.rule),
        ),
        child: Center(
          child: Text('No comprehension evaluations yet',
              style: LumiType.caption),
        ),
      );
    }

    final latest = evals.isEmpty ? null : evals.first;
    return Container(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_latestReplaced) ...[
            _ReplacedBanner(),
            const SizedBox(height: 10),
          ],
          if (latest != null)
            InkWell(
              onTap: () => showComprehensionEvalSheet(
                context,
                eval: latest,
                studentName: studentName,
              ),
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              child: _LatestEvalCard(eval: latest),
            ),
          if (evals.length > 1) ...[
            const SizedBox(height: 12),
            _LevelTrend(evals: evals.take(5).toList(growable: false)),
          ],
          if (pending > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.hourglass_top,
                    size: 15, color: LumiTokens.muted),
                const SizedBox(width: 6),
                Text(
                  pending == 1
                      ? '1 recording awaiting evaluation'
                      : '$pending recordings awaiting evaluation',
                  style:
                      LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'AI-generated — may be inaccurate. Listen to the recording and '
            'use your professional judgement.',
            style: LumiType.caption.copyWith(
              color: LumiTokens.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestEvalCard extends StatelessWidget {
  final ComprehensionEvalModel eval;

  const _LatestEvalCard({required this.eval});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        eval.logDate != null ? formatCommentDate(eval.logDate!) : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ComprehensionLevelChip(
              level: eval.overallLevel,
              status: eval.status,
            ),
            const SizedBox(width: 8),
            if (eval.confidence != null)
              Text(
                ComprehensionEvalModel.confidenceLabel(eval.confidence),
                style: LumiType.caption.copyWith(color: LumiTokens.muted),
              ),
            const Spacer(),
            Text(dateStr,
                style: LumiType.caption.copyWith(color: LumiTokens.muted)),
          ],
        ),
        if (eval.summary != null && eval.summary!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            eval.summary!,
            style: LumiType.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (eval.flags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final flag in eval.flags.take(3))
                ComprehensionFlagChip(flag: flag),
              if (eval.flags.length > 3)
                Text('+${eval.flags.length - 3}',
                    style: LumiType.caption
                        .copyWith(color: LumiTokens.muted)),
            ],
          ),
        ],
      ],
    );
  }
}

class _LevelTrend extends StatelessWidget {
  final List<ComprehensionEvalModel> evals;

  const _LevelTrend({required this.evals});

  @override
  Widget build(BuildContext context) {
    // Oldest -> newest, so the rightmost dot is the latest evaluation.
    final ordered = evals.reversed.toList(growable: false);
    return Row(
      children: [
        Text('Last ${ordered.length}: ',
            style: LumiType.caption.copyWith(color: LumiTokens.muted)),
        const SizedBox(width: 4),
        for (final e in ordered)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Tooltip(
              message: ComprehensionEvalModel.levelLabel(e.overallLevel),
              triggerMode: TooltipTriggerMode.tap,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: e.isScored
                      ? ComprehensionEvalModel.levelColor(e.overallLevel)
                      : LumiTokens.rule,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReplacedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LumiTokens.tintYellow,
        borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Recording was replaced after this evaluation',
              style: LumiType.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// Level pill shared by the section, review screen and eval sheet.
class ComprehensionLevelChip extends StatelessWidget {
  final String? level;
  final String status;

  const ComprehensionLevelChip({
    super.key,
    required this.level,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (status == 'failed') {
      label = "Couldn't evaluate";
      color = LumiTokens.muted;
    } else if (status == 'skipped') {
      label = 'Not evaluated';
      color = LumiTokens.muted;
    } else if (level == null) {
      label = 'Needs review';
      color = LumiTokens.yellow;
    } else {
      label = ComprehensionEvalModel.levelLabel(level);
      color = ComprehensionEvalModel.levelColor(level);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: LumiType.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: LumiTokens.ink,
        ),
      ),
    );
  }
}

/// Small neutral chip for a pipeline flag.
class ComprehensionFlagChip extends StatelessWidget {
  final String flag;

  const ComprehensionFlagChip({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Text(
        ComprehensionEvalModel.flagLabel(flag),
        style: LumiType.caption.copyWith(fontSize: 11),
      ),
    );
  }
}
