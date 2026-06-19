import 'package:flutter/material.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Lumi Design System - Stats Card
///
/// Three headline metrics for a child's reading: cumulative nights, the current
/// streak, and total read time. Each sits on a soft tinted icon tile with a
/// semantic colour (nights = blue/moon, streak = orange/flame, time =
/// green/clock) so the meaning reads at a glance.
class StatsCard extends StatelessWidget {
  final int currentStreak;
  final int totalNights;
  final int totalMinutes;

  /// Rest days remaining in the current streak (0–2). When exactly one has been
  /// used, a small footer reassures the parent the streak is still protected.
  final int? restDaysRemaining;

  const StatsCard({
    super.key,
    required this.currentStreak,
    required this.totalNights,
    required this.totalMinutes,
    this.restDaysRemaining,
  });

  static String _formatTime(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    return '${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    final restDays = restDaysRemaining ?? 2;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatColumn(
                    icon: Icons.nightlight_round,
                    tint: LumiTokens.tintBlue,
                    iconColor: LumiTokens.blue,
                    value: totalNights.toString(),
                    label: 'Nights',
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _StatColumn(
                    icon: Icons.local_fire_department_rounded,
                    tint: LumiTokens.tintOrange,
                    iconColor: LumiTokens.orange,
                    value: currentStreak.toString(),
                    label: 'Streak',
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _StatColumn(
                    icon: Icons.schedule_rounded,
                    tint: LumiTokens.tintGreen,
                    iconColor: LumiTokens.green,
                    value: _formatTime(totalMinutes),
                    label: 'Read time',
                  ),
                ),
              ],
            ),
          ),
          if (currentStreak > 0 && restDays == 1) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: LumiTokens.tintGreen,
                borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              ),
              child: Text(
                '🌙 1 rest day left — your streak is safe',
                style: LumiType.caption.copyWith(color: LumiTokens.ink),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 1, thickness: 1, color: LumiTokens.rule);
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String value;
  final String label;

  const _StatColumn({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(height: LumiTokens.space2),
        Text(value, style: LumiType.numberLarge.copyWith(fontSize: 30)),
        const SizedBox(height: 2),
        Text(label, style: LumiType.caption, textAlign: TextAlign.center),
      ],
    );
  }
}
