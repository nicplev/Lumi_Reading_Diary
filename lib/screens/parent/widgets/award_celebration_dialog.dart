import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/characters/lumi_character.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../data/models/student_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../core/utils/image_decode.dart';

/// Remembers which award celebrations a parent has already seen, so the
/// on-open modal fires exactly once per distinct award. Keyed by student +
/// award identity (the week for the weekly Top Reader award; the awarded-at
/// stamp for a teacher's special award).
class AwardCelebrationStore {
  AwardCelebrationStore._();

  static const _prefsKey = 'parent_award_celebrated_keys';
  static const _cap = 60;

  /// A stable key for a child's currently-active award, or null if the child
  /// has no active award. Manual (special) awards take precedence over the
  /// weekly auto award, matching [StudentModel.displayCharacterId].
  static String? keyFor(StudentModel child) {
    final manual = child.manualAward;
    if (manual != null) {
      final stamp = manual.awardedAt?.millisecondsSinceEpoch;
      return '${child.id}:manual:${stamp ?? manual.name}';
    }
    final auto = child.autoAward;
    if (auto != null) {
      final stamp = auto.awardedAt?.millisecondsSinceEpoch;
      return '${child.id}:auto:${auto.weekOf ?? stamp ?? auto.name}';
    }
    return null;
  }

  static Future<bool> isCelebrated(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? const <String>[]).contains(key);
  }

  static Future<void> markCelebrated(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? <String>[];
    if (list.contains(key)) return;
    list.add(key);
    // Bound growth — keep only the most recent keys.
    if (list.length > _cap) {
      list.removeRange(0, list.length - _cap);
    }
    await prefs.setStringList(_prefsKey, list);
  }
}

/// Shows the award celebration modal for [child], which must currently hold an
/// active award. Completes when the parent dismisses it.
Future<void> showAwardCelebrationDialog(
  BuildContext context, {
  required StudentModel child,
}) {
  HapticFeedback.mediumImpact();
  final isTopReader = child.manualAward == null && child.autoAward != null;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _AwardCelebrationDialog(
      childName: child.firstName,
      awardName: child.activeAwardName ?? 'a reading award',
      characterId: child.displayCharacterId,
      isTopReader: isTopReader,
    ),
  );
}

class _AwardCelebrationDialog extends StatelessWidget {
  const _AwardCelebrationDialog({
    required this.childName,
    required this.awardName,
    required this.characterId,
    required this.isTopReader,
  });

  final String childName;
  final String awardName;
  final String? characterId;
  final bool isTopReader;

  @override
  Widget build(BuildContext context) {
    // Orange (not yellow) for the weekly award so the white-text button keeps
    // enough contrast; purple for a teacher's special award.
    final accent = isTopReader ? LumiTokens.orange : LumiTokens.purple;
    final asset = LumiCharacters.findById(characterId)?.assetPath;

    return Dialog(
      backgroundColor: LumiTokens.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 6),
            Text(
              isTopReader ? 'Reader of the Week!' : 'A special award!',
              style: LumiType.subhead.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .shimmer(
                  duration: 1800.ms,
                  color: accent.withValues(alpha: 0.5),
                ),
            const SizedBox(height: 16),
            Container(
              width: 136,
              height: 136,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.28),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: asset != null
                  ? Image.asset(
                      asset,
                      width: 110,
                      cacheWidth: decodeCacheSize(context, 110),
                      height: 110,
                      fit: BoxFit.contain,
                    )
                  : Icon(Icons.emoji_events_rounded, size: 76, color: accent),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.06, 1.06),
                  duration: 1200.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 16),
            Text(
              '$childName earned "$awardName"!',
              style: LumiType.subhead,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isTopReader
                  ? '$childName read the most minutes in class last week. '
                      'Give them a big cheer and keep the reading going!'
                  : "$childName's teacher gave them a special award. "
                      'Celebrate their reading and keep it up!',
              style: LumiType.body.copyWith(
                color: LumiTokens.muted,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            LumiPrimaryButton(
              onPressed: () => Navigator.of(context).pop(),
              text: 'Celebrate 🎉',
              color: accent,
              isFullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}
