import 'package:flutter/foundation.dart';

import '../../../../data/models/class_model.dart';
import '../../../../data/models/reading_group_model.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../data/models/user_model.dart';
import 'student_achievement.dart';

/// Bag of shared dependencies passed to every dashboard widget builder.
///
/// Avoids each widget definition needing a unique set of constructor params;
/// builders pull only what they need from this context.
class DashboardWidgetContext {
  final ClassModel classModel;
  final String schoolId;
  final UserModel teacher;
  final List<StudentModel> students;
  final bool studentsLoaded;
  final ValueNotifier<int> engagementResetSignal;
  final VoidCallback onViewAllReading;

  // Shared weekly logs — fetched once, consumed by multiple widgets
  final List<ReadingLogModel> weeklyLogs;
  final bool weeklyLogsLoaded;

  // Reading groups for the current class
  final List<ReadingGroupModel> readingGroups;
  final bool readingGroupsLoaded;

  // Achievements extracted during student fetch (sorted by earnedAt desc)
  final List<StudentAchievement> recentAchievements;

  const DashboardWidgetContext({
    required this.classModel,
    required this.schoolId,
    required this.teacher,
    required this.students,
    required this.studentsLoaded,
    required this.engagementResetSignal,
    required this.onViewAllReading,
    this.weeklyLogs = const [],
    this.weeklyLogsLoaded = false,
    this.readingGroups = const [],
    this.readingGroupsLoaded = false,
    this.recentAchievements = const [],
  });
}
