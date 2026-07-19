import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/inline_stream_error.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../data/models/class_model.dart';
import '../../data/models/comprehension_eval_model.dart';
import '../../data/models/user_model.dart';
import '../../data/providers/comprehension_eval_providers.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import 'student_detail/comprehension_section.dart'
    show ComprehensionLevelChip;
import 'student_detail/reading_log_snapshot.dart' show formatCommentDate;
import 'widgets/comprehension_eval_sheet.dart';

enum _DateFilter { all, lastWeek, thisMonth }

/// Class-wide comprehension review: every AI evaluation for the class,
/// newest first, with date / level / needs-review filters. Dev-gated entry
/// points (teacher settings + classroom header); the section-level
/// entitlement gate hides the whole screen's data when the school is off.
class ComprehensionReviewScreen extends ConsumerStatefulWidget {
  final UserModel teacher;
  final ClassModel classModel;

  const ComprehensionReviewScreen({
    super.key,
    required this.teacher,
    required this.classModel,
  });

  @override
  ConsumerState<ComprehensionReviewScreen> createState() =>
      _ComprehensionReviewScreenState();
}

class _ComprehensionReviewScreenState
    extends ConsumerState<ComprehensionReviewScreen> {
  _DateFilter _dateFilter = _DateFilter.all;
  final Set<String> _levelFilter = {};
  bool _needsReviewOnly = false;

  ClassEvalsLookup get _lookup => ClassEvalsLookup(
        schoolId: widget.teacher.schoolId ?? '',
        classId: widget.classModel.id,
      );

  List<ComprehensionEvalModel> _applyFilters(
      List<ComprehensionEvalModel> evals) {
    final now = DateTime.now();
    return evals.where((e) {
      if (_needsReviewOnly && !e.needsReview) return false;
      if (_levelFilter.isNotEmpty &&
          !_levelFilter.contains(e.overallLevel)) {
        return false;
      }
      final date = e.logDate ?? e.evaluatedAt;
      if (date == null) return _dateFilter == _DateFilter.all;
      switch (_dateFilter) {
        case _DateFilter.all:
          return true;
        case _DateFilter.lastWeek:
          return date.isAfter(now.subtract(const Duration(days: 7)));
        case _DateFilter.thisMonth:
          return date.year == now.year && date.month == now.month;
      }
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref
        .watch(aiEvaluationEnabledProvider(widget.teacher.schoolId ?? ''));
    final evalsAsync = ref.watch(classEvalsProvider(_lookup));
    final namesAsync = ref.watch(classStudentNamesProvider(_lookup));

    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.cream,
        elevation: 0,
        foregroundColor: LumiTokens.ink,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Comprehension', style: LumiType.subhead),
            Text(
              widget.classModel.name,
              style: LumiType.caption.copyWith(color: LumiTokens.muted),
            ),
          ],
        ),
      ),
      body: !enabled
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'AI comprehension evaluation is not enabled for this '
                  'school.',
                  style: LumiType.body,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                _buildFilters(),
                Expanded(
                  child: evalsAsync.when(
                    error: (_, __) => Center(
                      child: InlineStreamError(
                        message: "Couldn't load evaluations.",
                        onRetry: () =>
                            ref.invalidate(classEvalsProvider(_lookup)),
                      ),
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    data: (evals) {
                      final filtered = _applyFilters(evals);
                      final names = namesAsync.value ?? const {};
                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            evals.isEmpty
                                ? 'No evaluations yet.\nThey appear here '
                                    'after children record comprehension '
                                    'answers.'
                                : 'Nothing matches these filters.',
                            style: LumiType.caption,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filtered.length + 1,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index == filtered.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'AI-generated assessments — may be '
                                'inaccurate. Listen to recordings and use '
                                'your professional judgement before acting.',
                                style: LumiType.caption.copyWith(
                                  color: LumiTokens.muted,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          final eval = filtered[index];
                          final name = names[eval.studentId] ?? 'Student';
                          return _EvalRow(
                            eval: eval,
                            studentName: name,
                            onTap: () => showComprehensionEvalSheet(
                              context,
                              eval: eval,
                              studentName: name,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TeacherFilterChip(
                  label: 'All',
                  isActive: _dateFilter == _DateFilter.all,
                  activeColor: LumiTokens.green,
                  onTap: () =>
                      setState(() => _dateFilter = _DateFilter.all),
                ),
                const SizedBox(width: 6),
                TeacherFilterChip(
                  label: 'Last week',
                  isActive: _dateFilter == _DateFilter.lastWeek,
                  activeColor: LumiTokens.green,
                  onTap: () =>
                      setState(() => _dateFilter = _DateFilter.lastWeek),
                ),
                const SizedBox(width: 6),
                TeacherFilterChip(
                  label: 'This month',
                  isActive: _dateFilter == _DateFilter.thisMonth,
                  activeColor: LumiTokens.green,
                  onTap: () =>
                      setState(() => _dateFilter = _DateFilter.thisMonth),
                ),
                Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: LumiTokens.rule,
                ),
                TeacherFilterChip(
                  label: 'Needs review',
                  isActive: _needsReviewOnly,
                  activeColor: LumiTokens.yellow,
                  onTap: () =>
                      setState(() => _needsReviewOnly = !_needsReviewOnly),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final level in ComprehensionEvalModel.levelOrder) ...[
                  TeacherFilterChip(
                    label: ComprehensionEvalModel.levelLabel(level),
                    isActive: _levelFilter.contains(level),
                    activeColor: ComprehensionEvalModel.levelColor(level),
                    onTap: () => setState(() {
                      if (!_levelFilter.add(level)) {
                        _levelFilter.remove(level);
                      }
                    }),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvalRow extends StatelessWidget {
  final ComprehensionEvalModel eval;
  final String studentName;
  final VoidCallback onTap;

  const _EvalRow({
    required this.eval,
    required this.studentName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = eval.logDate ?? eval.evaluatedAt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(color: LumiTokens.rule),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(studentName, style: LumiType.body),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (date != null)
                        Text(
                          formatCommentDate(date),
                          style: LumiType.caption
                              .copyWith(color: LumiTokens.muted),
                        ),
                      if (eval.flags.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.flag_outlined,
                            size: 13, color: LumiTokens.yellow),
                        const SizedBox(width: 2),
                        Text(
                          '${eval.flags.length}',
                          style: LumiType.caption
                              .copyWith(color: LumiTokens.muted),
                        ),
                      ],
                      if (eval.audioUploadedAt != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.mic_none,
                            size: 13, color: LumiTokens.muted),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ComprehensionLevelChip(
              level: eval.overallLevel,
              status: eval.status,
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: LumiTokens.muted),
          ],
        ),
      ),
    );
  }
}
