import 'package:flutter/material.dart';

import '../../../core/characters/staff_lumi_character.dart';
import '../../../data/models/user_model.dart';

/// Renders a staff member's avatar — the staff counterpart of [StudentAvatar].
///
/// Shows the assigned staff Lumi character image when [characterId] is set and
/// recognised, otherwise falls back to an initials circle using [initial] and
/// [avatarColor].
///
/// Use [StaffAvatar.fromUser] to construct from a [UserModel] — it computes the
/// initials and colour automatically.
class StaffAvatar extends StatelessWidget {
  final String? characterId;
  final String initial;
  final Color avatarColor;
  final double size;

  const StaffAvatar({
    super.key,
    required this.characterId,
    required this.initial,
    required this.avatarColor,
    this.size = 40,
  });

  /// Constructs from a [UserModel], deriving initial and colour automatically.
  factory StaffAvatar.fromUser(UserModel user, {double size = 40, Key? key}) {
    final parts =
        user.fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initial = parts.take(2).map((p) => p[0]).join().toUpperCase();

    final color = _avatarColors[user.fullName.hashCode.abs() % _avatarColors.length];

    return StaffAvatar(
      key: key,
      characterId: user.characterId,
      initial: initial.isEmpty ? '?' : initial,
      avatarColor: color,
      size: size,
    );
  }

  static const List<Color> _avatarColors = [
    Color(0xFFFFCDD2), // pink
    Color(0xFFBBDEFB), // blue
    Color(0xFFC8E6C9), // green
    Color(0xFFFFE0B2), // orange
    Color(0xFFE1BEE7), // purple
    Color(0xFFB2EBF2), // cyan
  ];

  @override
  Widget build(BuildContext context) {
    final character = StaffLumiCharacters.findById(characterId);

    if (character != null) {
      return Image.asset(
        character.assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: avatarColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
