/// In-memory snapshot of an active developer impersonation session.
///
/// The [ImpersonationService] holds one of these (or null) and notifies
/// listeners when it flips. Never persisted to disk — a full app restart
/// clears the session (server-side TTL handles stale sessions too).
class ImpersonationSession {
  const ImpersonationSession({
    required this.sessionId,
    required this.schoolId,
    required this.schoolName,
    required this.targetUserId,
    required this.targetUserLabel,
    required this.role,
    required this.reason,
    required this.startedAt,
    required this.expiresAt,
  });

  final String sessionId;
  final String schoolId;
  final String schoolName;
  final String targetUserId;
  final String targetUserLabel;
  final String role; // 'teacher' | 'schoolAdmin'
  final String reason;
  final DateTime startedAt;
  final DateTime expiresAt;

  Duration get remaining {
    final now = DateTime.now();
    final diff = expiresAt.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
