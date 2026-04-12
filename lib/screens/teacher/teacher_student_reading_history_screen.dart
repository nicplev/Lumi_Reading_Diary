import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
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
      backgroundColor: AppColors.teacherBackground,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        surfaceTintColor: AppColors.white,
        title: Row(
          children: [
            StudentAvatar.fromStudent(widget.student, size: 32),
            const SizedBox(width: 10),
            Text(widget.student.fullName, style: TeacherTypography.h3),
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
                      size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Text('No reading history yet',
                      style: TeacherTypography.bodySmall),
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
                      filteredCount: _hasActiveFilters ? filtered.length : null)),
              SliverToBoxAdapter(child: _buildFilterSection()),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.filter_list_off,
                            size: 40, color: AppColors.textSecondary),
                        const SizedBox(height: 10),
                        Text('No logs match your filters',
                            style: TeacherTypography.bodySmall),
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

  Widget _buildStatsBar(List<_ReadingLogSnapshot> logs,
      {int? filteredCount}) {
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
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        border: Border.all(color: AppColors.teacherBorder),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                _buildStatCell('$totalNights', 'Nights logged'),
                VerticalDivider(
                    width: 1, thickness: 1, color: AppColors.teacherBorder),
                _buildStatCell('$totalMinutes', 'Total minutes'),
                VerticalDivider(
                    width: 1, thickness: 1, color: AppColors.teacherBorder),
                _buildStatCell('$booksRead', 'Books read'),
              ],
            ),
          ),
          if (filteredCount != null) ...[
            const SizedBox(height: 8),
            Text(
              'Showing $filteredCount of $totalNights sessions',
              style: TeacherTypography.caption
                  .copyWith(color: AppColors.textSecondary),
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
          Text(value, style: TeacherTypography.h2),
          const SizedBox(height: 2),
          Text(
            label,
            style: TeacherTypography.caption
                .copyWith(color: AppColors.textSecondary),
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
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.teacherBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TeacherTypography.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search by book name...',
                    hintStyle: TeacherTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                  cursorColor: AppColors.teacherPrimary,
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(Icons.close,
                      size: 16, color: AppColors.textSecondary),
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
                  onTap: () => setState(() => _dateFilter = _DateFilter.all),
                ),
                const SizedBox(width: 8),
                TeacherFilterChip(
                  label: 'Last week',
                  isActive: _dateFilter == _DateFilter.lastWeek,
                  onTap: () =>
                      setState(() => _dateFilter = _DateFilter.lastWeek),
                ),
                const SizedBox(width: 8),
                TeacherFilterChip(
                  label: 'This month',
                  isActive: _dateFilter == _DateFilter.thisMonth,
                  onTap: () =>
                      setState(() => _dateFilter = _DateFilter.thisMonth),
                ),
                const SizedBox(width: 12),
                Container(
                    width: 1, height: 24, color: AppColors.teacherBorder),
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
    final minutes = log.minutesRead;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(dateStr, style: TeacherTypography.caption),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  books,
                  style: TeacherTypography.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${minutes}m',
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(log.status),
                  shape: BoxShape.circle,
                ),
              ),
              if (log.childFeeling != null) ...[
                const SizedBox(width: 6),
                Image.asset(
                  'assets/blobs/blob-${log.childFeeling}.png',
                  width: 18,
                  height: 18,
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: AppColors.teacherBorder,
            indent: 14,
            endIndent: 14,
          ),
      ],
    );
  }

  // ─── Book Summary Row ────────────────────────────────────────────────────────

  Widget _buildBookSummaryRow(_BookSummary book,
      {required bool showDivider}) {
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
                      style: TeacherTypography.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${book.sessionCount} ${book.sessionCount == 1 ? 'session' : 'sessions'}  ·  ${book.totalMinutes} min  ·  $dateRange',
                      style: TeacherTypography.caption
                          .copyWith(color: AppColors.textSecondary),
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
            color: AppColors.teacherBorder,
            indent: 14,
            endIndent: 14,
          ),
      ],
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  Color _statusColor(String status) => switch (status) {
        'completed' => AppColors.success,
        'partial' => AppColors.warmOrange,
        'skipped' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  List<_ReadingLogSnapshot> _toReadingLogs(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final dateTimestamp = data['date'] as Timestamp?;
      final commentSelections = data['parentCommentSelections'];
      return _ReadingLogSnapshot(
        id: doc.id,
        date:
            dateTimestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        allocationId: data['allocationId'] as String?,
        bookTitles: List<String>.from(data['bookTitles'] ?? const []),
        status: (data['status'] as String?) ?? '',
        minutesRead: (data['minutesRead'] as num?)?.toInt() ?? 0,
        targetMinutes: (data['targetMinutes'] as num?)?.toInt() ?? 0,
        parentId: data['parentId'] as String?,
        parentComment: (data['parentComment'] as String?)?.trim(),
        parentCommentSelections: commentSelections is List
            ? commentSelections.whereType<String>().toList()
            : const [],
        parentCommentFreeText:
            (data['parentCommentFreeText'] as String?)?.trim(),
        childFeeling: data['childFeeling'] as String?,
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
        border: Border.all(color: AppColors.teacherBorder),
        color: AppColors.white,
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
          Container(width: 1, color: AppColors.teacherBorder),
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
          color: active ? AppColors.teacherPrimary : AppColors.white,
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
            color: active ? AppColors.white : AppColors.textSecondary,
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
          color: isActive ? AppColors.teacherPrimaryLight : AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? AppColors.teacherPrimary : AppColors.teacherBorder,
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

// ─── Data Classes ─────────────────────────────────────────────────────────────

class _ReadingLogSnapshot {
  final String id;
  final DateTime date;
  final String? allocationId;
  final List<String> bookTitles;
  final String status;
  final int minutesRead;
  final int targetMinutes;
  final String? parentId;
  final String? parentComment;
  final List<String> parentCommentSelections;
  final String? parentCommentFreeText;
  final String? childFeeling;

  const _ReadingLogSnapshot({
    required this.id,
    required this.date,
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
  });
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
