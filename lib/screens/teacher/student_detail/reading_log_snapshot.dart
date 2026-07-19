import 'package:cloud_firestore/cloud_firestore.dart';

/// Lightweight reading-log row model shared by the student-detail sections
/// (recent reading, latest parent comment, assigned books). Extracted from the
/// screen's former private `_ReadingLogSnapshot` unchanged.
class ReadingLogSnapshot {
  final String id;
  final DateTime date;
  final DateTime createdAt;
  final String? allocationId;
  final List<String> bookTitles;
  final String status;
  final int minutesRead;
  final int targetMinutes;
  final String? notes;
  final String? parentId;
  final String? parentComment;
  final List<String> parentCommentSelections;
  final String? parentCommentFreeText;
  final String? childFeeling;
  // Comprehension recording fields denormalized from the reading log doc.
  // [comprehensionAudioPath] is the Storage object path; the player resolves
  // a signed URL on demand. The player is only rendered when
  // [comprehensionAudioUploaded] is true.
  final String? comprehensionAudioPath;
  final int? comprehensionAudioDurationSec;
  final bool comprehensionAudioUploaded;
  final DateTime? comprehensionAudioUploadedAt;
  // One-tap log: books inferred from assignments, not parent-confirmed.
  final bool isQuickLog;
  // Denormalized comment-thread state, so a row can open the thread and show an
  // unread dot without an extra read.
  final DateTime? lastCommentAt;
  final String? lastCommentByRole;
  final Map<String, DateTime> commentsViewedAt;

  const ReadingLogSnapshot({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.allocationId,
    required this.bookTitles,
    required this.status,
    required this.minutesRead,
    required this.targetMinutes,
    required this.parentId,
    required this.parentComment,
    required this.parentCommentSelections,
    required this.parentCommentFreeText,
    required this.childFeeling,
    this.notes,
    this.comprehensionAudioPath,
    this.comprehensionAudioDurationSec,
    this.comprehensionAudioUploaded = false,
    this.comprehensionAudioUploadedAt,
    this.isQuickLog = false,
    this.lastCommentAt,
    this.lastCommentByRole,
    this.commentsViewedAt = const {},
  });

  bool get hasComprehensionAudio =>
      comprehensionAudioUploaded && comprehensionAudioPath != null;

  /// Whether the teacher [uid] has an unseen reply: the newest comment is from
  /// a parent and postdates this teacher's last view of the thread.
  bool hasUnreadForTeacher(String uid) {
    if (lastCommentAt == null || lastCommentByRole == 'teacher') return false;
    final viewed = commentsViewedAt[uid];
    return viewed == null || viewed.isBefore(lastCommentAt!);
  }
}

/// View data for the "Latest Parent Comment" card.
class LatestParentCommentViewData {
  /// The log this comment belongs to, so tapping the card can open its thread.
  final ReadingLogSnapshot log;
  final String? parentId;
  final String commentText;
  final DateTime date;
  final List<String> selections;
  final String? feeling;

  const LatestParentCommentViewData({
    required this.log,
    required this.parentId,
    required this.commentText,
    required this.date,
    required this.selections,
    required this.feeling,
  });
}

/// Parses a readingLogs query snapshot into row models (former
/// `_toReadingLogs`, unchanged).
List<ReadingLogSnapshot> toReadingLogSnapshots(QuerySnapshot snapshot) {
  return snapshot.docs.map((doc) {
    final data = doc.data() as Map<String, dynamic>;
    final dateTimestamp = data['date'] as Timestamp?;
    final commentSelections = data['parentCommentSelections'];
    final viewedRaw = data['commentsViewedAt'] as Map<String, dynamic>?;
    return ReadingLogSnapshot(
      id: doc.id,
      date: dateTimestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
          dateTimestamp?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      allocationId: data['allocationId'] as String?,
      bookTitles: List<String>.from(data['bookTitles'] ?? const []),
      status: (data['status'] as String?) ?? '',
      minutesRead: (data['minutesRead'] as num?)?.toInt() ?? 0,
      targetMinutes: (data['targetMinutes'] as num?)?.toInt() ?? 0,
      notes: (data['notes'] as String?)?.trim(),
      parentId: data['parentId'] as String?,
      parentComment: (data['parentComment'] as String?)?.trim(),
      parentCommentSelections: commentSelections is List
          ? commentSelections.whereType<String>().toList()
          : const [],
      parentCommentFreeText:
          (data['parentCommentFreeText'] as String?)?.trim(),
      childFeeling: data['childFeeling'] as String?,
      comprehensionAudioPath: data['comprehensionAudioPath'] as String?,
      comprehensionAudioDurationSec:
          (data['comprehensionAudioDurationSec'] as num?)?.toInt(),
      comprehensionAudioUploaded:
          data['comprehensionAudioUploaded'] as bool? ?? false,
      comprehensionAudioUploadedAt:
          (data['comprehensionAudioUploadedAt'] as Timestamp?)?.toDate(),
      isQuickLog:
          (data['metadata'] as Map<String, dynamic>?)?['quickLog'] == true,
      lastCommentAt: (data['lastCommentAt'] as Timestamp?)?.toDate(),
      lastCommentByRole: data['lastCommentByRole'] as String?,
      commentsViewedAt: viewedRaw == null
          ? const {}
          : {
              for (final entry in viewedRaw.entries)
                if (entry.value is Timestamp)
                  entry.key: (entry.value as Timestamp).toDate(),
            },
    );
  }).toList();
}

/// Returns only the parent's typed free-text comment, excluding chip
/// selections. Falls back to the legacy `parentComment` field if no
/// structured data exists.
String extractParentFreeText(ReadingLogSnapshot log) {
  final freeText = log.parentCommentFreeText?.trim() ?? '';
  if (freeText.isNotEmpty) return freeText;
  // Legacy logs stored everything in parentComment. Only use it if there
  // are no structured selections (otherwise it's a duplicate).
  if (log.parentCommentSelections.isEmpty) {
    return log.parentComment?.trim() ?? '';
  }
  return '';
}

/// Newest log carrying either chips or free text, or null.
LatestParentCommentViewData? latestParentComment(
  List<ReadingLogSnapshot> logs,
) {
  for (final log in logs) {
    final hasChips = log.parentCommentSelections.isNotEmpty;
    final freeText = extractParentFreeText(log);
    final hasFreeText = freeText.isNotEmpty;
    if (!hasChips && !hasFreeText) continue;

    return LatestParentCommentViewData(
      log: log,
      parentId: log.parentId,
      commentText: freeText,
      date: log.date,
      selections: log.parentCommentSelections,
      feeling: log.childFeeling,
    );
  }
  return null;
}

/// "Today" / "Yesterday" / d/m/y — shared by the history rows and the
/// latest-comment card.
String formatCommentDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final dateOnly = DateTime(date.year, date.month, date.day);
  if (dateOnly == today) return 'Today';
  if (dateOnly == yesterday) return 'Yesterday';
  return '${date.day}/${date.month}/${date.year}';
}
