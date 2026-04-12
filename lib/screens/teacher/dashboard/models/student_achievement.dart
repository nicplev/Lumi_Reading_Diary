import '../../../../data/models/achievement_model.dart';

/// Lightweight pairing of a student's identity with an achievement they earned.
///
/// Built during the dashboard's student fetch by extracting the `achievements`
/// array from each raw Firestore document — zero additional reads.
class StudentAchievement {
  final String studentId;
  final String studentFirstName;
  final AchievementModel achievement;

  const StudentAchievement({
    required this.studentId,
    required this.studentFirstName,
    required this.achievement,
  });
}
