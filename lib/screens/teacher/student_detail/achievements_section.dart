import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/achievements/achievement_presentation.dart';
import '../../../data/models/achievement_model.dart';
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
  final VoidCallback onOpenAchievements;

  const AchievementsSection({
    super.key,
    required this.firestore,
    required this.schoolId,
    required this.studentId,
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined,
                        size: 20, color: LumiTokens.muted),
                    const SizedBox(width: 8),
                    Text(
                      'No achievements yet',
                      style: LumiType.caption,
                    ),
                  ],
                ),
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
                    return GestureDetector(
                      onTap: widget.onOpenAchievements,
                      child: Container(
                        width: 72,
                        decoration: BoxDecoration(
                          color: LumiTokens.paper,
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                          border: Border.all(
                            color: Color(template.effectiveColor)
                                .withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(template.effectiveColor)
                                  .withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              achievementIconFor(template),
                              size: 28,
                              color: achievementCategoryColor(
                                template.category,
                              ),
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
