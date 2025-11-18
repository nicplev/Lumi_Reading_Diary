import 'package:cloud_firestore/cloud_firestore.dart';

class StudentModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? studentId; // School's student ID
  final String schoolId;
  final String classId;
  final String? currentReadingLevel;
  final List<String> parentIds;
  final DateTime? dateOfBirth;
  final String? profileImageUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? enrolledAt;
  final Map<String, dynamic>? additionalInfo;
  final List<ReadingLevelHistory> levelHistory;
  final StudentStats? stats;

  StudentModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.studentId,
    required this.schoolId,
    required this.classId,
    this.currentReadingLevel,
    this.parentIds = const [],
    this.dateOfBirth,
    this.profileImageUrl,
    this.isActive = true,
    required this.createdAt,
    this.enrolledAt,
    this.additionalInfo,
    this.levelHistory = const [],
    this.stats,
  });

  String get fullName => '$firstName $lastName';

  factory StudentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StudentModel(
      id: doc.id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      studentId: data['studentId'],
      schoolId: data['schoolId'] ?? '',
      classId: data['classId'] ?? '',
      currentReadingLevel: data['currentReadingLevel'],
      parentIds: List<String>.from(data['parentIds'] ?? []),
      dateOfBirth: data['dateOfBirth'] != null
          ? (data['dateOfBirth'] as Timestamp).toDate()
          : null,
      profileImageUrl: data['profileImageUrl'],
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      enrolledAt: data['enrolledAt'] != null
          ? (data['enrolledAt'] as Timestamp).toDate()
          : null,
      additionalInfo: data['additionalInfo'],
      levelHistory: (data['levelHistory'] as List<dynamic>?)
              ?.map((item) => ReadingLevelHistory.fromMap(item))
              .toList() ??
          [],
      stats: data['stats'] != null
          ? StudentStats.fromMap(data['stats'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'studentId': studentId,
      'schoolId': schoolId,
      'classId': classId,
      'currentReadingLevel': currentReadingLevel,
      'parentIds': parentIds,
      'dateOfBirth': dateOfBirth != null
          ? Timestamp.fromDate(dateOfBirth!)
          : null,
      'profileImageUrl': profileImageUrl,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'enrolledAt': enrolledAt != null
          ? Timestamp.fromDate(enrolledAt!)
          : null,
      'additionalInfo': additionalInfo,
      'levelHistory': levelHistory.map((e) => e.toMap()).toList(),
      'stats': stats?.toMap(),
    };
  }

  StudentModel copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? studentId,
    String? schoolId,
    String? classId,
    String? currentReadingLevel,
    List<String>? parentIds,
    DateTime? dateOfBirth,
    String? profileImageUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? enrolledAt,
    Map<String, dynamic>? additionalInfo,
    List<ReadingLevelHistory>? levelHistory,
    StudentStats? stats,
  }) {
    return StudentModel(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      studentId: studentId ?? this.studentId,
      schoolId: schoolId ?? this.schoolId,
      classId: classId ?? this.classId,
      currentReadingLevel: currentReadingLevel ?? this.currentReadingLevel,
      parentIds: parentIds ?? this.parentIds,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      enrolledAt: enrolledAt ?? this.enrolledAt,
      additionalInfo: additionalInfo ?? this.additionalInfo,
      levelHistory: levelHistory ?? this.levelHistory,
      stats: stats ?? this.stats,
    );
  }
}

class ReadingLevelHistory {
  final String level;
  final DateTime changedAt;
  final String changedBy;
  final String? reason;

  ReadingLevelHistory({
    required this.level,
    required this.changedAt,
    required this.changedBy,
    this.reason,
  });

  factory ReadingLevelHistory.fromMap(Map<String, dynamic> map) {
    return ReadingLevelHistory(
      level: map['level'] ?? '',
      changedAt: (map['changedAt'] as Timestamp).toDate(),
      changedBy: map['changedBy'] ?? '',
      reason: map['reason'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'level': level,
      'changedAt': Timestamp.fromDate(changedAt),
      'changedBy': changedBy,
      'reason': reason,
    };
  }
}

class StudentStats {
  final int totalMinutesRead;
  final int totalBooksRead;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastReadingDate;
  final double averageMinutesPerDay;
  final int totalReadingDays;

  StudentStats({
    this.totalMinutesRead = 0,
    this.totalBooksRead = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastReadingDate,
    this.averageMinutesPerDay = 0,
    this.totalReadingDays = 0,
  });

  factory StudentStats.fromMap(Map<String, dynamic> map) {
    return StudentStats(
      totalMinutesRead: map['totalMinutesRead'] ?? 0,
      totalBooksRead: map['totalBooksRead'] ?? 0,
      currentStreak: map['currentStreak'] ?? 0,
      longestStreak: map['longestStreak'] ?? 0,
      lastReadingDate: map['lastReadingDate'] != null
          ? (map['lastReadingDate'] as Timestamp).toDate()
          : null,
      averageMinutesPerDay: (map['averageMinutesPerDay'] ?? 0).toDouble(),
      totalReadingDays: map['totalReadingDays'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalMinutesRead': totalMinutesRead,
      'totalBooksRead': totalBooksRead,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastReadingDate': lastReadingDate != null
          ? Timestamp.fromDate(lastReadingDate!)
          : null,
      'averageMinutesPerDay': averageMinutesPerDay,
      'totalReadingDays': totalReadingDays,
    };
  }
}