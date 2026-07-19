import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../../data/models/reading_level_option.dart';
import '../../../data/models/student_model.dart';
import '../../../services/reading_level_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'reading_log_snapshot.dart';
import 'reading_level_labels.dart';

/// "Reading Level" card on the teacher student-detail screen. Owns its
/// expanded/collapsed state locally so toggling it no longer rebuilds the
/// whole screen. Level mutations (picker, history, up/down) stay with the
/// parent, which also owns the options list.
class ReadingLevelCard extends StatefulWidget {
  final StudentModel student;
  final List<ReadingLevelOption> options;
  final ReadingLevelService readingLevelService;
  final void Function({required bool increase}) onMoveLevel;
  final VoidCallback onShowHistory;
  final VoidCallback onShowPicker;

  const ReadingLevelCard({
    super.key,
    required this.student,
    required this.options,
    required this.readingLevelService,
    required this.onMoveLevel,
    required this.onShowHistory,
    required this.onShowPicker,
  });

  @override
  State<ReadingLevelCard> createState() => _ReadingLevelCardState();
}

class _ReadingLevelCardState extends State<ReadingLevelCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final options = widget.options;
    final service = widget.readingLevelService;

    final unset = isReadingLevelUnset(student);
    final unresolved =
        isReadingLevelUnresolved(student, options: options, service: service);
    final hasResolvedLevel = !unset && !unresolved;
    final canMoveDown = hasResolvedLevel &&
        service.previousLevel(
              student.currentReadingLevel,
              options: options,
            ) !=
            null;
    final canMoveUp = hasResolvedLevel &&
        service.nextLevel(
              student.currentReadingLevel,
              options: options,
            ) !=
            null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tappable header ──────────────────────────────────────────
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Text('Reading Level', style: LumiType.subhead),
                    const SizedBox(width: 8),
                    TeacherReadingLevelPill(
                      label: readingLevelCompactLabel(
                        student,
                        options: options,
                        service: service,
                      ),
                      isUnset: unset,
                      isUnresolved: unresolved,
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: LumiTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              Divider(height: 1, color: LumiTokens.rule),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Level label + date
                    Row(
                      children: [
                        Text(
                          readingLevelDisplayLabel(
                            student,
                            options: options,
                            service: service,
                          ),
                          style: LumiType.body.copyWith(
                            color: LumiTokens.muted,
                          ),
                        ),
                        if (student.readingLevelUpdatedAt != null) ...[
                          Text(
                            '  ·  Updated ${formatCommentDate(student.readingLevelUpdatedAt!)}',
                            style: LumiType.caption,
                          ),
                        ],
                      ],
                    ),

                    // Unresolved level warning
                    if (unresolved) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.07),
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          'Legacy level — pick a new level to fix.',
                          style: LumiType.caption.copyWith(
                            color: LumiTokens.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // ── Action row ───────────────────────────────────────
                    Row(
                      children: [
                        _CompactLevelButton(
                          icon: Icons.keyboard_arrow_down_rounded,
                          label: 'Down',
                          onPressed: canMoveDown
                              ? () => widget.onMoveLevel(increase: false)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        _CompactLevelButton(
                          icon: Icons.keyboard_arrow_up_rounded,
                          label: 'Up',
                          onPressed: canMoveUp
                              ? () => widget.onMoveLevel(increase: true)
                              : null,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: widget.onShowHistory,
                          style: TextButton.styleFrom(
                            foregroundColor: LumiTokens.muted,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -2,
                            ),
                            textStyle: LumiType.caption,
                          ),
                          child: const Text('History'),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          onPressed: widget.onShowPicker,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: LumiTokens.green,
                            foregroundColor: LumiTokens.paper,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            elevation: 0,
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -2,
                            ),
                            textStyle: LumiType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusMedium),
                            ),
                          ),
                          child: const Text('Change Level'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactLevelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _CompactLevelButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            onPressed != null ? LumiTokens.green : LumiTokens.muted,
        side: BorderSide(
          color: onPressed != null
              ? LumiTokens.green.withValues(alpha: 0.35)
              : LumiTokens.rule,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        textStyle: LumiType.caption.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        ),
      ),
    );
  }
}
