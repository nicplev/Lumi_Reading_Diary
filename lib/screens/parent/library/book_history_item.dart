/// Formats a minute count as a short reading duration: "45m", "1h", "1h 30m".
String formatReadingDuration(int totalMinutes) {
  if (totalMinutes < 60) return '${totalMinutes}m';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

/// Aggregated reading history for a single book title, derived from a child's
/// reading logs (deduped by title). Used by the Library "Books" shelf and the
/// book-detail sheet.
class BookHistoryItem {
  final String title;
  final int totalMinutes;
  final int sessions;
  final DateTime lastReadAt;
  final DateTime firstReadAt;

  const BookHistoryItem({
    required this.title,
    required this.totalMinutes,
    required this.sessions,
    required this.lastReadAt,
    required this.firstReadAt,
  });

  BookHistoryItem copyWith({
    String? title,
    int? totalMinutes,
    int? sessions,
    DateTime? lastReadAt,
    DateTime? firstReadAt,
  }) {
    return BookHistoryItem(
      title: title ?? this.title,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      sessions: sessions ?? this.sessions,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      firstReadAt: firstReadAt ?? this.firstReadAt,
    );
  }
}
