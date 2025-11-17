import 'package:cloud_firestore/cloud_firestore.dart';

/// Student Goal Model - Represents personal reading goals set by students/parents
///
/// Goals can be:
/// - Time-based (read X minutes per day/week)
/// - Book-based (finish X books per month)
/// - Streak-based (maintain X day streak)
/// - Custom goals
class StudentGoalModel {
  final String id;
  final String studentId;
  final String schoolId;
  final GoalType type;
  final String title;
  final String? description;
  final int targetValue;
  final int currentValue;
  final GoalPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final bool isCompleted;
  final DateTime? completedAt;
  final String? reward; // Optional reward description
  final DateTime createdAt;

  StudentGoalModel({
    required this.id,
    required this.studentId,
    required this.schoolId,
    required this.type,
    required this.title,
    this.description,
    required this.targetValue,
    required this.currentValue,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.isCompleted,
    this.completedAt,
    this.reward,
    required this.createdAt,
  });

  factory StudentGoalModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return StudentGoalModel(
      id: doc.id,
      studentId: data['studentId'] as String? ?? '',
      schoolId: data['schoolId'] as String? ?? '',
      type: GoalType.values.firstWhere(
        (e) => e.name == (data['type'] as String? ?? 'minutes'),
        orElse: () => GoalType.minutes,
      ),
      title: data['title'] as String? ?? 'My Reading Goal',
      description: data['description'] as String?,
      targetValue: data['targetValue'] as int? ?? 0,
      currentValue: data['currentValue'] as int? ?? 0,
      period: GoalPeriod.values.firstWhere(
        (e) => e.name == (data['period'] as String? ?? 'weekly'),
        orElse: () => GoalPeriod.weekly,
      ),
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 7)),
      isCompleted: data['isCompleted'] as bool? ?? false,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      reward: data['reward'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'schoolId': schoolId,
      'type': type.name,
      'title': title,
      'description': description,
      'targetValue': targetValue,
      'currentValue': currentValue,
      'period': period.name,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isCompleted': isCompleted,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'reward': reward,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  StudentGoalModel copyWith({
    int? currentValue,
    bool? isCompleted,
    DateTime? completedAt,
  }) {
    return StudentGoalModel(
      id: id,
      studentId: studentId,
      schoolId: schoolId,
      type: type,
      title: title,
      description: description,
      targetValue: targetValue,
      currentValue: currentValue ?? this.currentValue,
      period: period,
      startDate: startDate,
      endDate: endDate,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      reward: reward,
      createdAt: createdAt,
    );
  }

  double get progressPercentage {
    if (targetValue == 0) return 0;
    return (currentValue / targetValue).clamp(0.0, 1.0);
  }

  int get daysRemaining {
    return endDate.difference(DateTime.now()).inDays;
  }

  bool get isExpired => DateTime.now().isAfter(endDate);
}

enum GoalType {
  minutes, // Total minutes read
  books, // Books completed
  streak, // Consecutive days
  days, // Number of reading days
}

enum GoalPeriod {
  daily,
  weekly,
  monthly,
  custom,
}

/// Pre-defined goal templates for quick setup
class GoalTemplates {
  static const List<Map<String, dynamic>> templates = [
    {
      'title': 'Read 20 Minutes Daily',
      'type': 'minutes',
      'period': 'daily',
      'targetValue': 20,
      'description': 'Build a daily reading habit',
    },
    {
      'title': 'Finish 2 Books This Month',
      'type': 'books',
      'period': 'monthly',
      'targetValue': 2,
      'description': 'Complete 2 books in 30 days',
    },
    {
      'title': '7 Day Reading Streak',
      'type': 'streak',
      'period': 'weekly',
      'targetValue': 7,
      'description': 'Read every day for a week',
    },
    {
      'title': 'Read 100 Minutes This Week',
      'type': 'minutes',
      'period': 'weekly',
      'targetValue': 100,
      'description': 'Hit 100 minutes of reading',
    },
  ];
}
