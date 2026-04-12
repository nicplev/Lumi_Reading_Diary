import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/characters/lumi_character.dart';
import '../../../data/models/student_model.dart';

/// Renders a student's avatar.
///
/// Shows the assigned Lumi character SVG when [characterId] is set and
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
      characterId: student.characterId,
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
      return SvgPicture.asset(
        character.assetPath,
        width: size,
        height: size,
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
