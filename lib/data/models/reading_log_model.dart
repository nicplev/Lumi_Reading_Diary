import 'package:cloud_firestore/cloud_firestore.dart';

enum LogStatus {
  completed,
  partial,
  skipped,
  pending,
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

  // For teacher feedback
  final String? teacherComment;
  final DateTime? commentedAt;
  final String? commentedBy;

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
    this.teacherComment,
    this.commentedAt,
    this.commentedBy,
  });

  bool get isCompleted => status == LogStatus.completed;
  bool get hasMetTarget => minutesRead >= targetMinutes;

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
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      syncedAt: data['syncedAt'] != null
          ? (data['syncedAt'] as Timestamp).toDate()
          : null,
      allocationId: data['allocationId'],
      metadata: data['metadata'],
      teacherComment: data['teacherComment'],
      commentedAt: data['commentedAt'] != null
          ? (data['commentedAt'] as Timestamp).toDate()
          : null,
      commentedBy: data['commentedBy'],
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
      'teacherComment': teacherComment,
      'commentedAt': commentedAt != null
          ? Timestamp.fromDate(commentedAt!)
          : null,
      'commentedBy': commentedBy,
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
    String? teacherComment,
    DateTime? commentedAt,
    String? commentedBy,
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
      teacherComment: teacherComment ?? this.teacherComment,
      commentedAt: commentedAt ?? this.commentedAt,
      commentedBy: commentedBy ?? this.commentedBy,
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
      'teacherComment': teacherComment,
      'commentedAt': commentedAt?.toIso8601String(),
      'commentedBy': commentedBy,
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
      photoUrls: map['photoUrls'] != null
          ? List<String>.from(map['photoUrls'])
          : null,
      isOfflineCreated: map['isOfflineCreated'] ?? true,
      createdAt: DateTime.parse(map['createdAt']),
      syncedAt: map['syncedAt'] != null
          ? DateTime.parse(map['syncedAt'])
          : null,
      allocationId: map['allocationId'],
      metadata: map['metadata'],
      teacherComment: map['teacherComment'],
      commentedAt: map['commentedAt'] != null
          ? DateTime.parse(map['commentedAt'])
          : null,
      commentedBy: map['commentedBy'],
    );
  }
}