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

  /// Materialised, fail-closed access verdict for the current academic year.
  /// Written exclusively server-side (renewal callable, subscription trigger,
  /// rollover cron, link redemption). Clients and security rules read it but
  /// never write it. Null on legacy documents predating the access model —
  /// treated as "no access" (fail-closed) by [hasActiveAccess].
  final StudentAccess? access;

  final List<ReadingLevelHistory> levelHistory;
  final StudentStats? stats;

  /// Ids of achievements the student has earned (from the `achievements` array
  /// written by the `detectAchievements`/`backfillAchievements` functions).
  /// Used to render earned vs locked badges and to compute next-goal progress.
  final List<String> earnedAchievementIds;
  // Denormalized name + relationship label for each linked guardian, keyed by
  // parent UID. Maintained server-side by the syncGuardianProfiles Cloud
  // Function — never written by clients. Lets a guardian see who else is
  // linked (name only) without read access to other parent docs.
  final Map<String, GuardianProfile> guardianProfiles;

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
    this.access,
    this.levelHistory = const [],
    this.stats,
    this.earnedAchievementIds = const [],
    this.guardianProfiles = const {},
  });

  bool get isEnrolled =>
      enrollmentStatus == 'book_pack' || enrollmentStatus == 'direct_purchase';

  /// Whether the student currently has live, unexpired access. Fail-closed:
  /// a null [access] (legacy doc) or a non-active/expired status returns false.
  bool get hasActiveAccess => access?.isActive ?? false;

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
          (data['additionalInfo']
              as Map<String, dynamic>?)?['pendingParentEmail'],
      access: data['access'] != null
          ? StudentAccess.fromMap(
              Map<String, dynamic>.from(data['access'] as Map))
          : null,
      levelHistory: (data['levelHistory'] as List<dynamic>?)
              ?.map((item) => ReadingLevelHistory.fromMap(item))
              .toList() ??
          [],
      stats: data['stats'] != null ? StudentStats.fromMap(data['stats']) : null,
      earnedAchievementIds: (data['achievements'] as List<dynamic>?)
              ?.map((a) =>
                  (a is Map ? a['id'] : null) is String ? a['id'] as String : null)
              .whereType<String>()
              .toList() ??
          const [],
      guardianProfiles: (data['guardianProfiles'] as Map<String, dynamic>?)
              ?.map((uid, value) => MapEntry(
                  uid,
                  GuardianProfile.fromMap(
                      Map<String, dynamic>.from(value as Map)))) ??
          const {},
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
      // Included so a full-document write round-trips the map; the server
      // (renewal/subscription/rollover functions) is the authoritative writer.
      if (access != null) 'access': access!.toMap(),
      'levelHistory': levelHistory.map((e) => e.toMap()).toList(),
      'stats': stats?.toMap(),
      // Included so a full-document write round-trips the map; the
      // syncGuardianProfiles Cloud Function is the authoritative writer.
      'guardianProfiles':
          guardianProfiles.map((uid, p) => MapEntry(uid, p.toMap())),
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
    StudentAccess? access,
    List<ReadingLevelHistory>? levelHistory,
    StudentStats? stats,
    List<String>? earnedAchievementIds,
    Map<String, GuardianProfile>? guardianProfiles,
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
      access: access ?? this.access,
      levelHistory: levelHistory ?? this.levelHistory,
      stats: stats ?? this.stats,
      earnedAchievementIds: earnedAchievementIds ?? this.earnedAchievementIds,
      guardianProfiles: guardianProfiles ?? this.guardianProfiles,
    );
  }
}

/// Minimal projection of a linked guardian, denormalized onto the student doc.
/// Deliberately carries name + relationship label only — never email/phone.
class GuardianProfile {
  final String name;
  final String? relationshipLabel;

  GuardianProfile({
    required this.name,
    this.relationshipLabel,
  });

  factory GuardianProfile.fromMap(Map<String, dynamic> map) {
    return GuardianProfile(
      name: map['name'] ?? '',
      relationshipLabel: map['relationshipLabel'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'relationshipLabel': relationshipLabel,
    };
  }

  /// Display string preferring the relationship label.
  String get display => relationshipLabel ?? name;
}

/// Materialised, fail-closed access verdict for a student. Mirrors the
/// `student.access` map written server-side. See the access model in
/// the licensing/lifecycle plan. The single source of truth for whether a
/// parent may log reading or view content for this child.
class StudentAccess {
  /// Live access. Anything other than `active` (or a passed [expiresAt])
  /// means the child is gated.
  static const String statusActive = 'active';
  static const String statusExpired = 'expired';
  static const String statusSuspended = 'suspended';

  final String status;

  /// Calendar year the AU school-year STARTS (e.g. 2026 for the 2026 year).
  final int academicYear;

  /// Absolute hard boundary (~31 Jan of the following year). Access lapses at
  /// this instant even if no server job runs — the date is the backstop.
  final DateTime? expiresAt;

  /// Where the grant came from: school_renewal | book_pack_assumed |
  /// parent_direct | comp.
  final String? source;
  final DateTime? grantedAt;
  final String? grantedBy;

  StudentAccess({
    required this.status,
    required this.academicYear,
    this.expiresAt,
    this.source,
    this.grantedAt,
    this.grantedBy,
  });

  /// Fail-closed: live only when status is active AND the hard expiry has not
  /// passed. A missing [expiresAt] is treated as expired.
  bool get isActive {
    if (status != statusActive) return false;
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isBefore(exp);
  }

  factory StudentAccess.fromMap(Map<String, dynamic> map) {
    return StudentAccess(
      status: map['status'] as String? ?? statusExpired,
      academicYear: (map['academicYear'] as num?)?.toInt() ?? 0,
      expiresAt: map['expiresAt'] != null
          ? (map['expiresAt'] as Timestamp).toDate()
          : null,
      source: map['source'] as String?,
      grantedAt: map['grantedAt'] != null
          ? (map['grantedAt'] as Timestamp).toDate()
          : null,
      grantedBy: map['grantedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'academicYear': academicYear,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      if (source != null) 'source': source,
      if (grantedAt != null) 'grantedAt': Timestamp.fromDate(grantedAt!),
      if (grantedBy != null) 'grantedBy': grantedBy,
    };
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
  /// Default streak freezes a student starts with, and the cap they can hold.
  /// Retained only for back-compat reads of old documents; see the deprecated
  /// freeze fields below.
  static const int defaultStreakFreezes = 2;

  final int totalMinutesRead;
  final int totalBooksRead;

  /// Gentle, forgiving streak (server-computed). Tolerates up to 2 missed days
  /// before resetting — a single missed night never resets it to zero. Earns no
  /// rewards; it's a secondary momentum signal, not the hero metric.
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastReadingDate;
  final double averageMinutesPerDay;

  /// Cumulative count of distinct nights read — the hero metric and the basis
  /// for all rewards. Monotonic: it only ever increases.
  final int totalReadingDays;

  // ─── Rolling "rhythm" + rest days (server-computed) ──────────────
  /// Distinct nights read in the last 30 days — a forgiving, sliding "rhythm"
  /// count for the "X of the last 30 nights" framing. Null when not computed.
  final int? last30DaysCount;

  /// Distinct nights read in the last 50 days. Null when not computed.
  final int? last50DaysCount;

  /// Rest days remaining in the current streak (2 minus missed days already
  /// bridged). Derived server-side; null on documents predating the rewrite.
  final int? restDaysRemaining;

  // ─── Deprecated: streak-freeze economy (replaced by rest-day tolerance) ──
  // These fields are no longer written or surfaced. The earn/spend freeze
  // economy was replaced by stateless rest-day tolerance in the streak
  // calculation (see functions/src/dateUtils.ts computeGentleStreak). They
  // remain only so [fromMap] of historical documents keeps working.
  /// Deprecated. Unused freezes on legacy documents.
  final int streakFreezesAvailable;

  /// Deprecated. Lifetime freezes consumed on legacy documents.
  final int streakFreezesUsed;

  /// Deprecated. When the most recent legacy freeze was earned.
  final DateTime? streakFreezeLastEarnedDate;

  /// Rest days left in the current streak (0 when none), back-compat safe.
  int get restDaysLeft => restDaysRemaining ?? 0;

  StudentStats({
    this.totalMinutesRead = 0,
    this.totalBooksRead = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastReadingDate,
    this.averageMinutesPerDay = 0,
    this.totalReadingDays = 0,
    this.last30DaysCount,
    this.last50DaysCount,
    this.restDaysRemaining,
    this.streakFreezesAvailable = defaultStreakFreezes,
    this.streakFreezesUsed = 0,
    this.streakFreezeLastEarnedDate,
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
      last30DaysCount: map['last30DaysCount'],
      last50DaysCount: map['last50DaysCount'],
      restDaysRemaining: map['restDaysRemaining'],
      // Null-safe defaults keep legacy (pre-rewrite) documents readable.
      streakFreezesAvailable:
          map['streakFreezesAvailable'] ?? defaultStreakFreezes,
      streakFreezesUsed: map['streakFreezesUsed'] ?? 0,
      streakFreezeLastEarnedDate: map['streakFreezeLastEarnedDate'] != null
          ? (map['streakFreezeLastEarnedDate'] as Timestamp).toDate()
          : null,
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
      'last30DaysCount': last30DaysCount,
      'last50DaysCount': last50DaysCount,
      'restDaysRemaining': restDaysRemaining,
      'streakFreezesAvailable': streakFreezesAvailable,
      'streakFreezesUsed': streakFreezesUsed,
      'streakFreezeLastEarnedDate': streakFreezeLastEarnedDate != null
          ? Timestamp.fromDate(streakFreezeLastEarnedDate!)
          : null,
    };
  }
}
