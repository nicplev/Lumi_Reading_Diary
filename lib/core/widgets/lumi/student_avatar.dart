import 'package:flutter/material.dart';

import '../../../core/characters/lumi_character.dart';
import '../../../data/models/student_model.dart';
import '../../../core/utils/image_decode.dart';

/// Renders a student's avatar.
///
/// Shows the assigned Lumi character image when [characterId] is set and
/// recognised, otherwise falls back to the existing initials circle using
/// [initial] and [avatarColor].
///
/// Use [StudentAvatar.fromStudent] to construct from a [StudentModel] — it
/// computes the initials and colour automatically.
class StudentAvatar extends StatelessWidget {
  final String? characterId;
  final String initial;
  final Color avatarColor;
  final double size;

  const StudentAvatar({
    super.key,
    required this.characterId,
    required this.initial,
    required this.avatarColor,
    this.size = 40,
  });

  /// Constructs from a [StudentModel], deriving initial and colour automatically.
  factory StudentAvatar.fromStudent(
    StudentModel student, {
    double size = 40,
    Key? key,
  }) {
    final initial = [
      student.firstName.isNotEmpty ? student.firstName[0] : '',
      student.lastName.isNotEmpty ? student.lastName[0] : '',
    ].join().toUpperCase();

    final color = _avatarColors[student.fullName.hashCode.abs() % _avatarColors.length];

    return StudentAvatar(
      key: key,
      // displayCharacterId applies any active award character (Top Reader /
      // special) over the chosen character, so the award shows everywhere this
      // factory is used — including the class kiosk.
      characterId: student.displayCharacterId,
      initial: initial,
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
    final character = LumiCharacters.findById(characterId);

    if (character != null) {
      return Image.asset(
        character.assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: decodeCacheSize(context, size),
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
