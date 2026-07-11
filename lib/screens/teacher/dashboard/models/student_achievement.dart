import '../../../../data/models/achievement_model.dart';

/// Lightweight pairing of a student's identity with an achievement they earned.
///
/// Built during the dashboard's student fetch by extracting the `achievements`
/// array from each raw Firestore document — zero additional reads.
class StudentAchievement {
  final String studentId;

  /// Display name shown on the achievement spotlight — first name plus the
  /// last-name initial (e.g. "Ari P.") so students who share a first name in a
  /// class can be told apart. See [StudentModel.firstNameWithLastInitial].
  final String studentDisplayName;
  final AchievementModel achievement;

  const StudentAchievement({
    required this.studentId,
    required this.studentDisplayName,
    required this.achievement,
  });
}
