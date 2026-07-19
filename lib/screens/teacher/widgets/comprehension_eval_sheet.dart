import 'package:flutter/material.dart';

import '../../../core/widgets/audio/comprehension_audio_player.dart';
import '../../../data/models/comprehension_eval_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../student_detail/comprehension_section.dart'
    show ComprehensionLevelChip, ComprehensionFlagChip;
import '../student_detail/reading_log_snapshot.dart' show formatCommentDate;

/// Opens the full evaluation detail bottom sheet for one AI comprehension
/// evaluation: question asked, recording player, transcript, per-criterion
/// evidence and flags — always framed as decision support, never a grade.
Future<void> showComprehensionEvalSheet(
  BuildContext context, {
  required ComprehensionEvalModel eval,
  required String studentName,
  bool questionMayHaveChanged = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ComprehensionEvalSheet(
      eval: eval,
      studentName: studentName,
    ),
  );
}

class ComprehensionEvalSheet extends StatelessWidget {
  final ComprehensionEvalModel eval;
  final String studentName;

  const ComprehensionEvalSheet({
    super.key,
    required this.eval,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
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
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(studentName, style: LumiType.subhead),
                          if (eval.logDate != null)
                            Text(
                              formatCommentDate(eval.logDate!),
                              style: LumiType.caption
                                  .copyWith(color: LumiTokens.muted),
                            ),
                        ],
                      ),
                    ),
                    ComprehensionLevelChip(
                      level: eval.overallLevel,
                      status: eval.status,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    _disclaimer(),
                    const SizedBox(height: 14),
                    if (eval.questionTextUsed != null) ...[
                      _sectionTitle('Question asked'),
                      Text(eval.questionTextUsed!, style: LumiType.body),
                      if (eval.questionSource != null &&
                          eval.questionSource != 'log')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'The class question may have changed since this '
                            'recording was made.',
                            style: LumiType.caption
                                .copyWith(color: LumiTokens.muted),
                          ),
                        ),
                      const SizedBox(height: 14),
                    ],
                    if (eval.audioUploadedAt != null) ...[
                      _sectionTitle('Recording'),
                      ComprehensionAudioPlayer(
                        storagePath: 'schools/${eval.schoolId}/'
                            'comprehension_audio/${eval.logId}.m4a',
                        schoolId: eval.schoolId,
                        logId: eval.logId,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _sectionTitle('Transcript'),
                    if (eval.transcript != null &&
                        eval.transcript!.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: LumiTokens.cream,
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                        ),
                        child: Text(eval.transcript!, style: LumiType.body),
                      )
                    else
                      Text(
                        eval.transcriptRemovedAt != null
                            ? 'Transcript removed after the retention period.'
                            : 'No transcript available.',
                        style:
                            LumiType.caption.copyWith(color: LumiTokens.muted),
                      ),
                    const SizedBox(height: 14),
                    if (eval.summary != null && eval.summary!.isNotEmpty) ...[
                      _sectionTitle('AI summary'),
                      Text(eval.summary!, style: LumiType.body),
                      const SizedBox(height: 14),
                    ],
                    if (eval.criterionScores.isNotEmpty) ...[
                      _sectionTitle('What the response showed'),
                      for (final criterion in eval.criterionScores)
                        _CriterionRow(criterion: criterion),
                      const SizedBox(height: 14),
                    ],
                    if (eval.flags.isNotEmpty) ...[
                      _sectionTitle('Flags'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final flag in eval.flags)
                            ComprehensionFlagChip(flag: flag),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: LumiType.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: LumiTokens.muted,
        ),
      ),
    );
  }

  Widget _disclaimer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LumiTokens.tintBlue,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      child: Text(
        'AI-generated assessment — may be inaccurate. Listen to the '
        'recording and use your professional judgement before acting.',
        style: LumiType.caption,
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  final CriterionScore criterion;

  const _CriterionRow({required this.criterion});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(criterion.label, style: LumiType.body)),
              for (int i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i < criterion.score
                          ? LumiTokens.green
                          : LumiTokens.rule,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          if (criterion.evidence.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '“${criterion.evidence}”',
                style: LumiType.caption.copyWith(color: LumiTokens.muted),
              ),
            ),
        ],
      ),
    );
  }
}
