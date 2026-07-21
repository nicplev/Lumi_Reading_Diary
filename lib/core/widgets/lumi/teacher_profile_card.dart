import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';
import 'staff_avatar.dart';
import '../../../theme/lumi_tokens.dart';

/// Profile stat data for the profile card stats row.
class ProfileStat {
  final String value;
  final String label;

  const ProfileStat({required this.value, required this.label});
}

/// Lumi Design System - Teacher Profile Card
///
/// 80px gradient avatar, name, role subtitle, and 3-stat row.
/// Per spec: 20px radius, 24px padding, card shadow.
class TeacherProfileCard extends StatelessWidget {
  final String initials;
  final String fullName;
  final String subtitle;
  final List<ProfileStat> stats;
  /// Chosen staff Lumi character id; renders in place of the initials circle.
  final String? characterId;
  /// Tap handler for the avatar (e.g. open the character picker).
  final VoidCallback? onAvatarTap;

  const TeacherProfileCard({
    super.key,
    required this.initials,
    required this.fullName,
    required this.subtitle,
    this.stats = const [],
    this.characterId,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TeacherDimensions.paddingXXL),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        children: [
          // Avatar (character if chosen, else initials circle) — tap to change.
          GestureDetector(
            onTap: onAvatarTap,
            child: StaffAvatar(
              characterId: characterId,
              initial: initials,
              avatarColor: AppColors.teacherPrimary,
              size: TeacherDimensions.avatarL,
            ),
          ),
          const SizedBox(height: 16),
          // Name
          Text(
            fullName,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: LumiTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          // Subtitle
          Text(
            subtitle,
            style: TeacherTypography.bodyMedium.copyWith(
              color: LumiTokens.muted,
            ),
            textAlign: TextAlign.center,
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 20),
            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 32),
                  _ProfileStatWidget(stat: stats[i]),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileStatWidget extends StatelessWidget {
  final ProfileStat stat;

  const _ProfileStatWidget({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          stat.value,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: LumiTokens.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stat.label,
          style: TeacherTypography.bodySmall,
        ),
      ],
    );
  }
}
