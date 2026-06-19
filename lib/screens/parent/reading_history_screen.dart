import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../theme/section_theme.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/book_lookup_service.dart';
import '../../services/book_metadata_resolver.dart';
import '../../services/firebase_service.dart';
import 'library/book_cover.dart';
import 'library/book_detail_sheet.dart';
import 'library/book_history_item.dart';
import 'library/reading_feeling_visuals.dart';
import 'library/session_detail_sheet.dart';

/// Vertical space the parent's floating glass nav occupies; scroll content
/// reserves this so the last item clears the bar (mirrors the Home shell).
const double _kNavClearance = 92;

/// Date helpers for the Library's time ranges.
class ReadingHistoryDateRange {
  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime startOfWeek(DateTime date) {
    final dayStart = startOfDay(date);
    return dayStart.subtract(Duration(days: dayStart.weekday - 1));
  }

  static DateTime startOfMonth(DateTime date) =>
      DateTime(date.year, date.month);

  static DateTime startOfNextMonth(DateTime date) =>
      DateTime(date.year, date.month + 1);

  static String formatRange(DateTime startInclusive, DateTime endExclusive) {
    final endInclusive = endExclusive.subtract(const Duration(days: 1));
    final sameYear = startInclusive.year == endInclusive.year;
    final startFormat =
        sameYear ? DateFormat('d MMM') : DateFormat('d MMM yyyy');
    final endFormat = DateFormat('d MMM yyyy');
    return '${startFormat.format(startInclusive)} – ${endFormat.format(endInclusive)}';
  }
}

enum _LibraryTab { activity, books }

enum _Range { week, month, all }

enum _BooksSort { recent, alphabetical }

class ReadingHistoryScreen extends StatefulWidget {
  final String studentId;
  final String parentId;
  final String schoolId;

  const ReadingHistoryScreen({
    super.key,
    required this.studentId,
    required this.parentId,
    required this.schoolId,
  });

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  BookMetadataResolver? _metadataResolverInstance;

  _LibraryTab _tab = _LibraryTab.activity;
  _Range _range = _Range.week;
  DateTime _selectedMonth = DateTime.now();

  _BooksSort _booksSort = _BooksSort.recent;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _searchVisible = false;

  BookMetadataResolver get _metadataResolver {
    final existing = _metadataResolverInstance;
    if (existing != null) return existing;
    final resolver = BookMetadataResolver(
      lookupService: BookLookupService(),
      schoolId: widget.schoolId,
      actorId: widget.parentId,
    );
    resolver.addListener(_onMetadataUpdated);
    _metadataResolverInstance = resolver;
    return resolver;
  }

  @override
  void initState() {
    super.initState();
    _metadataResolver; // eager-init so covers start resolving on first view
  }

  @override
  void didUpdateWidget(covariant ReadingHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scopeChanged = oldWidget.schoolId != widget.schoolId ||
        oldWidget.parentId != widget.parentId;
    if (!scopeChanged) return;
    _disposeMetadataResolver();
    _metadataResolver;
  }

  void _onMetadataUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposeMetadataResolver();
    _searchController.dispose();
    super.dispose();
  }

  void _disposeMetadataResolver() {
    final resolver = _metadataResolverInstance;
    if (resolver == null) return;
    resolver.removeListener(_onMetadataUpdated);
    resolver.dispose();
    _metadataResolverInstance = null;
  }

  Query<Map<String, dynamic>> get _logsCollection => _firebaseService.firestore
      .collection('schools')
      .doc(widget.schoolId)
      .collection('readingLogs')
      .where('studentId', isEqualTo: widget.studentId);

  Stream<QuerySnapshot> _activityStream() {
    switch (_range) {
      case _Range.week:
        final start = ReadingHistoryDateRange.startOfWeek(DateTime.now());
        final end = start.add(const Duration(days: 7));
        return _logsCollection
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThan: Timestamp.fromDate(end))
            .orderBy('date', descending: true)
            .snapshots();
      case _Range.month:
        final start = ReadingHistoryDateRange.startOfMonth(_selectedMonth);
        final end = ReadingHistoryDateRange.startOfNextMonth(_selectedMonth);
        return _logsCollection
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThan: Timestamp.fromDate(end))
            .orderBy('date', descending: true)
            .snapshots();
      case _Range.all:
        return _logsCollection.orderBy('date', descending: true).snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LumiSectionScope(
      section: LumiSectionTheme.library,
      child: Scaffold(
        backgroundColor: LumiTokens.cream,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _tab == _LibraryTab.activity
                    ? _buildActivityTab()
                    : _buildBooksTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header: title + Activity / Books segmented control ──

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LumiTokens.space4,
        LumiTokens.space2,
        LumiTokens.space4,
        LumiTokens.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reading', style: LumiType.heading),
          const SizedBox(height: LumiTokens.space3),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFEDE6),
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            ),
            child: Row(
              children: [
                _SegmentButton(
                  label: 'Activity',
                  selected: _tab == _LibraryTab.activity,
                  onTap: () => setState(() => _tab = _LibraryTab.activity),
                ),
                _SegmentButton(
                  label: 'Bookshelf',
                  selected: _tab == _LibraryTab.books,
                  onTap: () => setState(() => _tab = _LibraryTab.books),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Activity tab: range filter + summary + session timeline ──

  Widget _buildActivityTab() {
    return Column(
      children: [
        _buildRangeFilter(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _activityStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorState(onRetry: () => setState(() {}));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: LumiTokens.yellow),
                );
              }

              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  const <ReadingLogModel>[];

              if (logs.isEmpty) {
                return const _EmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: 'No reading yet',
                  message: 'Reading sessions for this period will appear here.',
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  LumiTokens.space4,
                  LumiTokens.space2,
                  LumiTokens.space4,
                  _kNavClearance,
                ),
                children: [
                  _SummaryStrip(logs: logs),
                  const SizedBox(height: LumiTokens.space5),
                  ..._buildDayGroups(logs),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Splits the (date-descending) logs into per-day groups, each rendered as a
  /// date header above a single card whose rows are that day's sessions. This
  /// replaces the old one-tall-card-per-log list, cutting repetition and depth.
  List<Widget> _buildDayGroups(List<ReadingLogModel> logs) {
    final widgets = <Widget>[];
    DateTime? currentDay;
    var bucket = <ReadingLogModel>[];

    void flush() {
      if (bucket.isEmpty) return;
      widgets.add(_DateHeader(date: currentDay!));
      widgets.add(const SizedBox(height: LumiTokens.space2));
      widgets.add(_DaySessionsCard(logs: List.of(bucket)));
      widgets.add(const SizedBox(height: LumiTokens.space4));
    }

    for (final log in logs) {
      final day = ReadingHistoryDateRange.startOfDay(log.date);
      if (currentDay == null || day != currentDay) {
        flush();
        currentDay = day;
        bucket = <ReadingLogModel>[];
      }
      bucket.add(log);
    }
    flush();
    return widgets;
  }

  Widget _buildRangeFilter() {
    String subLabel;
    switch (_range) {
      case _Range.week:
        final start = ReadingHistoryDateRange.startOfWeek(DateTime.now());
        subLabel = ReadingHistoryDateRange.formatRange(
            start, start.add(const Duration(days: 7)));
      case _Range.month:
        subLabel = '';
      case _Range.all:
        subLabel = 'Across all time';
    }

    final now = DateTime.now();
    final atCurrentMonth =
        _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LumiTokens.space4,
        0,
        LumiTokens.space4,
        LumiTokens.space2,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _FilterChip(
                label: 'Week',
                selected: _range == _Range.week,
                onTap: () => setState(() => _range = _Range.week),
              ),
              const SizedBox(width: LumiTokens.space2),
              _FilterChip(
                label: 'Month',
                selected: _range == _Range.month,
                onTap: () => setState(() => _range = _Range.month),
              ),
              const SizedBox(width: LumiTokens.space2),
              _FilterChip(
                label: 'All time',
                selected: _range == _Range.all,
                onTap: () => setState(() => _range = _Range.all),
              ),
            ],
          ),
          if (_range == _Range.month) ...[
            const SizedBox(height: LumiTokens.space2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StepperButton(
                  icon: Icons.chevron_left,
                  onTap: () => setState(() {
                    _selectedMonth = DateTime(
                        _selectedMonth.year, _selectedMonth.month - 1);
                  }),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: LumiType.body.copyWith(fontWeight: FontWeight.w700),
                ),
                _StepperButton(
                  icon: Icons.chevron_right,
                  onTap: atCurrentMonth
                      ? null
                      : () => setState(() {
                            _selectedMonth = DateTime(
                                _selectedMonth.year, _selectedMonth.month + 1);
                          }),
                ),
              ],
            ),
          ] else if (subLabel.isNotEmpty) ...[
            const SizedBox(height: LumiTokens.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(subLabel, style: LumiType.caption),
            ),
          ],
        ],
      ),
    );
  }

  // ── Books tab: slim shelf (grid + Recent/A-Z sort + optional search) ──

  Widget _buildBooksTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _logsCollection.orderBy('date', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(onRetry: () => setState(() {}));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: LumiTokens.yellow),
          );
        }

        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            const <ReadingLogModel>[];

        final books = <String, BookHistoryItem>{};
        for (final log in logs) {
          for (final title in log.bookTitles) {
            final key = title.trim();
            if (key.isEmpty) continue;
            final existing = books[key];
            if (existing == null) {
              books[key] = BookHistoryItem(
                title: key,
                totalMinutes: log.minutesRead,
                sessions: 1,
                lastReadAt: log.date,
                firstReadAt: log.date,
              );
            } else {
              books[key] = existing.copyWith(
                totalMinutes: existing.totalMinutes + log.minutesRead,
                sessions: existing.sessions + 1,
                lastReadAt: existing.lastReadAt.isAfter(log.date)
                    ? existing.lastReadAt
                    : log.date,
                firstReadAt: existing.firstReadAt.isBefore(log.date)
                    ? existing.firstReadAt
                    : log.date,
              );
            }
          }
        }

        if (books.isEmpty) {
          return const _EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'No books yet',
            message: 'Books you log reading will be collected here.',
          );
        }

        _metadataResolver.resolveAll(books.keys.toList());

        var shelf = books.values.toList();
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          shelf = shelf.where((book) {
            final metadata = _metadataResolver.getCached(book.title);
            final title = (metadata?.title ?? book.title).toLowerCase();
            final author = (metadata?.author ?? '').toLowerCase();
            return title.contains(query) || author.contains(query);
          }).toList();
        }

        switch (_booksSort) {
          case _BooksSort.recent:
            shelf.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
          case _BooksSort.alphabetical:
            shelf.sort((a, b) {
              final at = _metadataResolver.getCached(a.title)?.title ?? a.title;
              final bt = _metadataResolver.getCached(b.title)?.title ?? b.title;
              return at.toLowerCase().compareTo(bt.toLowerCase());
            });
        }

        return Column(
          children: [
            _buildBooksToolbar(count: books.length, showSearch: books.length > 8),
            Expanded(
              child: shelf.isEmpty
                  ? const _EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      message: 'No books match your search.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        LumiTokens.space4,
                        LumiTokens.space2,
                        LumiTokens.space4,
                        _kNavClearance,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.50,
                        crossAxisSpacing: LumiTokens.space3,
                        mainAxisSpacing: LumiTokens.space4,
                      ),
                      itemCount: shelf.length,
                      itemBuilder: (context, index) =>
                          _buildBookTile(shelf[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBooksToolbar({required int count, required bool showSearch}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LumiTokens.space4,
        0,
        LumiTokens.space4,
        LumiTokens.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: LumiTokens.space2),
            child: Text(
              count == 1 ? '1 book' : '$count books',
              style: LumiType.caption,
            ),
          ),
          Row(
            children: [
              _FilterChip(
                label: 'Recent',
                selected: _booksSort == _BooksSort.recent,
                onTap: () => setState(() => _booksSort = _BooksSort.recent),
              ),
              const SizedBox(width: LumiTokens.space2),
              _FilterChip(
                label: 'A–Z',
                selected: _booksSort == _BooksSort.alphabetical,
                onTap: () =>
                    setState(() => _booksSort = _BooksSort.alphabetical),
              ),
              const Spacer(),
              if (showSearch)
                _StepperButton(
                  icon: _searchVisible ? Icons.close : Icons.search,
                  onTap: () => setState(() {
                    _searchVisible = !_searchVisible;
                    if (!_searchVisible) {
                      _searchController.clear();
                      _searchQuery = '';
                    }
                  }),
                ),
            ],
          ),
          if (showSearch && _searchVisible) ...[
            const SizedBox(height: LumiTokens.space2),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: LumiType.body,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search books or authors',
                hintStyle: LumiType.body.copyWith(color: LumiTokens.muted),
                prefixIcon:
                    const Icon(Icons.search, color: LumiTokens.muted, size: 20),
                filled: true,
                fillColor: LumiTokens.paper,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: LumiTokens.space3,
                  vertical: LumiTokens.space3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.yellow),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookTile(BookHistoryItem book) {
    final metadata = _metadataResolver.getCached(book.title);
    final resolved = _metadataResolver.isResolved(book.title);
    final displayTitle = metadata?.title ?? book.title;
    final author = metadata?.author;

    return GestureDetector(
      onTap: () => showBookDetailSheet(context, book, metadata),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: BookCover(
                title: book.title,
                coverUrl: metadata?.coverImageUrl,
                isLoading: !resolved,
              ),
            ),
          ),
          const SizedBox(height: LumiTokens.space2),
          Text(
            displayTitle,
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (author != null)
            Text(
              author,
              style: LumiType.caption.copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 2),
          Text(
            book.sessions == 1 ? '1 session' : '${book.sessions} sessions',
            style: LumiType.caption.copyWith(
              fontSize: 11,
              color: LumiTokens.muted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? LumiTokens.tintYellow : Colors.transparent,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: LumiType.body.copyWith(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? LumiTokens.ink : LumiTokens.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LumiTokens.space4,
          vertical: LumiTokens.space2,
        ),
        decoration: BoxDecoration(
          color: selected ? LumiTokens.tintYellow : Colors.transparent,
          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          border: Border.all(
            color: selected ? LumiTokens.tintYellow : LumiTokens.rule,
          ),
        ),
        child: Text(
          label,
          style: LumiType.caption.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? LumiTokens.ink : LumiTokens.muted,
          ),
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          shape: BoxShape.circle,
          border: Border.all(color: LumiTokens.rule),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? LumiTokens.ink : LumiTokens.rule,
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final List<ReadingLogModel> logs;

  const _SummaryStrip({required this.logs});

  @override
  Widget build(BuildContext context) {
    final totalMinutes =
        logs.fold<int>(0, (total, log) => total + log.minutesRead);
    final bookTitles = <String>{};
    for (final log in logs) {
      for (final title in log.bookTitles) {
        final key = title.trim();
        if (key.isNotEmpty) bookTitles.add(key.toLowerCase());
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: LumiTokens.space4,
        horizontal: LumiTokens.space4,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _SummaryStat(
              icon: Icons.event_available_rounded,
              tint: LumiTokens.tintBlue,
              iconColor: LumiTokens.blue,
              value: '${logs.length}',
              label: 'Sessions',
            ),
            const _SummaryDivider(),
            _SummaryStat(
              icon: Icons.schedule_rounded,
              tint: LumiTokens.tintOrange,
              iconColor: LumiTokens.orange,
              value: formatReadingDuration(totalMinutes),
              label: 'Reading time',
            ),
            const _SummaryDivider(),
            _SummaryStat(
              icon: Icons.menu_book_rounded,
              tint: LumiTokens.tintGreen,
              iconColor: LumiTokens.green,
              value: '${bookTitles.length}',
              label: 'Books',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String value;
  final String label;

  const _SummaryStat({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(height: LumiTokens.space2),
          Text(
            value,
            style: LumiType.subhead.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            textAlign: TextAlign.center,
            style: LumiType.caption.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 1, thickness: 1, color: LumiTokens.rule);
}

class _DateHeader extends StatelessWidget {
  final DateTime date;

  const _DateHeader({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE, d MMM').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        _label().toUpperCase(),
        style: LumiType.caption.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: LumiTokens.muted,
        ),
      ),
    );
  }
}

/// A single day's reading sessions, grouped into one card with divider rows.
class _DaySessionsCard extends StatelessWidget {
  final List<ReadingLogModel> logs;

  const _DaySessionsCard({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        children: [
          for (var i = 0; i < logs.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: LumiTokens.space4,
                endIndent: LumiTokens.space4,
                color: LumiTokens.rule,
              ),
            _SessionRow(log: logs[i]),
          ],
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final ReadingLogModel log;

  const _SessionRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final hasMultipleBooks = log.bookTitles.length > 1;
    final extraCount = log.bookTitles.length - 1;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final hasUnread = uid.isNotEmpty && log.hasUnreadFor(uid, 'parent');
    final feeling = log.childFeeling;

    return InkWell(
      onTap: () => showSessionDetailSheet(context, log),
      child: Padding(
        padding: const EdgeInsets.all(LumiTokens.space4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading: the child's feeling blob when logged, otherwise a quiet
            // book glyph. An unread dot rides the corner when the teacher has
            // replied since this parent last opened the thread.
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (feeling != null)
                  Image.asset(
                    feelingAsset(feeling),
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: LumiTokens.cream,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        size: 20, color: LumiTokens.muted),
                  ),
                if (hasUnread)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: LumiTokens.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: LumiTokens.paper, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: LumiTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hasMultipleBooks
                              ? log.bookTitles.first
                              : log.bookTitles.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LumiType.body
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (hasMultipleBooks) ...[
                        const SizedBox(width: LumiTokens.space2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: LumiTokens.space2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFEDE6),
                            borderRadius:
                                BorderRadius.circular(LumiTokens.radiusPill),
                          ),
                          child: Text(
                            '+$extraCount more',
                            style: LumiType.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: LumiTokens.muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '${log.minutesRead} min',
                      if (log.loggedByName != null)
                        'Logged by ${log.loggedByDisplay}',
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LumiType.caption,
                  ),
                  if (log.notes != null && log.notes!.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      log.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LumiType.caption.copyWith(
                        fontStyle: FontStyle.italic,
                        color: LumiTokens.ink,
                      ),
                    ),
                  ],
                  if (log.teacherComment != null) ...[
                    const SizedBox(height: LumiTokens.space2),
                    Container(
                      padding: const EdgeInsets.all(LumiTokens.space2),
                      decoration: BoxDecoration(
                        color: LumiTokens.tintBlue,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusSmall),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline,
                              size: 14, color: LumiTokens.blue),
                          const SizedBox(width: LumiTokens.space2),
                          Expanded(
                            child: Text(
                              'Teacher: ${log.teacherComment}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: LumiType.caption
                                  .copyWith(color: LumiTokens.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: LumiTokens.space2),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right_rounded,
                  size: 20, color: LumiTokens.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LumiTokens.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: LumiTokens.tintYellow,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: LumiTokens.ink),
            ),
            const SizedBox(height: LumiTokens.space4),
            Text(title, style: LumiType.subhead),
            const SizedBox(height: LumiTokens.space2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LumiType.body.copyWith(color: LumiTokens.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LumiTokens.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: LumiTokens.muted),
            const SizedBox(height: LumiTokens.space3),
            Text("Couldn't load reading history", style: LumiType.subhead),
            const SizedBox(height: LumiTokens.space2),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: LumiType.body.copyWith(color: LumiTokens.muted),
            ),
            const SizedBox(height: LumiTokens.space4),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: LumiTokens.ink),
              label: Text('Retry',
                  style: LumiType.body.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
