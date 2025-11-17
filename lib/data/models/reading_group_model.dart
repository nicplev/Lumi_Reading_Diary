import 'package:cloud_firestore/cloud_firestore.dart';

/// Reading Group Model - Represents a reading group within a class
///
/// Teachers create groups for differentiated instruction:
/// - Ability-based groups (e.g., "Advanced Readers", "Emerging Readers")
/// - Interest-based groups (e.g., "Fantasy Fans", "Science Explorers")
/// - Project-based groups (e.g., "Book Club 1", "Reading Buddies")
///
/// Groups can have:
/// - Custom reading goals (minutes per week, books per month)
/// - Assigned book lists
/// - Group achievements
/// - Performance tracking
class ReadingGroupModel {
  final String id;
  final String schoolId;
  final String classId;
  final String name;
  final String? description;
  final GroupType type;
  final String color; // Hex color for UI differentiation
  final List<String> studentIds;
  final GroupGoals goals;
  final GroupStats stats;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ReadingGroupModel({
    required this.id,
    required this.schoolId,
    required this.classId,
    required this.name,
    this.description,
    required this.type,
    required this.color,
    required this.studentIds,
    required this.goals,
    required this.stats,
    required this.createdAt,
    this.updatedAt,
  });

  // Firestore converters
  factory ReadingGroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return ReadingGroupModel(
      id: doc.id,
      schoolId: data['schoolId'] as String? ?? '',
      classId: data['classId'] as String? ?? '',
      name: data['name'] as String? ?? 'Unnamed Group',
      description: data['description'] as String?,
      type: GroupType.values.firstWhere(
        (e) => e.name == (data['type'] as String? ?? 'ability'),
        orElse: () => GroupType.ability,
      ),
      color: data['color'] as String? ?? '#1976D2',
      studentIds: List<String>.from(data['studentIds'] as List? ?? []),
      goals: GroupGoals.fromMap(data['goals'] as Map<String, dynamic>? ?? {}),
      stats: GroupStats.fromMap(data['stats'] as Map<String, dynamic>? ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schoolId': schoolId,
      'classId': classId,
      'name': name,
      'description': description,
      'type': type.name,
      'color': color,
      'studentIds': studentIds,
      'goals': goals.toMap(),
      'stats': stats.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  // Helper methods
  ReadingGroupModel copyWith({
    String? name,
    String? description,
    GroupType? type,
    String? color,
    List<String>? studentIds,
    GroupGoals? goals,
    GroupStats? stats,
    DateTime? updatedAt,
  }) {
    return ReadingGroupModel(
      id: id,
      schoolId: schoolId,
      classId: classId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      color: color ?? this.color,
      studentIds: studentIds ?? this.studentIds,
      goals: goals ?? this.goals,
      stats: stats ?? this.stats,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  int get memberCount => studentIds.length;

  bool containsStudent(String studentId) => studentIds.contains(studentId);

  double get goalsProgressPercentage {
    if (goals.targetMinutesPerWeek == 0) return 0;
    return (stats.weeklyMinutes / goals.targetMinutesPerWeek).clamp(0.0, 1.0);
  }
}

/// Type of reading group
enum GroupType {
  ability,    // Grouped by reading ability/level
  interest,   // Grouped by reading interests/genres
  project,    // Project or book club based
  mixed,      // Mixed ability/interest
}

/// Group goals set by teacher
class GroupGoals {
  final int targetMinutesPerWeek;
  final int targetBooksPerMonth;
  final int targetReadingDays; // Days per week goal

  GroupGoals({
    this.targetMinutesPerWeek = 0,
    this.targetBooksPerMonth = 0,
    this.targetReadingDays = 5,
  });

  factory GroupGoals.fromMap(Map<String, dynamic> map) {
    return GroupGoals(
      targetMinutesPerWeek: map['targetMinutesPerWeek'] as int? ?? 0,
      targetBooksPerMonth: map['targetBooksPerMonth'] as int? ?? 0,
      targetReadingDays: map['targetReadingDays'] as int? ?? 5,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'targetMinutesPerWeek': targetMinutesPerWeek,
      'targetBooksPerMonth': targetBooksPerMonth,
      'targetReadingDays': targetReadingDays,
    };
  }

  GroupGoals copyWith({
    int? targetMinutesPerWeek,
    int? targetBooksPerMonth,
    int? targetReadingDays,
  }) {
    return GroupGoals(
      targetMinutesPerWeek: targetMinutesPerWeek ?? this.targetMinutesPerWeek,
      targetBooksPerMonth: targetBooksPerMonth ?? this.targetBooksPerMonth,
      targetReadingDays: targetReadingDays ?? this.targetReadingDays,
    );
  }
}

/// Group statistics (aggregated from members)
class GroupStats {
  final int totalMinutes;
  final int totalBooks;
  final int weeklyMinutes;
  final int monthlyBooks;
  final int activeMembersThisWeek;
  final double averageMinutesPerMember;

  GroupStats({
    this.totalMinutes = 0,
    this.totalBooks = 0,
    this.weeklyMinutes = 0,
    this.monthlyBooks = 0,
    this.activeMembersThisWeek = 0,
    this.averageMinutesPerMember = 0.0,
  });

  factory GroupStats.fromMap(Map<String, dynamic> map) {
    return GroupStats(
      totalMinutes: map['totalMinutes'] as int? ?? 0,
      totalBooks: map['totalBooks'] as int? ?? 0,
      weeklyMinutes: map['weeklyMinutes'] as int? ?? 0,
      monthlyBooks: map['monthlyBooks'] as int? ?? 0,
      activeMembersThisWeek: map['activeMembersThisWeek'] as int? ?? 0,
      averageMinutesPerMember: (map['averageMinutesPerMember'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalMinutes': totalMinutes,
      'totalBooks': totalBooks,
      'weeklyMinutes': weeklyMinutes,
      'monthlyBooks': monthlyBooks,
      'activeMembersThisWeek': activeMembersThisWeek,
      'averageMinutesPerMember': averageMinutesPerMember,
    };
  }

  GroupStats copyWith({
    int? totalMinutes,
    int? totalBooks,
    int? weeklyMinutes,
    int? monthlyBooks,
    int? activeMembersThisWeek,
    double? averageMinutesPerMember,
  }) {
    return GroupStats(
      totalMinutes: totalMinutes ?? this.totalMinutes,
      totalBooks: totalBooks ?? this.totalBooks,
      weeklyMinutes: weeklyMinutes ?? this.weeklyMinutes,
      monthlyBooks: monthlyBooks ?? this.monthlyBooks,
      activeMembersThisWeek: activeMembersThisWeek ?? this.activeMembersThisWeek,
      averageMinutesPerMember: averageMinutesPerMember ?? this.averageMinutesPerMember,
    );
  }
}

/// Pre-defined group templates for quick setup
class GroupTemplates {
  static const List<Map<String, dynamic>> templates = [
    {
      'name': 'Advanced Readers',
      'type': 'ability',
      'color': '#4CAF50', // Green
      'description': 'Students reading above grade level',
      'goals': {
        'targetMinutesPerWeek': 150,
        'targetBooksPerMonth': 4,
        'targetReadingDays': 5,
      },
    },
    {
      'name': 'On-Level Readers',
      'type': 'ability',
      'color': '#2196F3', // Blue
      'description': 'Students reading at grade level',
      'goals': {
        'targetMinutesPerWeek': 100,
        'targetBooksPerMonth': 2,
        'targetReadingDays': 5,
      },
    },
    {
      'name': 'Emerging Readers',
      'type': 'ability',
      'color': '#FF9800', // Orange
      'description': 'Students developing reading skills',
      'goals': {
        'targetMinutesPerWeek': 75,
        'targetBooksPerMonth': 1,
        'targetReadingDays': 5,
      },
    },
    {
      'name': 'Book Club',
      'type': 'project',
      'color': '#9C27B0', // Purple
      'description': 'Students reading the same book together',
      'goals': {
        'targetMinutesPerWeek': 120,
        'targetBooksPerMonth': 1,
        'targetReadingDays': 5,
      },
    },
    {
      'name': 'Fantasy Fans',
      'type': 'interest',
      'color': '#E91E63', // Pink
      'description': 'Students who love fantasy and adventure',
      'goals': {
        'targetMinutesPerWeek': 100,
        'targetBooksPerMonth': 2,
        'targetReadingDays': 5,
      },
    },
    {
      'name': 'Non-Fiction Explorers',
      'type': 'interest',
      'color': '#00BCD4', // Cyan
      'description': 'Students interested in real-world topics',
      'goals': {
        'targetMinutesPerWeek': 100,
        'targetBooksPerMonth': 2,
        'targetReadingDays': 5,
      },
    },
  ];

  static ReadingGroupModel createFromTemplate(
    int templateIndex,
    String schoolId,
    String classId,
  ) {
    final template = templates[templateIndex];

    return ReadingGroupModel(
      id: '', // Firestore will assign
      schoolId: schoolId,
      classId: classId,
      name: template['name'] as String,
      description: template['description'] as String,
      type: GroupType.values.firstWhere((e) => e.name == template['type']),
      color: template['color'] as String,
      studentIds: [],
      goals: GroupGoals.fromMap(template['goals'] as Map<String, dynamic>),
      stats: GroupStats(),
      createdAt: DateTime.now(),
    );
  }
}
