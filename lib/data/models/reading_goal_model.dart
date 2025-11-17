import 'package:cloud_firestore/cloud_firestore.dart';

/// Type of reading goal
enum GoalType {
  dailyMinutes, // Read X minutes per day
  weeklyMinutes, // Read X minutes per week
  monthlyMinutes, // Read X minutes per month
  dailyStreak, // Maintain X day streak
  booksToRead, // Read X books
  pagesPerDay, // Read X pages per day
  custom, // Custom goal
}

/// Status of a goal
enum GoalStatus {
  active, // Currently working on
  completed, // Goal achieved
  failed, // Goal not met and expired
  paused, // Temporarily paused
}

/// Model for student reading goals
/// Allows students to set personal targets and track progress
class ReadingGoalModel {
  final String id;
  final String studentId;
  final String schoolId;
  final GoalType type;
  final String title;
  final String? description;
  final int targetValue; // Target to achieve
  final int currentValue; // Current progress
  final DateTime startDate;
  final DateTime endDate;
  final GoalStatus status;
  final DateTime? completedAt;
  final String? rewardMessage; // Message shown when goal is achieved
  final String? parentMessage; // Message for parent
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  ReadingGoalModel({
    required this.id,
    required this.studentId,
    required this.schoolId,
    required this.type,
    required this.title,
    this.description,
    required this.targetValue,
    this.currentValue = 0,
    required this.startDate,
    required this.endDate,
    this.status = GoalStatus.active,
    this.completedAt,
    this.rewardMessage,
    this.parentMessage,
    required this.createdAt,
    this.metadata,
  });

  /// Calculate progress percentage
  double get progressPercentage {
    if (targetValue == 0) return 0.0;
    return (currentValue / targetValue).clamp(0.0, 1.0);
  }

  /// Check if goal is achieved
  bool get isAchieved => currentValue >= targetValue;

  /// Check if goal is expired
  bool get isExpired => DateTime.now().isAfter(endDate);

  /// Get days remaining
  int get daysRemaining {
    final now = DateTime.now();
    if (now.isAfter(endDate)) return 0;
    return endDate.difference(now).inDays;
  }

  /// Get days elapsed
  int get daysElapsed {
    final now = DateTime.now();
    return now.difference(startDate).inDays;
  }

  factory ReadingGoalModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReadingGoalModel(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      schoolId: data['schoolId'] ?? '',
      type: GoalType.values.firstWhere(
        (e) => e.toString() == 'GoalType.${data['type']}',
        orElse: () => GoalType.custom,
      ),
      title: data['title'] ?? '',
      description: data['description'],
      targetValue: data['targetValue'] ?? 0,
      currentValue: data['currentValue'] ?? 0,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      status: GoalStatus.values.firstWhere(
        (e) => e.toString() == 'GoalStatus.${data['status']}',
        orElse: () => GoalStatus.active,
      ),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
      rewardMessage: data['rewardMessage'],
      parentMessage: data['parentMessage'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'schoolId': schoolId,
      'type': type.toString().split('.').last,
      'title': title,
      'description': description,
      'targetValue': targetValue,
      'currentValue': currentValue,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status.toString().split('.').last,
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'rewardMessage': rewardMessage,
      'parentMessage': parentMessage,
      'createdAt': Timestamp.fromDate(createdAt),
      'metadata': metadata,
    };
  }

  ReadingGoalModel copyWith({
    String? id,
    String? studentId,
    String? schoolId,
    GoalType? type,
    String? title,
    String? description,
    int? targetValue,
    int? currentValue,
    DateTime? startDate,
    DateTime? endDate,
    GoalStatus? status,
    DateTime? completedAt,
    String? rewardMessage,
    String? parentMessage,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return ReadingGoalModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      schoolId: schoolId ?? this.schoolId,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      targetValue: targetValue ?? this.targetValue,
      currentValue: currentValue ?? this.currentValue,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      rewardMessage: rewardMessage ?? this.rewardMessage,
      parentMessage: parentMessage ?? this.parentMessage,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Helper to get human-readable goal type
  String get typeLabel {
    switch (type) {
      case GoalType.dailyMinutes:
        return 'Daily Minutes';
      case GoalType.weeklyMinutes:
        return 'Weekly Minutes';
      case GoalType.monthlyMinutes:
        return 'Monthly Minutes';
      case GoalType.dailyStreak:
        return 'Reading Streak';
      case GoalType.booksToRead:
        return 'Books to Read';
      case GoalType.pagesPerDay:
        return 'Daily Pages';
      case GoalType.custom:
        return 'Custom Goal';
    }
  }

  /// Helper to get value unit
  String get valueUnit {
    switch (type) {
      case GoalType.dailyMinutes:
      case GoalType.weeklyMinutes:
      case GoalType.monthlyMinutes:
        return 'minutes';
      case GoalType.dailyStreak:
        return 'days';
      case GoalType.booksToRead:
        return 'books';
      case GoalType.pagesPerDay:
        return 'pages';
      case GoalType.custom:
        return '';
    }
  }
}

/// Predefined goal templates
class GoalTemplate {
  final String title;
  final String description;
  final GoalType type;
  final int targetValue;
  final int durationDays;

  GoalTemplate({
    required this.title,
    required this.description,
    required this.type,
    required this.targetValue,
    required this.durationDays,
  });

  static List<GoalTemplate> get templates => [
        GoalTemplate(
          title: 'Read Every Day This Week',
          description: 'Build a 7-day reading streak',
          type: GoalType.dailyStreak,
          targetValue: 7,
          durationDays: 7,
        ),
        GoalTemplate(
          title: 'Read 100 Minutes This Week',
          description: 'Hit 100 minutes of reading in 7 days',
          type: GoalType.weeklyMinutes,
          targetValue: 100,
          durationDays: 7,
        ),
        GoalTemplate(
          title: 'Finish 3 Books This Month',
          description: 'Complete 3 books in 30 days',
          type: GoalType.booksToRead,
          targetValue: 3,
          durationDays: 30,
        ),
        GoalTemplate(
          title: 'Read 20 Minutes Daily',
          description: 'Meet your daily reading target for 30 days',
          type: GoalType.dailyMinutes,
          targetValue: 20,
          durationDays: 30,
        ),
        GoalTemplate(
          title: 'Build a 30-Day Streak',
          description: 'Read every day for an entire month',
          type: GoalType.dailyStreak,
          targetValue: 30,
          durationDays: 30,
        ),
        GoalTemplate(
          title: 'Read 500 Minutes This Month',
          description: 'Achieve 500 total minutes in 30 days',
          type: GoalType.monthlyMinutes,
          targetValue: 500,
          durationDays: 30,
        ),
      ];
}
