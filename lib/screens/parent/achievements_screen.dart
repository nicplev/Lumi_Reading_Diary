import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lumi_reading_tracker/data/models/achievement_model.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/theme/lumi_tokens.dart';
import 'package:lumi_reading_tracker/theme/lumi_typography.dart';
import 'package:lumi_reading_tracker/theme/section_theme.dart';
import 'package:lumi_reading_tracker/core/widgets/glass/glass_achievement_card.dart';

/// Achievements screen — a calm, grouped view of every badge a child can earn.
///
/// Earned badges light up in their rarity colour; locked badges sit quietly
/// with an inline progress hint. Streak badges are intentionally absent: the
/// reward engine no longer awards them (see [AchievementTemplates] and
/// detectAchievements in functions/src/index.ts), so showing un-earnable
/// badges would be misleading. The 30-night rhythm grid lives on the Progress
/// screen, not here.
class AchievementsScreen extends StatefulWidget {
  final String studentId;
  final String schoolId;

  const AchievementsScreen({
    super.key,
    required this.studentId,
    required this.schoolId,
  });

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

/// Display order + labels + icons for the badge groups (no emoji — unified
/// Material icons, coloured by category). Streak is deliberately omitted.
const _groups = <({AchievementCategory category, String label, IconData icon})>[
  (category: AchievementCategory.readingDays, label: 'Reading Nights', icon: Icons.nightlight_round),
  (category: AchievementCategory.books, label: 'Books', icon: Icons.menu_book_rounded),
  (category: AchievementCategory.minutes, label: 'Reading Time', icon: Icons.schedule_rounded),
  (category: AchievementCategory.special, label: 'Special', icon: Icons.star_rounded),
];

// Warm accents not in the core token palette (gold/amber read as "reward/time").
const _goldAccent = Color(0xFFE0A93B);
const _amberAccent = Color(0xFFF59E0B);

/// Relevant, good-contrast colour per category — used for both the section
/// header icon and its badge icons (the rarity colour stays on the earned
/// card's border + check).
Color _categoryColor(AchievementCategory category) {
  switch (category) {
    case AchievementCategory.readingDays:
      return LumiTokens.blue;
    case AchievementCategory.books:
      return LumiTokens.green;
    case AchievementCategory.minutes:
      return _amberAccent;
    case AchievementCategory.special:
      return LumiTokens.red;
    default:
      return LumiTokens.muted;
  }
}

/// A unified Material icon per badge (by stable id, with a category fallback
/// for any custom/unknown achievement).
IconData _achievementIcon(AchievementModel t) {
  switch (t.id) {
    case 'days_t1':
      return Icons.bedtime_rounded;
    case 'days_t2':
      return Icons.nightlight_round;
    case 'days_t3':
      return Icons.dark_mode_rounded;
    case 'days_t4':
      return Icons.calendar_month_rounded;
    case 'books_t1':
      return Icons.menu_book_rounded;
    case 'books_t2':
      return Icons.auto_stories_rounded;
    case 'books_t3':
      return Icons.local_library_rounded;
    case 'books_t4':
      return Icons.library_books_rounded;
    case 'books_t5':
      return Icons.workspace_premium_rounded;
    case 'minutes_t1':
      return Icons.schedule_rounded;
    case 'minutes_t2':
      return Icons.update_rounded;
    case 'minutes_t3':
      return Icons.directions_run_rounded;
    case 'minutes_t4':
      return Icons.hourglass_bottom_rounded;
    case 'minutes_t5':
      return Icons.all_inclusive_rounded;
    case 'first_log':
      return Icons.flag_rounded;
  }
  switch (t.category) {
    case AchievementCategory.readingDays:
      return Icons.nightlight_round;
    case AchievementCategory.books:
      return Icons.menu_book_rounded;
    case AchievementCategory.minutes:
      return Icons.schedule_rounded;
    case AchievementCategory.special:
      return Icons.star_rounded;
    default:
      return Icons.emoji_events_rounded;
  }
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  AchievementThresholds _thresholds = AchievementThresholds.defaults;
  AchievementCustomization _customization = AchievementCustomization.empty;

  @override
  void initState() {
    super.initState();
    _loadThresholds();
  }

  Future<void> _loadThresholds() async {
    try {
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .get();
      final settings = schoolDoc.data()?['settings'] as Map<String, dynamic>?;
      final rawThresholds = settings?['achievementThresholds'] as Map<String, dynamic>?;
      final rawCustomization = settings?['achievementCustomization'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          if (rawThresholds != null) _thresholds = AchievementThresholds.fromMap(rawThresholds);
          if (rawCustomization != null) {
            _customization = AchievementCustomization.fromMap(rawCustomization);
          }
        });
      }
    } catch (_) {
      // Fall back to defaults silently — thresholds always have a safe default.
    }
  }

  @override
  Widget build(BuildContext context) {
    return LumiSectionScope(
      section: LumiSectionTheme.library,
      child: Scaffold(
        backgroundColor: LumiTokens.cream,
        appBar: AppBar(
          backgroundColor: LumiTokens.cream,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: LumiTokens.ink),
          title: Text('Achievements', style: LumiType.subhead),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('students')
              .doc(widget.studentId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorState(snapshot.error.toString());
            if (!snapshot.hasData) return const _LoadingState();
            if (!snapshot.data!.exists) {
              return const _ErrorState('Student data not found');
            }

            final student = StudentModel.fromFirestore(snapshot.data!);
            final stats = student.stats;

            final raw = (snapshot.data!.data() as Map<String, dynamic>?)?['achievements']
                    as List<dynamic>? ??
                const [];
            final earnedById = <String, AchievementModel>{
              for (final a in raw)
                (a['id'] as String? ?? ''):
                    AchievementModel.fromMap(Map<String, dynamic>.from(a)),
            };

            // Build displayable templates (streak excluded — never awarded).
            final templates = AchievementTemplates
                .generateTemplates(_thresholds, customization: _customization)
                .where((t) => t.category != AchievementCategory.streak)
                .toList();

            final earnedCount =
                templates.where((t) => earnedById.containsKey(t.id)).length;

            // Closest-to-unlocking locked badges — the motivating "next goal".
            final almost = templates
                .where((t) => !earnedById.containsKey(t.id))
                .map((t) {
                  final p = _progressFor(t, stats);
                  final frac = p.required <= 0
                      ? 0.0
                      : (p.current / p.required).clamp(0.0, 1.0);
                  return (template: t, progress: p, fraction: frac);
                })
                .where((e) => e.fraction > 0 && e.fraction < 1)
                .toList()
              ..sort((a, b) => b.fraction.compareTo(a.fraction));
            final almostThere = almost.take(3).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _HeroCard(earned: earnedCount, total: templates.length),
                const SizedBox(height: 16),
                if (almostThere.isNotEmpty) ...[
                  _AlmostThereSection(
                    items: almostThere,
                    onTap: (t) => _showLockedSheet(t, _progressFor(t, stats)),
                  ),
                  const SizedBox(height: 20),
                ],
                for (final group in _groups) ...[
                  ..._buildGroup(group, templates, earnedById, stats),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildGroup(
    ({AchievementCategory category, String label, IconData icon}) group,
    List<AchievementModel> templates,
    Map<String, AchievementModel> earnedById,
    StudentStats? stats,
  ) {
    final items = templates.where((t) => t.category == group.category).toList();
    if (items.isEmpty) return const [];

    final earnedInGroup = items.where((t) => earnedById.containsKey(t.id)).length;

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Row(
          children: [
            Icon(group.icon, size: 20, color: _categoryColor(group.category)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.label,
                style: LumiType.subhead.copyWith(fontSize: 18),
              ),
            ),
            Text('$earnedInGroup/${items.length}', style: LumiType.caption),
          ],
        ),
      ),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
        children: [
          for (final t in items)
            _BadgeTile(
              template: t,
              earned: earnedById[t.id],
              progress: _progressFor(t, stats),
              onTap: () => _onTapBadge(t, earnedById[t.id], stats),
            ),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  /// Current / required for the badge's requirement type. Streak is never
  /// reached here because streak badges aren't displayed.
  ({int current, int required}) _progressFor(
      AchievementModel t, StudentStats? stats) {
    final current = switch (t.requirementType) {
      'books' => stats?.totalBooksRead ?? 0,
      'minutes' => stats?.totalMinutesRead ?? 0,
      'days' => stats?.totalReadingDays ?? 0,
      _ => 0,
    };
    return (current: current, required: t.requiredValue);
  }

  void _onTapBadge(
      AchievementModel template, AchievementModel? earned, StudentStats? stats) {
    if (earned != null) {
      // Enrich with the live template name/colour, then celebrate.
      showDialog(
        context: context,
        builder: (_) => AchievementUnlockPopup(
          achievement: earned.copyWith(
            name: template.name,
            customColor: template.customColor,
          ),
          icon: _achievementIcon(template),
          iconColor: Colors.white,
        ),
      );
      return;
    }
    _showLockedSheet(template, _progressFor(template, stats));
  }

  void _showLockedSheet(AchievementModel t, ({int current, int required}) p) {
    final fraction =
        p.required <= 0 ? 0.0 : (p.current / p.required).clamp(0.0, 1.0);
    final accent = context.sectionTheme.accent;

    showModalBottomSheet(
      context: context,
      backgroundColor: LumiTokens.paper,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusXL)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Row(
              children: [
                Opacity(
                  opacity: 0.55,
                  child: Icon(
                    _achievementIcon(t),
                    size: 40,
                    color: _categoryColor(t.category),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(t.name, style: LumiType.heading.copyWith(fontSize: 22)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(t.description, style: LumiType.body),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 10,
                backgroundColor: LumiTokens.rule,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${p.current} of ${p.required} • ${(fraction * 100).round()}%',
              style: LumiType.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// Flat bento tile — paper surface, hairline rule border, no shadow. The
/// surface used across the migrated Lumi parent flows.
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

/// Top-of-screen summary. Doubles as the empty state when nothing is earned.
class _HeroCard extends StatelessWidget {
  final int earned;
  final int total;

  const _HeroCard({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    final accent = context.sectionTheme.accent;
    final fraction = total <= 0 ? 0.0 : (earned / total).clamp(0.0, 1.0);
    final remaining = total - earned;
    final subtitle = earned == 0
        ? 'Keep reading to unlock your first badge.'
        : earned >= total
            ? 'Every badge unlocked — amazing!'
            : '$remaining more to collect — keep it up!';

    return _bentoCard(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.emoji_events_rounded,
                  size: 32, color: _goldAccent),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$earned', style: LumiType.heading),
                      TextSpan(
                        text: ' of $total unlocked',
                        style: LumiType.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 10,
                    backgroundColor: LumiTokens.rule,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle, style: LumiType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single badge in the grid — lit up when earned, quietly progressing when not.
class _BadgeTile extends StatelessWidget {
  final AchievementModel template;
  final AchievementModel? earned;
  final ({int current, int required}) progress;
  final VoidCallback onTap;

  const _BadgeTile({
    required this.template,
    required this.earned,
    required this.progress,
    required this.onTap,
  });

  // Subtly recessed locked surface, derived from tokens (no raw hex): a faint
  // rule wash over the cream canvas so locked tiles read as "not yet earned".
  static final Color _lockedBg = Color.alphaBlend(
    LumiTokens.rule.withValues(alpha: 0.4),
    LumiTokens.cream,
  );

  @override
  Widget build(BuildContext context) {
    final isEarned = earned != null;
    final color = Color(template.effectiveColor);
    final fraction = progress.required <= 0
        ? 0.0
        : (progress.current / progress.required).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          // Earned cards read as a reward: brighter paper, a stronger accent
          // border, a soft shadow, and a corner check badge.
          color: isEarned ? LumiTokens.paper : _lockedBg,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(
            color: isEarned ? color.withValues(alpha: 0.7) : LumiTokens.rule,
            width: isEarned ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: isEarned ? 1.0 : 0.4,
                  child: Icon(
                    _achievementIcon(template),
                    size: 34,
                    color: _categoryColor(template.category),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  template.name,
                  style: LumiType.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isEarned ? LumiTokens.ink : LumiTokens.muted,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (isEarned)
                  Text(
                    'Unlocked',
                    style: LumiType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  )
                else ...[
                  _MiniProgress(
                      fraction: fraction, accent: context.sectionTheme.accent),
                  const SizedBox(height: 4),
                  // Numerical progress so the goal is concrete (and not
                  // communicated by colour alone).
                  Text(
                    '${progress.current}/${progress.required}',
                    style: LumiType.caption
                        .copyWith(fontSize: 11, color: LumiTokens.muted),
                  ),
                ],
              ],
            ),
            if (isEarned)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.check_circle_rounded, size: 20, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// Slim progress bar shown under locked badges.
class _MiniProgress extends StatelessWidget {
  final double fraction;
  final Color accent;

  const _MiniProgress({required this.fraction, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 5,
          backgroundColor: LumiTokens.rule,
          valueColor: AlwaysStoppedAnimation(accent.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}

/// "Almost there" — the closest-to-unlocking badges, surfaced near the top so
/// there's always a concrete next goal to read toward.
class _AlmostThereSection extends StatelessWidget {
  final List<
      ({
        AchievementModel template,
        ({int current, int required}) progress,
        double fraction,
      })> items;
  final void Function(AchievementModel) onTap;

  const _AlmostThereSection({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = context.sectionTheme.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4, left: 2),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  size: 20, color: _amberAccent),
              const SizedBox(width: 8),
              Text('Almost there',
                  style: LumiType.subhead.copyWith(fontSize: 18)),
            ],
          ),
        ),
        _bentoCard(
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Divider(height: 20, color: LumiTokens.rule),
                InkWell(
                  onTap: () => onTap(items[i].template),
                  borderRadius:
                      BorderRadius.circular(LumiTokens.radiusMedium),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _achievementIcon(items[i].template),
                          size: 26,
                          color: _categoryColor(items[i].template.category),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                items[i].template.name,
                                style: LumiType.body
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: items[i].fraction,
                                  minHeight: 6,
                                  backgroundColor: LumiTokens.rule,
                                  valueColor: AlwaysStoppedAnimation(accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${items[i].progress.current}/'
                          '${items[i].progress.required}',
                          style: LumiType.caption
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(color: context.sectionTheme.accent),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: LumiTokens.muted),
            const SizedBox(height: 12),
            Text('Couldn’t load achievements',
                style: LumiType.subhead, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: LumiType.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
