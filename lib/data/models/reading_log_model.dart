import 'package:cloud_firestore/cloud_firestore.dart';

enum LogStatus {
  completed,
  partial,
  skipped,
  pending,
}

/// How the child felt about the reading session.
/// Maps to the 5 blob character assets in assets/blobs/.
enum ReadingFeeling {
  hard, // blob-hard.png
  tricky, // blob-tricky.png
  okay, // blob-okay.png
  good, // blob-good.png
  great, // blob-great.png
}

/// Who created the reading log.
/// `parent` is the default (and is assumed for historical logs that predate
/// this field). `teacher` indicates a proxy log entered by a teacher on
/// behalf of a student whose carer cannot use the app.
enum LoggedByRole {
  parent,
  teacher,
}

class ReadingLogModel {
  final String id;
  final String studentId;
  final String parentId;
  final String schoolId;
  final String classId;
  final DateTime date;
  final int minutesRead;
  final int targetMinutes;
  final LogStatus status;
  final List<String> bookTitles;
  final String? notes;
  final List<String>? photoUrls;
  final bool isOfflineCreated;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final String? allocationId; // Links to the allocation this fulfills
  final Map<String, dynamic>? metadata;

  // Child's self-assessment of how the reading went
  final ReadingFeeling? childFeeling;

  // Parent's comment using template chips
  final String? parentComment;
  final List<String> parentCommentSelections;
  final String? parentCommentFreeText;

  // For teacher feedback
  final String? teacherComment;
  final DateTime? commentedAt;
  final String? commentedBy;

  // Denormalized preview of the most recent comment-thread message, kept on the
  // log so history lists can show a preview and an unread badge without reading
  // the `comments` subcollection. `lastCommentByRole` is 'parent' | 'teacher'.
  final String? lastCommentPreview;
  final DateTime? lastCommentAt;
  final String? lastCommentByRole;

  // Per-user read marker for the comment thread, keyed by Firebase UID. A log is
  // "unread" for a viewer when the newest comment is from the other party and is
  // newer than that viewer's entry here.
  final Map<String, DateTime> commentsViewedAt;

  // Denormalized attribution of the guardian who logged this session.
  // Captured at create time so the display stays correct even if the
  // guardian later changes their name or relationship label.
  final String? loggedByName;
  final String? loggedByLabel;

  // Role of the creator. Null on legacy docs (treated as parent on read).
  // For teacher-proxy logs `parentId` holds the teacher's UID so existing
  // ownership rules (parentId == auth.uid) cover create/update/delete.
  final LoggedByRole? loggedByRole;

  ReadingLogModel({
    required this.id,
    required this.studentId,
    required this.parentId,
    required this.schoolId,
    required this.classId,
    required this.date,
    required this.minutesRead,
    required this.targetMinutes,
    required this.status,
    required this.bookTitles,
    this.notes,
    this.photoUrls,
    this.isOfflineCreated = false,
    required this.createdAt,
    this.syncedAt,
    this.allocationId,
    this.metadata,
    this.childFeeling,
    this.parentComment,
    this.parentCommentSelections = const [],
    this.parentCommentFreeText,
    this.teacherComment,
    this.commentedAt,
    this.commentedBy,
    this.lastCommentPreview,
    this.lastCommentAt,
    this.lastCommentByRole,
    this.commentsViewedAt = const {},
    this.loggedByName,
    this.loggedByLabel,
    this.loggedByRole,
  });

  bool get isCompleted => status == LogStatus.completed;
  bool get hasMetTarget => minutesRead >= targetMinutes;
  bool get isTeacherProxy => loggedByRole == LoggedByRole.teacher;

  /// Whether the viewer [uid] (acting as [role], 'parent' | 'teacher') has an
  /// unseen comment: there's a thread, its newest message is from the other
  /// party, and it postdates this viewer's last view.
  bool hasUnreadFor(String uid, String role) {
    if (lastCommentAt == null || lastCommentByRole == role) return false;
    final viewed = commentsViewedAt[uid];
    return viewed == null || viewed.isBefore(lastCommentAt!);
  }

  factory ReadingLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReadingLogModel(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      parentId: data['parentId'] ?? '',
      schoolId: data['schoolId'] ?? '',
      classId: data['classId'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      minutesRead: data['minutesRead'] ?? 0,
      targetMinutes: data['targetMinutes'] ?? 20,
      status: LogStatus.values.firstWhere(
        (e) => e.toString() == 'LogStatus.${data['status']}',
        orElse: () => LogStatus.pending,
      ),
      bookTitles: List<String>.from(data['bookTitles'] ?? []),
      notes: data['notes'],
      photoUrls: data['photoUrls'] != null
          ? List<String>.from(data['photoUrls'])
          : null,
      isOfflineCreated: data['isOfflineCreated'] ?? false,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      syncedAt: data['syncedAt'] != null
          ? (data['syncedAt'] as Timestamp).toDate()
          : null,
      allocationId: data['allocationId'],
      metadata: data['metadata'],
      childFeeling: data['childFeeling'] != null
          ? ReadingFeeling.values.firstWhere(
              (e) => e.toString() == 'ReadingFeeling.${data['childFeeling']}',
              orElse: () => ReadingFeeling.okay,
            )
          : null,
      parentComment: data['parentComment'],
      parentCommentSelections:
          List<String>.from(data['parentCommentSelections'] ?? []),
      parentCommentFreeText: data['parentCommentFreeText'],
      teacherComment: data['teacherComment'],
      commentedAt: data['commentedAt'] != null
          ? (data['commentedAt'] as Timestamp).toDate()
          : null,
      commentedBy: data['commentedBy'],
      lastCommentPreview: data['lastCommentPreview'],
      lastCommentAt: data['lastCommentAt'] != null
          ? (data['lastCommentAt'] as Timestamp).toDate()
          : null,
      lastCommentByRole: data['lastCommentByRole'],
      commentsViewedAt: (data['commentsViewedAt'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as Timestamp).toDate())) ??
          const {},
      loggedByName: data['loggedByName'],
      loggedByLabel: data['loggedByLabel'],
      loggedByRole: data['loggedByRole'] != null
          ? LoggedByRole.values.firstWhere(
              (e) => e.toString() == 'LoggedByRole.${data['loggedByRole']}',
              orElse: () => LoggedByRole.parent,
            )
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'parentId': parentId,
      'schoolId': schoolId,
      'classId': classId,
      'date': Timestamp.fromDate(date),
      'minutesRead': minutesRead,
      'targetMinutes': targetMinutes,
      'status': status.toString().split('.').last,
      'bookTitles': bookTitles,
      'notes': notes,
      'photoUrls': photoUrls,
      'isOfflineCreated': isOfflineCreated,
      'createdAt': Timestamp.fromDate(createdAt),
      'syncedAt': syncedAt != null ? Timestamp.fromDate(syncedAt!) : null,
      'allocationId': allocationId,
      'metadata': metadata,
      'childFeeling': childFeeling?.toString().split('.').last,
      'parentComment': parentComment,
      'parentCommentSelections': parentCommentSelections,
      'parentCommentFreeText': parentCommentFreeText,
      'teacherComment': teacherComment,
      'commentedAt':
          commentedAt != null ? Timestamp.fromDate(commentedAt!) : null,
      'commentedBy': commentedBy,
      'lastCommentPreview': lastCommentPreview,
      'lastCommentAt':
          lastCommentAt != null ? Timestamp.fromDate(lastCommentAt!) : null,
      'lastCommentByRole': lastCommentByRole,
      'commentsViewedAt': commentsViewedAt
          .map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
      'loggedByName': loggedByName,
      'loggedByLabel': loggedByLabel,
      'loggedByRole': loggedByRole?.toString().split('.').last,
    };
  }

  ReadingLogModel copyWith({
    String? id,
    String? studentId,
    String? parentId,
    String? schoolId,
    String? classId,
    DateTime? date,
    int? minutesRead,
    int? targetMinutes,
    LogStatus? status,
    List<String>? bookTitles,
    String? notes,
    List<String>? photoUrls,
    bool? isOfflineCreated,
    DateTime? createdAt,
    DateTime? syncedAt,
    String? allocationId,
    Map<String, dynamic>? metadata,
    ReadingFeeling? childFeeling,
    String? parentComment,
    List<String>? parentCommentSelections,
    String? parentCommentFreeText,
    String? teacherComment,
    DateTime? commentedAt,
    String? commentedBy,
    String? lastCommentPreview,
    DateTime? lastCommentAt,
    String? lastCommentByRole,
    Map<String, DateTime>? commentsViewedAt,
    String? loggedByName,
    String? loggedByLabel,
    LoggedByRole? loggedByRole,
  }) {
    return ReadingLogModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      parentId: parentId ?? this.parentId,
      schoolId: schoolId ?? this.schoolId,
      classId: classId ?? this.classId,
      date: date ?? this.date,
      minutesRead: minutesRead ?? this.minutesRead,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      status: status ?? this.status,
      bookTitles: bookTitles ?? this.bookTitles,
      notes: notes ?? this.notes,
      photoUrls: photoUrls ?? this.photoUrls,
      isOfflineCreated: isOfflineCreated ?? this.isOfflineCreated,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      allocationId: allocationId ?? this.allocationId,
      metadata: metadata ?? this.metadata,
      childFeeling: childFeeling ?? this.childFeeling,
      parentComment: parentComment ?? this.parentComment,
      parentCommentSelections:
          parentCommentSelections ?? this.parentCommentSelections,
      parentCommentFreeText:
          parentCommentFreeText ?? this.parentCommentFreeText,
      teacherComment: teacherComment ?? this.teacherComment,
      commentedAt: commentedAt ?? this.commentedAt,
      commentedBy: commentedBy ?? this.commentedBy,
      lastCommentPreview: lastCommentPreview ?? this.lastCommentPreview,
      lastCommentAt: lastCommentAt ?? this.lastCommentAt,
      lastCommentByRole: lastCommentByRole ?? this.lastCommentByRole,
      commentsViewedAt: commentsViewedAt ?? this.commentsViewedAt,
      loggedByName: loggedByName ?? this.loggedByName,
      loggedByLabel: loggedByLabel ?? this.loggedByLabel,
      loggedByRole: loggedByRole ?? this.loggedByRole,
    );
  }

  // For local storage with Hive
  Map<String, dynamic> toLocal() {
    return {
      'id': id,
      'studentId': studentId,
      'parentId': parentId,
      'schoolId': schoolId,
      'classId': classId,
      'date': date.toIso8601String(),
      'minutesRead': minutesRead,
      'targetMinutes': targetMinutes,
      'status': status.toString().split('.').last,
      'bookTitles': bookTitles,
      'notes': notes,
      'photoUrls': photoUrls,
      'isOfflineCreated': isOfflineCreated,
      'createdAt': createdAt.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
      'allocationId': allocationId,
      'metadata': metadata,
      'childFeeling': childFeeling?.toString().split('.').last,
      'parentComment': parentComment,
      'parentCommentSelections': parentCommentSelections,
      'parentCommentFreeText': parentCommentFreeText,
      'teacherComment': teacherComment,
      'commentedAt': commentedAt?.toIso8601String(),
      'commentedBy': commentedBy,
      'lastCommentPreview': lastCommentPreview,
      'lastCommentAt': lastCommentAt?.toIso8601String(),
      'lastCommentByRole': lastCommentByRole,
      'commentsViewedAt':
          commentsViewedAt.map((k, v) => MapEntry(k, v.toIso8601String())),
      'loggedByName': loggedByName,
      'loggedByLabel': loggedByLabel,
      'loggedByRole': loggedByRole?.toString().split('.').last,
    };
  }

  factory ReadingLogModel.fromLocal(Map<String, dynamic> map) {
    return ReadingLogModel(
      id: map['id'] ?? '',
      studentId: map['studentId'] ?? '',
      parentId: map['parentId'] ?? '',
      schoolId: map['schoolId'] ?? '',
      classId: map['classId'] ?? '',
      date: DateTime.parse(map['date']),
      minutesRead: map['minutesRead'] ?? 0,
      targetMinutes: map['targetMinutes'] ?? 20,
      status: LogStatus.values.firstWhere(
        (e) => e.toString() == 'LogStatus.${map['status']}',
        orElse: () => LogStatus.pending,
      ),
      bookTitles: List<String>.from(map['bookTitles'] ?? []),
      notes: map['notes'],
      photoUrls:
          map['photoUrls'] != null ? List<String>.from(map['photoUrls']) : null,
      isOfflineCreated: map['isOfflineCreated'] ?? true,
      createdAt: DateTime.parse(map['createdAt']),
      syncedAt:
          map['syncedAt'] != null ? DateTime.parse(map['syncedAt']) : null,
      allocationId: map['allocationId'],
      metadata: map['metadata'],
      childFeeling: map['childFeeling'] != null
          ? ReadingFeeling.values.firstWhere(
              (e) => e.toString() == 'ReadingFeeling.${map['childFeeling']}',
              orElse: () => ReadingFeeling.okay,
            )
          : null,
      parentComment: map['parentComment'],
      parentCommentSelections:
          List<String>.from(map['parentCommentSelections'] ?? []),
      parentCommentFreeText: map['parentCommentFreeText'],
      teacherComment: map['teacherComment'],
      commentedAt: map['commentedAt'] != null
          ? DateTime.parse(map['commentedAt'])
          : null,
      commentedBy: map['commentedBy'],
      lastCommentPreview: map['lastCommentPreview'],
      lastCommentAt: map['lastCommentAt'] != null
          ? DateTime.parse(map['lastCommentAt'])
          : null,
      lastCommentByRole: map['lastCommentByRole'],
      commentsViewedAt: (map['commentsViewedAt'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, DateTime.parse(v as String))) ??
          const {},
      loggedByName: map['loggedByName'],
      loggedByLabel: map['loggedByLabel'],
      loggedByRole: map['loggedByRole'] != null
          ? LoggedByRole.values.firstWhere(
              (e) => e.toString() == 'LoggedByRole.${map['loggedByRole']}',
              orElse: () => LoggedByRole.parent,
            )
          : null,
    );
  }

  /// Human-friendly attribution for "Logged by …" surfaces. Prefers the
  /// relationship label, falls back to the name, then a generic term.
  String get loggedByDisplay => loggedByLabel ?? loggedByName ?? 'Guardian';
}
