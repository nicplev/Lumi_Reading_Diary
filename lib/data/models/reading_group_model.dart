import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for organizing students into reading groups within a class
/// Enables teachers to manage students by ability level or interest
class ReadingGroupModel {
  final String id;
  final String classId;
  final String schoolId;
  final String name;
  final String? description;
  final String? readingLevel; // Target reading level for this group
  final List<String> studentIds;
  final String? color; // Hex color for visual identification
  final int targetMinutes; // Daily reading target for this group
  final DateTime createdAt;
  final String createdBy;
  final DateTime? updatedAt;
  final bool isActive;
  final Map<String, dynamic>? settings;

  ReadingGroupModel({
    required this.id,
    required this.classId,
    required this.schoolId,
    required this.name,
    this.description,
    this.readingLevel,
    this.studentIds = const [],
    this.color,
    this.targetMinutes = 20,
    required this.createdAt,
    required this.createdBy,
    this.updatedAt,
    this.isActive = true,
    this.settings,
  });

  factory ReadingGroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReadingGroupModel(
      id: doc.id,
      classId: data['classId'] ?? '',
      schoolId: data['schoolId'] ?? '',
      name: data['name'] ?? '',
      description: data['description'],
      readingLevel: data['readingLevel'],
      studentIds: List<String>.from(data['studentIds'] ?? []),
      color: data['color'],
      targetMinutes: data['targetMinutes'] ?? 20,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      isActive: data['isActive'] ?? true,
      settings: data['settings'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'classId': classId,
      'schoolId': schoolId,
      'name': name,
      'description': description,
      'readingLevel': readingLevel,
      'studentIds': studentIds,
      'color': color,
      'targetMinutes': targetMinutes,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isActive': isActive,
      'settings': settings,
    };
  }

  ReadingGroupModel copyWith({
    String? id,
    String? classId,
    String? schoolId,
    String? name,
    String? description,
    String? readingLevel,
    List<String>? studentIds,
    String? color,
    int? targetMinutes,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    bool? isActive,
    Map<String, dynamic>? settings,
  }) {
    return ReadingGroupModel(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      schoolId: schoolId ?? this.schoolId,
      name: name ?? this.name,
      description: description ?? this.description,
      readingLevel: readingLevel ?? this.readingLevel,
      studentIds: studentIds ?? this.studentIds,
      color: color ?? this.color,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      settings: settings ?? this.settings,
    );
  }
}

/// Statistics for a reading group
class ReadingGroupStats {
  final int totalStudents;
  final int activeReaders;
  final int totalMinutesRead;
  final double averageMinutesPerStudent;
  final int studentsMetTarget;
  final List<String> topPerformers; // Student IDs
  final List<String> needsSupport; // Student IDs

  ReadingGroupStats({
    required this.totalStudents,
    required this.activeReaders,
    required this.totalMinutesRead,
    required this.averageMinutesPerStudent,
    required this.studentsMetTarget,
    this.topPerformers = const [],
    this.needsSupport = const [],
  });

  factory ReadingGroupStats.fromMap(Map<String, dynamic> map) {
    return ReadingGroupStats(
      totalStudents: map['totalStudents'] ?? 0,
      activeReaders: map['activeReaders'] ?? 0,
      totalMinutesRead: map['totalMinutesRead'] ?? 0,
      averageMinutesPerStudent:
          (map['averageMinutesPerStudent'] ?? 0).toDouble(),
      studentsMetTarget: map['studentsMetTarget'] ?? 0,
      topPerformers: List<String>.from(map['topPerformers'] ?? []),
      needsSupport: List<String>.from(map['needsSupport'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalStudents': totalStudents,
      'activeReaders': activeReaders,
      'totalMinutesRead': totalMinutesRead,
      'averageMinutesPerStudent': averageMinutesPerStudent,
      'studentsMetTarget': studentsMetTarget,
      'topPerformers': topPerformers,
      'needsSupport': needsSupport,
    };
  }
}
