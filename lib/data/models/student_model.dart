import 'package:cloud_firestore/cloud_firestore.dart';

class StudentModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? studentId; // School's student ID
  final String schoolId;
  final String classId;
  final String? currentReadingLevel;
  final int? currentReadingLevelIndex;
  final DateTime? readingLevelUpdatedAt;
  final String? readingLevelUpdatedBy;
  final String? readingLevelSource;
  final List<String> parentIds;
  final DateTime? dateOfBirth;
  final String? profileImageUrl;
  final String? characterId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? enrolledAt;
  final Map<String, dynamic>? additionalInfo;
  final String? enrollmentStatus;
  final String? parentEmail;
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
    this.currentReadingLevelIndex,
    this.readingLevelUpdatedAt,
    this.readingLevelUpdatedBy,
    this.readingLevelSource,
    this.parentIds = const [],
    this.dateOfBirth,
    this.profileImageUrl,
    this.characterId,
    this.isActive = true,
    required this.createdAt,
    this.enrolledAt,
    this.additionalInfo,
    this.enrollmentStatus,
    this.parentEmail,
    this.levelHistory = const [],
    this.stats,
  });

  bool get isEnrolled =>
      enrollmentStatus == 'book_pack' ||
      enrollmentStatus == 'direct_purchase';

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
      currentReadingLevelIndex:
          (data['currentReadingLevelIndex'] as num?)?.toInt(),
      readingLevelUpdatedAt: data['readingLevelUpdatedAt'] != null
          ? (data['readingLevelUpdatedAt'] as Timestamp).toDate()
          : null,
      readingLevelUpdatedBy: data['readingLevelUpdatedBy'],
      readingLevelSource: data['readingLevelSource'],
      parentIds: List<String>.from(data['parentIds'] ?? []),
      dateOfBirth: data['dateOfBirth'] != null
          ? (data['dateOfBirth'] as Timestamp).toDate()
          : null,
      profileImageUrl: data['profileImageUrl'],
      characterId: data['characterId'] as String?,
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      enrolledAt: data['enrolledAt'] != null
          ? (data['enrolledAt'] as Timestamp).toDate()
          : null,
      additionalInfo: data['additionalInfo'],
      enrollmentStatus: data['enrollmentStatus'],
      parentEmail: data['parentEmail'] ??
          (data['additionalInfo'] as Map<String, dynamic>?)?['pendingParentEmail'],
      levelHistory: (data['levelHistory'] as List<dynamic>?)
              ?.map((item) => ReadingLevelHistory.fromMap(item))
              .toList() ??
          [],
      stats: data['stats'] != null ? StudentStats.fromMap(data['stats']) : null,
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
      'currentReadingLevelIndex': currentReadingLevelIndex,
      'readingLevelUpdatedAt': readingLevelUpdatedAt != null
          ? Timestamp.fromDate(readingLevelUpdatedAt!)
          : null,
      'readingLevelUpdatedBy': readingLevelUpdatedBy,
      'readingLevelSource': readingLevelSource,
      'parentIds': parentIds,
      'dateOfBirth':
          dateOfBirth != null ? Timestamp.fromDate(dateOfBirth!) : null,
      'profileImageUrl': profileImageUrl,
      if (characterId != null) 'characterId': characterId,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'enrolledAt': enrolledAt != null ? Timestamp.fromDate(enrolledAt!) : null,
      'additionalInfo': additionalInfo,
      'enrollmentStatus': enrollmentStatus,
      'parentEmail': parentEmail,
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
    int? currentReadingLevelIndex,
    DateTime? readingLevelUpdatedAt,
    String? readingLevelUpdatedBy,
    String? readingLevelSource,
    List<String>? parentIds,
    DateTime? dateOfBirth,
    String? profileImageUrl,
    String? characterId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? enrolledAt,
    Map<String, dynamic>? additionalInfo,
    String? enrollmentStatus,
    String? parentEmail,
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
      currentReadingLevelIndex:
          currentReadingLevelIndex ?? this.currentReadingLevelIndex,
      readingLevelUpdatedAt:
          readingLevelUpdatedAt ?? this.readingLevelUpdatedAt,
      readingLevelUpdatedBy:
          readingLevelUpdatedBy ?? this.readingLevelUpdatedBy,
      readingLevelSource: readingLevelSource ?? this.readingLevelSource,
      parentIds: parentIds ?? this.parentIds,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      characterId: characterId ?? this.characterId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      enrolledAt: enrolledAt ?? this.enrolledAt,
      additionalInfo: additionalInfo ?? this.additionalInfo,
      enrollmentStatus: enrollmentStatus ?? this.enrollmentStatus,
      parentEmail: parentEmail ?? this.parentEmail,
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
      changedAt: (map['changedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
      'lastReadingDate':
          lastReadingDate != null ? Timestamp.fromDate(lastReadingDate!) : null,
      'averageMinutesPerDay': averageMinutesPerDay,
      'totalReadingDays': totalReadingDays,
    };
  }
}
