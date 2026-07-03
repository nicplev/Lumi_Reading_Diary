import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/inline_stream_error.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/comments/teacher_comments_sheet.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _ViewMode { logs, books }

enum _DateFilter { all, lastWeek, thisMonth }

// ─── Screen ───────────────────────────────────────────────────────────────────

class TeacherStudentReadingHistoryScreen extends StatefulWidget {
  final StudentModel student;

  const TeacherStudentReadingHistoryScreen({
    super.key,
    required this.student,
  });

  @override
  State<TeacherStudentReadingHistoryScreen> createState() =>
      _TeacherStudentReadingHistoryScreenState();
}

class _TeacherStudentReadingHistoryScreenState
    extends State<TeacherStudentReadingHistoryScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;

  _ViewMode _viewMode = _ViewMode.logs;
  Set<String> _selectedFeelings = {};
  _DateFilter _dateFilter = _DateFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Filter & Group ─────────────────────────────────────────────────────────

  List<_ReadingLogSnapshot> _applyFilters(List<_ReadingLogSnapshot> all) {
    var logs = all;

    final now = DateTime.now();
    if (_dateFilter == _DateFilter.lastWeek) {
      final cutoff = now.subtract(const Duration(days: 7));
      logs = logs.where((l) => l.date.isAfter(cutoff)).toList();
    } else if (_dateFilter == _DateFilter.thisMonth) {
      final cutoff = DateTime(now.year, now.month, 1);
      logs = logs.where((l) => l.date.isAfter(cutoff)).toList();
    }

    if (_selectedFeelings.isNotEmpty) {
      logs = logs
          .where((l) =>
              l.childFeeling != null &&
              _selectedFeelings.contains(l.childFeeling))
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      logs = logs
          .where((l) => l.bookTitles.any((t) => t.toLowerCase().contains(q)))
          .toList();
    }

    return logs;
  }

  List<_BookSummary> _groupByBook(List<_ReadingLogSnapshot> logs) {
    final map = <String, List<_ReadingLogSnapshot>>{};
    for (final log in logs) {
      for (final title in log.bookTitles) {
        if (title.trim().isEmpty) continue;
        (map[title] ??= []).add(log);
      }
    }
    return map.entries.map((e) {
      final sessions = e.value..sort((a, b) => b.date.compareTo(a.date));
      return _BookSummary(
        title: e.key,
        sessionCount: sessions.length,
        totalMinutes: sessions.fold(0, (acc, l) => acc + l.minutesRead),
        feelings: sessions
            .where((l) => l.childFeeling != null)
            .map((l) => l.childFeeling!)
            .toList(),
        firstRead: sessions.last.date,
        lastRead: sessions.first.date,
      );
    }).toList()
      ..sort((a, b) => b.lastRead.compareTo(a.lastRead));
  }

  bool get _hasActiveFilters =>
      _selectedFeelings.isNotEmpty ||
      _dateFilter != _DateFilter.all ||
      _searchQuery.isNotEmpty;

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.paper,
        foregroundColor: LumiTokens.ink,
        elevation: 0,
        surfaceTintColor: LumiTokens.paper,
        title: Row(
          children: [
            StudentAvatar.fromStudent(widget.student, size: 32),
            const SizedBox(width: 10),
            Text(widget.student.fullName, style: LumiType.subhead),
          ],
        ),
        actions: [
          _ViewToggle(
            mode: _viewMode,
            onChanged: (m) => setState(() => _viewMode = m),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firebaseService.firestore
            .collection('schools')
            .doc(widget.student.schoolId)
            .collection('readingLogs')
            .where('studentId', isEqualTo: widget.student.id)
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: InlineStreamError(
                message: "Couldn't load reading history.",
                onRetry: () => setState(() {}),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allLogs = _toReadingLogs(snapshot.data!);

          if (allLogs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 48, color: LumiTokens.muted),
                  const SizedBox(height: 12),
                  Text('No reading history yet',
                      style: LumiType.caption),
                ],
              ),
            );
          }

          final filtered = _applyFilters(allLogs);
          final books = _viewMode == _ViewMode.books
              ? _groupByBook(filtered)
              : <_BookSummary>[];

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                  child: _buildStatsBar(allLogs,
                      filteredCount:
                          _hasActiveFilters ? filtered.length : null)),
              SliverToBoxAdapter(child: _buildFilterSection()),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.filter_list_off,
                            size: 40, color: LumiTokens.muted),
                        const SizedBox(height: 10),
                        Text('No logs match your filters',
                            style: LumiType.caption),
                      ],
                    ),
                  ),
                )
              else if (_viewMode == _ViewMode.logs)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildReadingLogRow(
                      filtered[index],
                      showDivider: index < filtered.length - 1,
                    ),
                    childCount: filtered.length,
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildBookSummaryRow(
                      books[index],
                      showDivider: index < books.length - 1,
                    ),
                    childCount: books.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  // ─── Stats Bar ──────────────────────────────────────────────────────────────

  Widget _buildStatsBar(List<_ReadingLogSnapshot> logs, {int? filteredCount}) {
    final totalNights = logs.length;
    final totalMinutes = logs.fold(0, (acc, l) => acc + l.minutesRead);
    final booksRead = logs
        .expand((l) => l.bookTitles)
        .where((t) => t.isNotEmpty)
        .toSet()
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                _buildStatCell('$totalNights', 'Nights logged'),
                VerticalDivider(
                    width: 1, thickness: 1, color: LumiTokens.rule),
                _buildStatCell('$totalMinutes', 'Total minutes'),
                VerticalDivider(
                    width: 1, thickness: 1, color: LumiTokens.rule),
                _buildStatCell('$booksRead', 'Books read'),
              ],
            ),
          ),
          if (filteredCount != null) ...[
            const SizedBox(height: 8),
            Text(
              'Showing $filteredCount of $totalNights sessions',
              style: LumiType.caption
                  .copyWith(color: LumiTokens.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCell(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: LumiType.heading),
          const SizedBox(height: 2),
          Text(
            label,
            style: LumiType.caption
                .copyWith(color: LumiTokens.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Filter Section ─────────────────────────────────────────────────────────

  Widget _buildFilterSection() {
    return Column(
      children: [
        // Search bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: LumiTokens.rule),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: LumiTokens.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: LumiType.body,
                  decoration: InputDecoration(
                    hintText: 'Search by book name...',
                    hintStyle: LumiType.body
                        .copyWith(color: LumiTokens.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  cursorColor: LumiTokens.green,
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(Icons.close,
                      size: 16, color: LumiTokens.muted),
                ),
            ],
          ),
        ),
        // Filter chips row
        SizedBox(
          height: 40,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                TeacherFilterChip(
                  label: 'All time',
                  isActive: _dateFilter == _DateFilter.all,
                  activeColor: LumiTokens.green,
                  onTap: () => setState(() => _dateFilter = _DateFilter.all),
                ),
                const SizedBox(width: 8),
                TeacherFilterChip(
                  label: 'Last week',
                  isActive: _dateFilter == _DateFilter.lastWeek,
                  activeColor: LumiTokens.green,
                  onTap: () =>
                      setState(() => _dateFilter = _DateFilter.lastWeek),
                ),
                const SizedBox(width: 8),
                TeacherFilterChip(
                  label: 'This month',
                  isActive: _dateFilter == _DateFilter.thisMonth,
                  activeColor: LumiTokens.green,
                  onTap: () =>
                      setState(() => _dateFilter = _DateFilter.thisMonth),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 24, color: LumiTokens.rule),
                const SizedBox(width: 12),
                for (final feeling in const [
                  'hard',
                  'tricky',
                  'okay',
                  'good',
                  'great'
                ]) ...[
                  _BlobFilterChip(
                    feeling: feeling,
                    isActive: _selectedFeelings.contains(feeling),
                    onTap: () => setState(() {
                      if (_selectedFeelings.contains(feeling)) {
                        _selectedFeelings = {..._selectedFeelings}
                          ..remove(feeling);
                      } else {
                        _selectedFeelings = {..._selectedFeelings, feeling};
                      }
                    }),
                  ),
                  if (feeling != 'great') const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ─── Log Row ─────────────────────────────────────────────────────────────────

  Widget _buildReadingLogRow(_ReadingLogSnapshot log,
      {required bool showDivider}) {
    final dateStr = _formatCommentDate(log.date);
    final books =
        log.bookTitles.isNotEmpty ? log.bookTitles.join(', ') : 'Free reading';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final hasUnread = uid.isNotEmpty && log.hasUnreadForTeacher(uid);
    // Date, duration and logger collapse into one muted meta line so the row
    // reads title-first instead of cramming everything across.
    final meta = [
      dateStr,
      '${log.minutesRead} min',
      if (log.loggedByDisplay != null) 'Logged by ${log.loggedByDisplay}',
    ].join(' · ');

    return Column(
      children: [
        InkWell(
          onTap: () => _openCommentsSheet(log),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              books,
                              style: LumiType.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Subtle one-tap marker: the books were inferred from
                          // the child's assignments, not confirmed by the parent.
                          if (log.isQuickLog) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message:
                                  'Quick log — books inferred from assignments, '
                                  'not confirmed by the parent',
                              triggerMode: TooltipTriggerMode.tap,
                              child: Icon(
                                Icons.bolt,
                                size: 15,
                                color: LumiTokens.muted.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style:
                            LumiType.caption.copyWith(color: LumiTokens.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status dot (completed / partial / skipped)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(log.status),
                    shape: BoxShape.circle,
                  ),
                ),
                if (log.childFeeling != null) ...[
                  const SizedBox(width: 8),
                  Image.asset(
                    'assets/blobs/blob-${log.childFeeling}.png',
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ],
                if (log.hasRecording) ...[
                  const SizedBox(width: 8),
                  RecordingAffordance(
                      pending: !log.comprehensionAudioUploaded),
                ],
                const SizedBox(width: 8),
                CommentAffordance(
                  hasUnread: hasUnread,
                  schoolId: widget.student.schoolId,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: LumiTokens.rule,
            indent: 14,
            endIndent: 14,
          ),
      ],
    );
  }

  // ─── Book Summary Row ────────────────────────────────────────────────────────

  Widget _buildBookSummaryRow(_BookSummary book, {required bool showDivider}) {
    final dateRange = book.sessionCount == 1
        ? _formatCommentDate(book.lastRead)
        : '${_formatCommentDate(book.firstRead)} – ${_formatCommentDate(book.lastRead)}';

    // Deduplicate feelings ordered by frequency
    final feelingCounts = <String, int>{};
    for (final f in book.feelings) {
      feelingCounts[f] = (feelingCounts[f] ?? 0) + 1;
    }
    final uniqueFeelings = feelingCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topFeelings = uniqueFeelings.take(4).map((e) => e.key).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: LumiType.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${book.sessionCount} ${book.sessionCount == 1 ? 'session' : 'sessions'}  ·  ${book.totalMinutes} min  ·  $dateRange',
                      style: LumiType.caption
                          .copyWith(color: LumiTokens.muted),
                    ),
                  ],
                ),
              ),
              if (topFeelings.isNotEmpty) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in topFeelings)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Image.asset(
                          'assets/blobs/blob-$f.png',
                          width: 20,
                          height: 20,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: LumiTokens.rule,
            indent: 14,
            endIndent: 14,
          ),
      ],
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  Color _statusColor(String status) => switch (status) {
        'completed' => LumiTokens.green,
        'partial' => LumiTokens.yellow,
        'skipped' => LumiTokens.red,
        _ => LumiTokens.muted,
      };

  /// Builds a full [ReadingLogModel] from the lightweight snapshot plus the
  /// screen's student, carrying the fields the comment thread and its writes
  /// need (ids and the denormalized comment state).
  ReadingLogModel _toReadingLogModel(_ReadingLogSnapshot snap) {
    return ReadingLogModel(
      id: snap.id,
      studentId: widget.student.id,
      parentId: snap.parentId ?? '',
      schoolId: widget.student.schoolId,
      classId: widget.student.classId,
      date: snap.date,
      minutesRead: snap.minutesRead,
      targetMinutes: snap.targetMinutes,
      status: LogStatus.values.firstWhere(
        (e) => e.toString() == 'LogStatus.${snap.status}',
        orElse: () => LogStatus.pending,
      ),
      bookTitles: snap.bookTitles,
      notes: snap.notes,
      createdAt: snap.createdAt,
      comprehensionAudioPath: snap.comprehensionAudioPath,
      comprehensionAudioDurationSec: snap.comprehensionAudioDurationSec,
      comprehensionAudioUploaded: snap.comprehensionAudioUploaded,
      lastCommentAt: snap.lastCommentAt,
      lastCommentByRole: snap.lastCommentByRole,
      commentsViewedAt: snap.commentsViewedAt,
    );
  }

  void _openCommentsSheet(_ReadingLogSnapshot snap) {
    openTeacherCommentsSheet(
      context,
      log: _toReadingLogModel(snap),
      studentName: widget.student.fullName,
    );
  }

  List<_ReadingLogSnapshot> _toReadingLogs(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final dateTimestamp = data['date'] as Timestamp?;
      final commentSelections = data['parentCommentSelections'];
      final viewedRaw = data['commentsViewedAt'] as Map<String, dynamic>?;
      return _ReadingLogSnapshot(
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
        isQuickLog:
            (data['metadata'] as Map<String, dynamic>?)?['quickLog'] == true,
        loggedByName: (data['loggedByName'] as String?)?.trim(),
        loggedByLabel: (data['loggedByLabel'] as String?)?.trim(),
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

  String _formatCommentDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'Today';
    if (dateOnly == yesterday) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ─── Private Widgets ──────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  final _ViewMode mode;
  final ValueChanged<_ViewMode> onChanged;

  const _ViewToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LumiTokens.rule),
        color: LumiTokens.paper,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleSide(
            icon: Icons.list_rounded,
            active: mode == _ViewMode.logs,
            isLeft: true,
            onTap: () => onChanged(_ViewMode.logs),
          ),
          Container(width: 1, color: LumiTokens.rule),
          _toggleSide(
            icon: Icons.menu_book_outlined,
            active: mode == _ViewMode.books,
            isLeft: false,
            onTap: () => onChanged(_ViewMode.books),
          ),
        ],
      ),
    );
  }

  Widget _toggleSide({
    required IconData icon,
    required bool active,
    required bool isLeft,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        decoration: BoxDecoration(
          color: active ? LumiTokens.green : LumiTokens.paper,
          borderRadius: BorderRadius.only(
            topLeft: isLeft ? const Radius.circular(7) : Radius.zero,
            bottomLeft: isLeft ? const Radius.circular(7) : Radius.zero,
            topRight: !isLeft ? const Radius.circular(7) : Radius.zero,
            bottomRight: !isLeft ? const Radius.circular(7) : Radius.zero,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 18,
            color: active ? LumiTokens.paper : LumiTokens.muted,
          ),
        ),
      ),
    );
  }
}

class _BlobFilterChip extends StatelessWidget {
  final String feeling;
  final bool isActive;
  final VoidCallback onTap;

  const _BlobFilterChip({
    required this.feeling,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? LumiTokens.tintGreen : LumiTokens.paper,
          shape: BoxShape.circle,
          border: Border.all(
            color:
                isActive ? LumiTokens.green : LumiTokens.rule,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Image.asset(
            'assets/blobs/blob-$feeling.png',
            width: 22,
            height: 22,
          ),
        ),
      ),
    );
  }
}

/// Trailing comment icon on a log row, with an accent dot when the teacher has
/// an unseen parent reply.
// ─── Data Classes ─────────────────────────────────────────────────────────────

class _ReadingLogSnapshot {
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
  final String? loggedByName;
  final String? loggedByLabel;
  final String? comprehensionAudioPath;
  final int? comprehensionAudioDurationSec;
  final bool comprehensionAudioUploaded;
  final bool isQuickLog;
  final DateTime? lastCommentAt;
  final String? lastCommentByRole;
  final Map<String, DateTime> commentsViewedAt;

  const _ReadingLogSnapshot({
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
    this.loggedByName,
    this.loggedByLabel,
    this.comprehensionAudioPath,
    this.comprehensionAudioDurationSec,
    this.comprehensionAudioUploaded = false,
    this.isQuickLog = false,
    this.lastCommentAt,
    this.lastCommentByRole,
    this.commentsViewedAt = const {},
  });

  /// "Logged by …" attribution, or null if this is a legacy log.
  String? get loggedByDisplay => loggedByLabel ?? loggedByName;

  /// Whether this log has a comprehension recording on it (uploaded or not).
  bool get hasRecording =>
      comprehensionAudioPath != null && comprehensionAudioPath!.isNotEmpty;

  /// Whether the teacher [uid] has an unseen reply: the newest comment is from
  /// a parent and postdates this teacher's last view of the thread.
  bool hasUnreadForTeacher(String uid) {
    if (lastCommentAt == null || lastCommentByRole == 'teacher') return false;
    final viewed = commentsViewedAt[uid];
    return viewed == null || viewed.isBefore(lastCommentAt!);
  }
}

class _BookSummary {
  final String title;
  final int sessionCount;
  final int totalMinutes;
  final List<String> feelings;
  final DateTime firstRead;
  final DateTime lastRead;

  const _BookSummary({
    required this.title,
    required this.sessionCount,
    required this.totalMinutes,
    required this.feelings,
    required this.firstRead,
    required this.lastRead,
  });
}
