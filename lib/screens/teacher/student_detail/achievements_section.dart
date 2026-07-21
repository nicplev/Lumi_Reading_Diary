import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/achievements/achievement_presentation.dart';
import '../../../data/models/achievement_model.dart';
import '../../../data/models/student_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// "Achievements" row on the teacher student-detail screen. Owns its one-shot
/// fetch of the student doc's achievements array; re-fires when the student
/// changes (mirrors the screen's original didUpdateWidget semantics).
/// Navigation stays with the parent via [onOpenAchievements].
class AchievementsSection extends StatefulWidget {
  final FirebaseFirestore firestore;
  final String schoolId;
  final String studentId;
  final StudentModel student;
  final VoidCallback onOpenAchievements;

  const AchievementsSection({
    super.key,
    required this.firestore,
    required this.schoolId,
    required this.studentId,
    required this.student,
    required this.onOpenAchievements,
  });

  @override
  State<AchievementsSection> createState() => _AchievementsSectionState();
}

class _AchievementsSectionState extends State<AchievementsSection> {
  late Future<List<EarnedAchievementDisplay>> _achievementsFuture;

  @override
  void initState() {
    super.initState();
    _achievementsFuture = _loadStudentAchievementDisplays();
  }

  @override
  void didUpdateWidget(covariant AchievementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId ||
        oldWidget.schoolId != widget.schoolId) {
      _achievementsFuture = _loadStudentAchievementDisplays();
    }
  }

  Future<List<EarnedAchievementDisplay>>
      _loadStudentAchievementDisplays() async {
    try {
      final doc = await widget.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .doc(widget.studentId)
          .get();
      final data = doc.data();
      if (data == null) return [];
      final raw = data['achievements'] as List<dynamic>? ?? [];
      final earnedById = earnedAchievementMap(
        raw.map((a) => AchievementModel.fromMap(Map<String, dynamic>.from(a))),
      );
      return earnedAchievementDisplays(earnedById: earnedById);
    } catch (e) {
      debugPrint('Error loading student achievements: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EarnedAchievementDisplay>>(
      future: _achievementsFuture,
      builder: (context, snapshot) {
        final achievements = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.waiting &&
            achievements.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Achievements', style: LumiType.subhead),
                if (achievements.isNotEmpty)
                  GestureDetector(
                    onTap: widget.onOpenAchievements,
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
            const SizedBox(height: 8),
            if (achievements.isEmpty)
              _NextMilestoneCard(
                student: widget.student,
                onTap: widget.onOpenAchievements,
              )
            else
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: achievements.length > 8 ? 8 : achievements.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final display = achievements[index];
                    final template = display.template;
                    final accent = Color(template.effectiveColor);
                    return GestureDetector(
                      onTap: widget.onOpenAchievements,
                      child: Container(
                        width: 88,
                        decoration: BoxDecoration(
                          color: Color.lerp(accent, LumiTokens.paper, 0.88),
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              achievementIconFor(template),
                              size: 28,
                              color: accent,
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                template.name,
                                style: LumiType.caption.copyWith(fontSize: 9),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NextMilestoneCard extends StatelessWidget {
  final StudentModel student;
  final VoidCallback onTap;

  const _NextMilestoneCard({required this.student, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final candidate = _nextMilestone(student);
    final achievement = candidate.achievement;
    final progress = candidate.current / achievement.requiredValue;
    final remaining = achievement.requiredValue - candidate.current;
    final unit = switch (achievement.requirementType) {
      'books' => 'book${remaining == 1 ? '' : 's'}',
      'minutes' => 'minute${remaining == 1 ? '' : 's'}',
      _ => 'reading night${remaining == 1 ? '' : 's'}',
    };

    return Semantics(
      button: true,
      label: 'Next milestone: ${achievement.name}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: LumiTokens.cream,
              borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
              border: Border.all(color: LumiTokens.rule),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: LumiTokens.tintYellow,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    achievementIconFor(achievement),
                    size: 22,
                    color: LumiTokens.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXT MILESTONE',
                        style: LumiType.sectionLabel.copyWith(
                          color: LumiTokens.orange,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        achievement.name,
                        style: LumiType.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$remaining more $unit to go',
                        style: LumiType.caption.copyWith(
                          color: LumiTokens.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusPill),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 5,
                          color: LumiTokens.yellow,
                          backgroundColor: LumiTokens.rule,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: LumiTokens.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({AchievementModel achievement, int current}) _nextMilestone(
      StudentModel student) {
    final stats = student.stats;
    final currentForRequirement = <String, int>{
      'books': stats?.totalBooksRead ?? 0,
      'minutes': stats?.totalMinutesRead ?? 0,
      'days': stats?.totalReadingDays ?? 0,
    };
    final candidates = AchievementTemplates.defaultTemplates.where((template) {
      if (template.requirementType != 'days' &&
          template.requirementType != 'minutes') {
        return false;
      }
      if (student.earnedAchievementIds.contains(template.id)) return false;
      final current = currentForRequirement[template.requirementType];
      return current != null && current < template.requiredValue;
    }).toList();
    candidates.sort((a, b) {
      final aProgress =
          currentForRequirement[a.requirementType]! / a.requiredValue;
      final bProgress =
          currentForRequirement[b.requirementType]! / b.requiredValue;
      return bProgress.compareTo(aProgress);
    });
    final next = candidates.isNotEmpty
        ? candidates.first
        : AchievementTemplates.defaultTemplates.firstWhere(
            (template) => template.requirementType == 'days',
          );
    return (
      achievement: next,
      current: currentForRequirement[next.requirementType] ?? 0,
    );
  }
}
