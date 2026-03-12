import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/book_lookup_service.dart';
import '../../services/book_metadata_resolver.dart';
import '../../services/firebase_service.dart';

enum _MyBooksSortMode { lastRead, mostRead, alphabetical, totalTime }

class ReadingHistoryDateRange {
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime startOfWeek(DateTime date) {
    final dayStart = startOfDay(date);
    return dayStart.subtract(Duration(days: dayStart.weekday - 1));
  }

  static DateTime startOfMonth(DateTime date) {
    return DateTime(date.year, date.month);
  }

  static DateTime startOfNextMonth(DateTime date) {
    return DateTime(date.year, date.month + 1);
  }

  static String formatRange(DateTime startInclusive, DateTime endExclusive) {
    final endInclusive = endExclusive.subtract(const Duration(days: 1));
    final sameYear = startInclusive.year == endInclusive.year;
    final startFormat =
        sameYear ? DateFormat('d MMM') : DateFormat('d MMM yyyy');
    final endFormat = DateFormat('d MMM yyyy');
    return '${startFormat.format(startInclusive)} - ${endFormat.format(endInclusive)}';
  }

  static String formatDurationMinutes(int totalMinutes) {
    if (totalMinutes < 60) {
      return '${totalMinutes}m';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
}

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

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _firebaseService = FirebaseService.instance;
  late final BookMetadataResolver _metadataResolver;
  DateTime _selectedMonth = DateTime.now();
  String _selectedView = 'list'; // 'list' or 'chart'

  // My Books tab state
  String _myBooksView = 'list'; // 'list' or 'grid'
  _MyBooksSortMode _myBooksSortMode = _MyBooksSortMode.lastRead;
  String _myBooksSearchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchVisible = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _metadataResolver = BookMetadataResolver(
      lookupService: BookLookupService(),
      schoolId: widget.schoolId,
      actorId: widget.parentId,
    );
    _metadataResolver.addListener(_onMetadataUpdated);
  }

  void _onMetadataUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _metadataResolver.removeListener(_onMetadataUpdated);
    _metadataResolver.dispose();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Bookshelf', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(child: Text('This Week', style: LumiTextStyles.label())),
            Tab(child: Text('This Month', style: LumiTextStyles.label())),
            Tab(child: Text('All Time', style: LumiTextStyles.label())),
            Tab(child: Text('My Books', style: LumiTextStyles.label())),
          ],
          labelColor: AppColors.rosePink,
          unselectedLabelColor: AppColors.charcoal.withValues(alpha: 0.7),
          indicatorColor: AppColors.rosePink,
        ),
        actions: [
          LumiIconButton(
            icon: _selectedView == 'list' ? Icons.bar_chart : Icons.list,
            onPressed: () {
              setState(() {
                _selectedView = _selectedView == 'list' ? 'chart' : 'list';
              });
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWeekView(),
          _buildMonthView(),
          _buildAllTimeView(),
          _buildMyBooksView(),
        ],
      ),
    );
  }

  Widget _buildWeekView() {
    final startOfWeek = ReadingHistoryDateRange.startOfWeek(DateTime.now());
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    return Column(
      children: [
        _buildRangeHeader(
          'Week: ${ReadingHistoryDateRange.formatRange(startOfWeek, endOfWeek)}',
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firebaseService.firestore
                .collection('schools')
                .doc(widget.schoolId)
                .collection('readingLogs')
                .where('studentId', isEqualTo: widget.studentId)
                .where('date',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
                .where('date', isLessThan: Timestamp.fromDate(endOfWeek))
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _buildQueryErrorState(
                  context,
                  'Couldn\'t load reading logs for this week.',
                  snapshot.error,
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  [];

              if (_selectedView == 'chart') {
                return _buildWeekChart(logs, startOfWeek);
              }

              return _buildLogsList(logs, 'No reading logs this week');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthView() {
    final startOfMonth = ReadingHistoryDateRange.startOfMonth(_selectedMonth);
    final startOfNextMonth =
        ReadingHistoryDateRange.startOfNextMonth(_selectedMonth);

    return Column(
      children: [
        // Month selector
        Container(
          color: AppColors.white,
          padding: EdgeInsets.symmetric(
              horizontal: LumiSpacing.s, vertical: LumiSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LumiIconButton(
                icon: Icons.chevron_left,
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    );
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedMonth),
                style: LumiTextStyles.h3(),
              ),
              LumiIconButton(
                icon: Icons.chevron_right,
                onPressed: _selectedMonth.month == DateTime.now().month &&
                        _selectedMonth.year == DateTime.now().year
                    ? null
                    : () {
                        setState(() {
                          _selectedMonth = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month + 1,
                          );
                        });
                      },
              ),
            ],
          ),
        ),
        _buildRangeHeader(
          ReadingHistoryDateRange.formatRange(startOfMonth, startOfNextMonth),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firebaseService.firestore
                .collection('schools')
                .doc(widget.schoolId)
                .collection('readingLogs')
                .where('studentId', isEqualTo: widget.studentId)
                .where('date',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
                .where('date', isLessThan: Timestamp.fromDate(startOfNextMonth))
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _buildQueryErrorState(
                  context,
                  'Couldn\'t load reading logs for this month.',
                  snapshot.error,
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  [];

              if (_selectedView == 'chart') {
                return _buildMonthChart(logs, startOfMonth, startOfNextMonth);
              }

              return _buildLogsList(logs, 'No reading logs this month');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAllTimeView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.studentId)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildQueryErrorState(
            context,
            'Couldn\'t load all-time reading history.',
            snapshot.error,
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        if (logs.isEmpty) {
          return _buildEmptyState('No reading logs yet');
        }

        // Calculate statistics
        final totalMinutes =
            logs.fold<int>(0, (sum, log) => sum + log.minutesRead);
        final totalBooks =
            logs.fold<int>(0, (sum, log) => sum + log.bookTitles.length);
        final uniqueDates = logs
            .map((log) => ReadingHistoryDateRange.startOfDay(log.date))
            .toSet();
        final readingDays = uniqueDates.length;
        final averageMinutes =
            readingDays == 0 ? 0 : (totalMinutes / readingDays).round();

        // Most read book
        final bookFrequency = <String, int>{};
        for (final log in logs) {
          for (final title in log.bookTitles) {
            bookFrequency[title] = (bookFrequency[title] ?? 0) + 1;
          }
        }
        String? mostReadBook;
        int mostReadCount = 0;
        bookFrequency.forEach((title, count) {
          if (count > mostReadCount) {
            mostReadBook = title;
            mostReadCount = count;
          }
        });

        // Reading streaks
        final sortedDates = uniqueDates.toList()..sort();
        int currentStreak = 0;
        int longestStreak = 0;
        if (sortedDates.isNotEmpty) {
          int streak = 1;
          for (int i = 1; i < sortedDates.length; i++) {
            final diff =
                sortedDates[i].difference(sortedDates[i - 1]).inDays;
            if (diff == 1) {
              streak++;
            } else {
              if (streak > longestStreak) longestStreak = streak;
              streak = 1;
            }
          }
          if (streak > longestStreak) longestStreak = streak;

          // Current streak: count backwards from today
          final today = ReadingHistoryDateRange.startOfDay(DateTime.now());
          final yesterday = today.subtract(const Duration(days: 1));
          if (sortedDates.last == today || sortedDates.last == yesterday) {
            currentStreak = 1;
            for (int i = sortedDates.length - 2; i >= 0; i--) {
              final diff =
                  sortedDates[i + 1].difference(sortedDates[i]).inDays;
              if (diff == 1) {
                currentStreak++;
              } else {
                break;
              }
            }
          }
        }

        if (_selectedView == 'chart') {
          return _buildYearChart(logs);
        }

        return SingleChildScrollView(
          padding: LumiPadding.allS,
          child: Column(
            children: [
              // Hero card — Total Reading Time
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: LumiSpacing.l,
                  horizontal: LumiSpacing.m,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: LumiBorders.medium,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.rosePink.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.timer_rounded,
                      size: 36,
                      color: AppColors.white.withValues(alpha: 0.9),
                    ),
                    LumiGap.xs,
                    Text(
                      ReadingHistoryDateRange.formatDurationMinutes(
                          totalMinutes),
                      style: LumiTextStyles.display(color: AppColors.white),
                    ),
                    LumiGap.xxs,
                    Text(
                      'Total Reading Time',
                      style: LumiTextStyles.body().copyWith(
                        color: AppColors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              LumiGap.s,

              // Books Read + Reading Days row
              Row(
                children: [
                  Expanded(
                    child: _AllTimeStatTile(
                      icon: Icons.menu_book_rounded,
                      value: totalBooks.toString(),
                      label: 'Books Read',
                      backgroundColor:
                          AppColors.rosePink.withValues(alpha: 0.1),
                      iconColor: AppColors.rosePink,
                    ),
                  ),
                  LumiGap.horizontalS,
                  Expanded(
                    child: _AllTimeStatTile(
                      icon: Icons.calendar_today_rounded,
                      value: readingDays.toString(),
                      label: 'Reading Days',
                      backgroundColor:
                          AppColors.skyBlue.withValues(alpha: 0.3),
                      iconColor: AppColors.info,
                    ),
                  ),
                ],
              ),
              LumiGap.s,

              // Avg per Day — full width
              _AllTimeStatTile(
                icon: Icons.trending_up_rounded,
                value: ReadingHistoryDateRange.formatDurationMinutes(
                    averageMinutes),
                label: 'Average per Reading Day',
                backgroundColor:
                    AppColors.mintGreen.withValues(alpha: 0.2),
                iconColor: AppColors.secondaryGreen,
              ),
              LumiGap.s,

              // Most Read Book
              if (mostReadBook != null && mostReadCount > 1) ...[
                LumiCard(
                  padding: LumiPadding.allS,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.softYellow.withValues(alpha: 0.4),
                          borderRadius: LumiBorders.medium,
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFE6A800),
                          size: 24,
                        ),
                      ),
                      LumiGap.horizontalS,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Favourite Book',
                              style: LumiTextStyles.bodySmall().copyWith(
                                color: AppColors.charcoal
                                    .withValues(alpha: 0.5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            LumiGap.xxs,
                            Text(
                              mostReadBook!,
                              style: LumiTextStyles.h3(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Read $mostReadCount times',
                              style: LumiTextStyles.bodySmall().copyWith(
                                color: AppColors.charcoal
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                LumiGap.s,
              ],

              // Reading Streak
              if (longestStreak > 1 || currentStreak > 0) ...[
                LumiCard(
                  padding: LumiPadding.allS,
                  child: Row(
                    children: [
                      // Current streak
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.warmOrange
                                    .withValues(alpha: 0.12),
                                borderRadius: LumiBorders.medium,
                              ),
                              child: const Icon(
                                Icons.local_fire_department_rounded,
                                color: AppColors.warmOrange,
                                size: 24,
                              ),
                            ),
                            LumiGap.xs,
                            Text(
                              '$currentStreak',
                              style: LumiTextStyles.h2().copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Day Streak',
                              style: LumiTextStyles.bodySmall().copyWith(
                                color: AppColors.charcoal
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 60,
                        color: AppColors.charcoal.withValues(alpha: 0.1),
                      ),
                      // Longest streak
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.15),
                                borderRadius: LumiBorders.medium,
                              ),
                              child: Icon(
                                Icons.emoji_events_rounded,
                                color: AppColors.gold,
                                size: 24,
                              ),
                            ),
                            LumiGap.xs,
                            Text(
                              '$longestStreak',
                              style: LumiTextStyles.h2().copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Best Streak',
                              style: LumiTextStyles.bodySmall().copyWith(
                                color: AppColors.charcoal
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyBooksView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.studentId)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildQueryErrorState(
            context,
            'Couldn\'t load book history.',
            snapshot.error,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];
        if (logs.isEmpty) {
          return _buildEmptyState('No books logged yet');
        }

        final books = <String, _BookHistoryItem>{};
        for (final log in logs) {
          for (final title in log.bookTitles) {
            final key = title.trim();
            if (key.isEmpty) continue;
            final existing = books[key];
            if (existing == null) {
              books[key] = _BookHistoryItem(
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

        // Kick off metadata resolution for all unique titles
        final titles = books.keys.toList();
        _metadataResolver.resolveAll(titles);

        // Apply search filter
        var filteredBooks = books.values.toList();
        if (_myBooksSearchQuery.isNotEmpty) {
          final query = _myBooksSearchQuery.toLowerCase();
          filteredBooks = filteredBooks.where((book) {
            final metadata = _metadataResolver.getCached(book.title);
            final displayTitle =
                (metadata?.title ?? book.title).toLowerCase();
            final author = (metadata?.author ?? '').toLowerCase();
            return displayTitle.contains(query) || author.contains(query);
          }).toList();
        }

        // Apply sort
        switch (_myBooksSortMode) {
          case _MyBooksSortMode.lastRead:
            filteredBooks
                .sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
          case _MyBooksSortMode.mostRead:
            filteredBooks.sort((a, b) => b.sessions.compareTo(a.sessions));
          case _MyBooksSortMode.alphabetical:
            filteredBooks.sort((a, b) {
              final aTitle =
                  _metadataResolver.getCached(a.title)?.title ?? a.title;
              final bTitle =
                  _metadataResolver.getCached(b.title)?.title ?? b.title;
              return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
            });
          case _MyBooksSortMode.totalTime:
            filteredBooks
                .sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));
        }

        // Split into currently reading (last 7 days) and previously read
        final now = DateTime.now();
        final recentCutoff = now.subtract(const Duration(days: 7));
        final currentlyReading = filteredBooks
            .where((b) => b.lastReadAt.isAfter(recentCutoff))
            .toList();
        final previouslyRead = filteredBooks
            .where((b) => !b.lastReadAt.isAfter(recentCutoff))
            .toList();

        return Column(
          children: [
            _buildMyBooksToolbar(),
            Expanded(
              child: filteredBooks.isEmpty
                  ? _buildEmptyState(
                      _myBooksSearchQuery.isNotEmpty
                          ? 'No books match your search'
                          : 'No books logged yet',
                    )
                  : _myBooksView == 'grid'
                      ? _buildMyBooksGrid(filteredBooks)
                      : _buildMyBooksList(
                          currentlyReading,
                          previouslyRead,
                        ),
            ),
          ],
        );
      },
    );
  }

  // ── My Books toolbar: search + sort chips + view toggle ──

  Widget _buildMyBooksToolbar() {
    return Container(
      color: AppColors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsible search bar
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isSearchVisible
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      LumiSpacing.s, LumiSpacing.xs, LumiSpacing.s, 0,
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search books...',
                        hintStyle: LumiTextStyles.body().copyWith(
                          color: AppColors.charcoal.withValues(alpha: 0.4),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.charcoal.withValues(alpha: 0.4),
                        ),
                        suffixIcon: _myBooksSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _myBooksSearchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: LumiBorders.medium,
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: LumiSpacing.s,
                          vertical: LumiSpacing.xs,
                        ),
                      ),
                      style: LumiTextStyles.body(),
                      onChanged: (value) {
                        setState(() => _myBooksSearchQuery = value);
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Sort chips + toggles row
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: LumiSpacing.s,
              vertical: LumiSpacing.xs,
            ),
            child: Row(
              children: [
                _buildToolbarIcon(
                  icon: Icons.search,
                  isActive: _isSearchVisible,
                  onTap: () {
                    setState(() {
                      _isSearchVisible = !_isSearchVisible;
                      if (!_isSearchVisible) {
                        _searchController.clear();
                        _myBooksSearchQuery = '';
                      }
                    });
                  },
                ),
                SizedBox(width: LumiSpacing.xs),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSortChip('Recent', _MyBooksSortMode.lastRead),
                        SizedBox(width: LumiSpacing.xxs),
                        _buildSortChip(
                            'Most Read', _MyBooksSortMode.mostRead),
                        SizedBox(width: LumiSpacing.xxs),
                        _buildSortChip(
                            'A-Z', _MyBooksSortMode.alphabetical),
                        SizedBox(width: LumiSpacing.xxs),
                        _buildSortChip(
                            'Total Time', _MyBooksSortMode.totalTime),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: LumiSpacing.xs),
                _buildToolbarIcon(
                  icon: _myBooksView == 'list'
                      ? Icons.grid_view
                      : Icons.view_list_rounded,
                  isActive: false,
                  onTap: () {
                    setState(() {
                      _myBooksView =
                          _myBooksView == 'list' ? 'grid' : 'list';
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.rosePink.withValues(alpha: 0.1)
              : AppColors.background,
          borderRadius: LumiBorders.small,
        ),
        child: Icon(
          icon,
          size: 20,
          color: isActive
              ? AppColors.rosePink
              : AppColors.charcoal.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, _MyBooksSortMode mode) {
    final isSelected = _myBooksSortMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _myBooksSortMode = mode),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: LumiSpacing.xs + 2,
          vertical: LumiSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.rosePink : AppColors.background,
          borderRadius: LumiBorders.circular,
        ),
        child: Text(
          label,
          style: LumiTextStyles.label().copyWith(
            color: isSelected
                ? AppColors.white
                : AppColors.charcoal.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ── List view with Currently Reading / Previously Read sections ──

  Widget _buildMyBooksList(
    List<_BookHistoryItem> currentlyReading,
    List<_BookHistoryItem> previouslyRead,
  ) {
    return ListView(
      padding: LumiPadding.allS,
      children: [
        if (currentlyReading.isNotEmpty) ...[
          _buildSectionHeader('Currently Reading'),
          ...currentlyReading.map((book) => _buildBookListCard(book)),
        ],
        if (previouslyRead.isNotEmpty) ...[
          if (currentlyReading.isNotEmpty) SizedBox(height: LumiSpacing.s),
          _buildSectionHeader('Previously Read'),
          ...previouslyRead.map((book) => _buildBookListCard(book)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: LumiSpacing.xs,
        top: LumiSpacing.xxs,
      ),
      child: Text(
        title,
        style: LumiTextStyles.overline().copyWith(
          color: AppColors.charcoal.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildBookListCard(_BookHistoryItem book) {
    final metadata = _metadataResolver.getCached(book.title);
    final resolved = _metadataResolver.isResolved(book.title);
    final coverUrl = metadata?.coverImageUrl;
    final author = metadata?.author;
    final displayTitle = metadata?.title ?? book.title;

    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.xs),
      child: GestureDetector(
        onLongPress: () => _showBookDetailSheet(context, book),
        child: LumiCard(
          padding: LumiPadding.allS,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: LumiBorders.medium,
                child: SizedBox(
                  width: 70,
                  height: 90,
                  child: coverUrl != null && coverUrl.startsWith('http')
                      ? Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _buildBookPlaceholder(book.title),
                        )
                      : _buildBookPlaceholder(
                          book.title,
                          isLoading: !resolved,
                        ),
                ),
              ),
              LumiGap.horizontalS,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: LumiTextStyles.h3(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (author != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        author,
                        style: LumiTextStyles.caption().copyWith(
                          color: AppColors.charcoal.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${book.sessions} session${book.sessions == 1 ? '' : 's'} • ${ReadingHistoryDateRange.formatDurationMinutes(book.totalMinutes)}',
                      style: LumiTextStyles.bodySmall().copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                DateFormat('d MMM').format(book.lastReadAt),
                style: LumiTextStyles.caption(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Grid view (bookshelf) ──

  Widget _buildMyBooksGrid(List<_BookHistoryItem> books) {
    return GridView.builder(
      padding: LumiPadding.allS,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final metadata = _metadataResolver.getCached(book.title);
        final resolved = _metadataResolver.isResolved(book.title);
        final coverUrl = metadata?.coverImageUrl;
        final displayTitle = metadata?.title ?? book.title;
        final author = metadata?.author;

        return GestureDetector(
          onLongPress: () => _showBookDetailSheet(context, book),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: LumiBorders.medium,
                  child: SizedBox(
                    width: double.infinity,
                    child: coverUrl != null && coverUrl.startsWith('http')
                        ? Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildBookPlaceholder(book.title),
                          )
                        : _buildBookPlaceholder(
                            book.title,
                            isLoading: !resolved,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                displayTitle,
                style: LumiTextStyles.label().copyWith(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (author != null)
                Text(
                  author,
                  style: LumiTextStyles.caption().copyWith(
                    color: AppColors.charcoal.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Book placeholder with letter avatar ──

  static const _placeholderColors = [
    AppColors.rosePink,
    Color(0xFF6FA8DC),
    Color(0xFF7CB97C),
    Color(0xFFF5A347),
    Color(0xFFE86B6B),
    Color(0xFF9B8EC4),
  ];

  Color _bookPlaceholderColor(String title) {
    return _placeholderColors[title.hashCode.abs() % _placeholderColors.length];
  }

  Widget _buildBookPlaceholder(String title, {bool isLoading = false}) {
    final color = _bookPlaceholderColor(title);
    final letter = title.isNotEmpty ? title[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.15),
          ],
        ),
      ),
      child: Center(
        child: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color.withValues(alpha: 0.6),
                ),
              )
            : Text(
                letter,
                style: LumiTextStyles.h1().copyWith(
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  // ── Long-press book detail bottom sheet ──

  void _showBookDetailSheet(BuildContext context, _BookHistoryItem book) {
    final metadata = _metadataResolver.getCached(book.title);
    final coverUrl = metadata?.coverImageUrl;
    final displayTitle = metadata?.title ?? book.title;
    final author = metadata?.author;
    final description = metadata?.description;
    final publisher = metadata?.publisher;
    final pageCount = metadata?.pageCount;
    final genres = metadata?.genres ?? [];
    final readingLevel = metadata?.readingLevel;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(LumiSpacing.m),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: EdgeInsets.only(top: LumiSpacing.xs),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.charcoal.withValues(alpha: 0.2),
                    borderRadius: LumiBorders.circular,
                  ),
                ),
              ),
              // Header: cover + title
              Padding(
                padding: EdgeInsets.fromLTRB(
                  LumiSpacing.m, LumiSpacing.s, LumiSpacing.m, 0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: LumiBorders.medium,
                      child: SizedBox(
                        width: 90,
                        height: 120,
                        child: coverUrl != null && coverUrl.startsWith('http')
                            ? Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _buildBookPlaceholder(book.title),
                              )
                            : _buildBookPlaceholder(book.title),
                      ),
                    ),
                    LumiGap.horizontalS,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: LumiTextStyles.h2(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (author != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              author,
                              style: LumiTextStyles.body().copyWith(
                                color: AppColors.charcoal
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                          if (publisher != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              publisher,
                              style: LumiTextStyles.caption().copyWith(
                                color: AppColors.charcoal
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              LumiGap.s,
              Divider(
                height: 1,
                color: AppColors.charcoal.withValues(alpha: 0.1),
              ),
              // Scrollable detail content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(LumiSpacing.m),
                  children: [
                    // Reading stats row
                    Row(
                      children: [
                        _buildDetailStat(
                          Icons.menu_book_rounded,
                          '${book.sessions}',
                          book.sessions == 1 ? 'Session' : 'Sessions',
                        ),
                        SizedBox(width: LumiSpacing.xs),
                        _buildDetailStat(
                          Icons.timer,
                          ReadingHistoryDateRange.formatDurationMinutes(
                              book.totalMinutes),
                          'Total Time',
                        ),
                        SizedBox(width: LumiSpacing.xs),
                        _buildDetailStat(
                          Icons.timer_outlined,
                          ReadingHistoryDateRange.formatDurationMinutes(
                            book.sessions > 0
                                ? book.totalMinutes ~/ book.sessions
                                : 0,
                          ),
                          'Avg / Session',
                        ),
                      ],
                    ),
                    LumiGap.s,
                    // Date chips
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateChip(
                            'First read',
                            DateFormat('d MMM yyyy').format(book.firstReadAt),
                          ),
                        ),
                        SizedBox(width: LumiSpacing.xs),
                        Expanded(
                          child: _buildDateChip(
                            'Last read',
                            DateFormat('d MMM yyyy').format(book.lastReadAt),
                          ),
                        ),
                      ],
                    ),
                    // Tags: reading level + genres
                    if (readingLevel != null || genres.isNotEmpty) ...[
                      LumiGap.s,
                      Wrap(
                        spacing: LumiSpacing.xxs,
                        runSpacing: LumiSpacing.xxs,
                        children: [
                          if (readingLevel != null)
                            _buildTag(
                                'Level $readingLevel', AppColors.rosePink),
                          ...genres.take(4).map(
                                (g) => _buildTag(g, const Color(0xFF6FA8DC)),
                              ),
                        ],
                      ),
                    ],
                    if (pageCount != null) ...[
                      LumiGap.s,
                      Text(
                        '$pageCount pages',
                        style: LumiTextStyles.caption().copyWith(
                          color: AppColors.charcoal.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                    if (description != null && description.isNotEmpty) ...[
                      LumiGap.s,
                      Text(
                        'About this book',
                        style: LumiTextStyles.overline().copyWith(
                          color: AppColors.charcoal.withValues(alpha: 0.5),
                        ),
                      ),
                      LumiGap.xs,
                      Text(
                        description,
                        style: LumiTextStyles.body().copyWith(
                          color: AppColors.charcoal.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailStat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: LumiSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: LumiBorders.medium,
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.rosePink),
            const SizedBox(height: 4),
            Text(
              value,
              style: LumiTextStyles.h3()
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: LumiTextStyles.caption().copyWith(
                color: AppColors.charcoal.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: LumiSpacing.xs,
        vertical: LumiSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: LumiBorders.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LumiTextStyles.caption().copyWith(
              color: AppColors.charcoal.withValues(alpha: 0.4),
            ),
          ),
          Text(
            value,
            style: LumiTextStyles.bodySmall()
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: LumiSpacing.xs,
        vertical: LumiSpacing.xxs - 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: LumiBorders.circular,
      ),
      child: Text(
        label,
        style: LumiTextStyles.caption().copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLogsList(List<ReadingLogModel> logs, String emptyMessage) {
    if (logs.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }

    return ListView.builder(
      padding: LumiPadding.allS,
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _LogCard(log: log);
      },
    );
  }

  Widget _buildWeekChart(List<ReadingLogModel> logs, DateTime startOfWeek) {
    final Map<int, int> minutesByDay = {};
    for (int i = 0; i < 7; i++) {
      minutesByDay[i] = 0;
    }

    for (final log in logs) {
      final dayIndex = log.date.difference(startOfWeek).inDays;
      if (dayIndex >= 0 && dayIndex < 7) {
        minutesByDay[dayIndex] =
            (minutesByDay[dayIndex] ?? 0) + log.minutesRead;
      }
    }

    final maxMinutes = minutesByDay.values.isEmpty
        ? 30
        : minutesByDay.values.reduce((a, b) => a > b ? a : b);
    final interval = _calculateAxisInterval(maxMinutes.toDouble());

    return Padding(
      padding: LumiPadding.allS,
      child: Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                barGroups: List.generate(7, (index) {
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: (minutesByDay[index] ?? 0).toDouble(),
                        color: AppColors.rosePink,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final date =
                            startOfWeek.add(Duration(days: value.toInt()));
                        return Text(
                          DateFormat('E').format(date).substring(0, 1),
                          style: LumiTextStyles.bodySmall(),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: interval,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _formatAxisMinutes(value.toInt()),
                          style:
                              LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: true, horizontalInterval: interval),
              ),
            ),
          ),
          LumiGap.s,
          Text(
            'Total: ${minutesByDay.values.fold(0, (a, b) => a + b)} minutes',
            style: LumiTextStyles.h3(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthChart(List<ReadingLogModel> logs, DateTime startOfMonth,
      DateTime startOfNextMonth) {
    final daysInMonth = startOfNextMonth.subtract(const Duration(days: 1)).day;
    final Map<int, int> minutesByDay = {};

    for (final log in logs) {
      minutesByDay[log.date.day] =
          (minutesByDay[log.date.day] ?? 0) + log.minutesRead;
    }

    final List<FlSpot> spots = [];
    for (int day = 1; day <= daysInMonth; day++) {
      spots.add(FlSpot(day.toDouble(), (minutesByDay[day] ?? 0).toDouble()));
    }

    final maxMinutes = minutesByDay.values.isEmpty
        ? 30
        : minutesByDay.values.reduce((a, b) => a > b ? a : b);
    final interval = _calculateAxisInterval(maxMinutes.toDouble());

    return Padding(
      padding: LumiPadding.allS,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.rosePink,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: spot.y > 0 ? 4 : 0,
                    color: AppColors.rosePink,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.rosePink.withValues(alpha: 0.1),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatAxisMinutes(value.toInt()),
                    style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: true, horizontalInterval: interval),
        ),
      ),
    );
  }

  Widget _buildYearChart(List<ReadingLogModel> logs) {
    // Group logs by month
    final Map<String, int> minutesByMonth = {};

    for (final log in logs) {
      final monthKey = DateFormat('MMM').format(log.date);
      minutesByMonth[monthKey] =
          (minutesByMonth[monthKey] ?? 0) + log.minutesRead;
    }

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final currentMonth = DateTime.now().month;
    final maxMinutes = minutesByMonth.values.isEmpty
        ? 30
        : minutesByMonth.values.reduce((a, b) => a > b ? a : b);
    final interval = _calculateAxisInterval(maxMinutes.toDouble());

    return Padding(
      padding: LumiPadding.allS,
      child: BarChart(
        BarChartData(
          barGroups: List.generate(currentMonth, (index) {
            final month = months[index];
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: (minutesByMonth[month] ?? 0).toDouble(),
                  color: AppColors.rosePink,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() < currentMonth) {
                    return Text(
                      months[value.toInt()],
                      style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatAxisMinutes(value.toInt()),
                    style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: true, horizontalInterval: interval),
        ),
      ),
    );
  }

  /// Returns a sensible Y-axis interval based on the max value in minutes.
  double _calculateAxisInterval(double maxValue) {
    if (maxValue <= 30) return 10;
    if (maxValue <= 60) return 15;
    if (maxValue <= 120) return 30;
    if (maxValue <= 300) return 60;
    return (maxValue / 5).ceilToDouble();
  }

  /// Formats minutes for axis labels: "15m", "1h", "1h 30m".
  String _formatAxisMinutes(int minutes) {
    if (minutes == 0) return '0';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _buildRangeHeader(String label) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: EdgeInsets.symmetric(
        horizontal: LumiSpacing.s,
        vertical: LumiSpacing.xs,
      ),
      child: Text(
        label,
        style: LumiTextStyles.caption().copyWith(
          color: AppColors.charcoal.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildQueryErrorState(
      BuildContext context, String message, Object? error) {
    return Center(
      child: Padding(
        padding: LumiPadding.allS,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 56,
              color: AppColors.error,
            ),
            LumiGap.s,
            Text(
              message,
              textAlign: TextAlign.center,
              style: LumiTextStyles.h3(),
            ),
            LumiGap.xs,
            Text(
              'Pull to refresh or try again.',
              textAlign: TextAlign.center,
              style: LumiTextStyles.bodySmall().copyWith(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            if (kDebugMode && error != null) ...[
              LumiGap.s,
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style:
                    LumiTextStyles.caption().copyWith(color: AppColors.error),
              ),
            ],
            LumiGap.s,
            LumiTextButton(
              onPressed: () => setState(() {}),
              text: 'Retry',
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 64,
            color: AppColors.charcoal.withValues(alpha: 0.5),
          ),
          LumiGap.s,
          Text(
            message,
            style: LumiTextStyles.h3().copyWith(
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final ReadingLogModel log;

  const _LogCard({required this.log});

  void _showSessionDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SessionDetailSheet(log: log),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultipleBooks = log.bookTitles.length > 1;
    final extraCount = log.bookTitles.length - 1;

    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.xs),
      child: GestureDetector(
        onTap: () => _showSessionDetail(context),
        child: LumiCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Container(
              width: 48,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.rosePink.withValues(alpha: 0.1),
                borderRadius: LumiBorders.medium,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('dd').format(log.date),
                    style: LumiTextStyles.h3().copyWith(
                      color: AppColors.rosePink,
                    ),
                  ),
                  Text(
                    DateFormat('MMM').format(log.date),
                    style: LumiTextStyles.bodySmall().copyWith(
                      color: AppColors.rosePink,
                    ),
                  ),
                ],
              ),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    hasMultipleBooks
                        ? log.bookTitles.first
                        : log.bookTitles.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LumiTextStyles.h3(),
                  ),
                ),
                if (hasMultipleBooks) ...[
                  LumiGap.horizontalXXS,
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: LumiSpacing.xxs + 2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.rosePink.withValues(alpha: 0.12),
                      borderRadius: LumiBorders.circular,
                    ),
                    child: Text(
                      '+$extraCount more',
                      style: LumiTextStyles.label().copyWith(
                        color: AppColors.rosePink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LumiGap.xxs,
              Row(
                children: [
                  Icon(
                    Icons.timer,
                    size: 16,
                    color: log.hasMetTarget
                        ? AppColors.mintGreen
                        : AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  LumiGap.horizontalXXS,
                  Text(
                    '${log.minutesRead} minutes',
                    style: LumiTextStyles.bodySmall().copyWith(
                      color: log.hasMetTarget
                          ? AppColors.mintGreen
                          : AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  if (log.hasMetTarget) ...[
                    LumiGap.horizontalXS,
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: LumiSpacing.xxs, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.1),
                        borderRadius: LumiBorders.circular,
                      ),
                      child: Text(
                        'Goal Met',
                        style: LumiTextStyles.label().copyWith(
                          color: AppColors.mintGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (log.notes != null && log.notes!.isNotEmpty) ...[
                LumiGap.xxs,
                Text(
                  log.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LumiTextStyles.bodySmall().copyWith(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (log.teacherComment != null) ...[
                LumiGap.xxs,
                Container(
                  padding: LumiPadding.allXS,
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.small,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.comment,
                        size: 16,
                        color: AppColors.info,
                      ),
                      LumiGap.horizontalXXS,
                      Expanded(
                        child: Text(
                          'Teacher: ${log.teacherComment}',
                          style: LumiTextStyles.bodySmall().copyWith(
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          trailing: log.isCompleted
              ? const Icon(
                  Icons.check_circle,
                  color: AppColors.mintGreen,
                )
              : Icon(
                  Icons.circle_outlined,
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
          ),
        ),
      ),
    );
  }
}

class _AllTimeStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color backgroundColor;
  final Color iconColor;

  const _AllTimeStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.backgroundColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return LumiCard(
      padding: LumiPadding.allS,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: LumiBorders.medium,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          LumiGap.horizontalS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: LumiTextStyles.h2().copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: LumiTextStyles.bodySmall().copyWith(
                    color: AppColors.charcoal.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookHistoryItem {
  final String title;
  final int totalMinutes;
  final int sessions;
  final DateTime lastReadAt;
  final DateTime firstReadAt;

  const _BookHistoryItem({
    required this.title,
    required this.totalMinutes,
    required this.sessions,
    required this.lastReadAt,
    required this.firstReadAt,
  });

  _BookHistoryItem copyWith({
    String? title,
    int? totalMinutes,
    int? sessions,
    DateTime? lastReadAt,
    DateTime? firstReadAt,
  }) {
    return _BookHistoryItem(
      title: title ?? this.title,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      sessions: sessions ?? this.sessions,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      firstReadAt: firstReadAt ?? this.firstReadAt,
    );
  }
}

class _SessionDetailSheet extends StatelessWidget {
  final ReadingLogModel log;

  const _SessionDetailSheet({required this.log});

  String _feelingAsset(ReadingFeeling feeling) {
    switch (feeling) {
      case ReadingFeeling.hard:
        return 'assets/blobs/blob-hard.png';
      case ReadingFeeling.tricky:
        return 'assets/blobs/blob-tricky.png';
      case ReadingFeeling.okay:
        return 'assets/blobs/blob-okay.png';
      case ReadingFeeling.good:
        return 'assets/blobs/blob-good.png';
      case ReadingFeeling.great:
        return 'assets/blobs/blob-great.png';
    }
  }

  String _feelingLabel(ReadingFeeling feeling) {
    return feeling.name[0].toUpperCase() + feeling.name.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.5],
      shouldCloseOnMinExtent: true,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiSpacing.s),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: EdgeInsets.only(top: LumiSpacing.xs),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.charcoal.withValues(alpha: 0.2),
                  borderRadius: LumiBorders.circular,
                ),
              ),
            ),
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(
                LumiSpacing.m, LumiSpacing.s, LumiSpacing.m, 0,
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.rosePink.withValues(alpha: 0.1),
                      borderRadius: LumiBorders.medium,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('dd').format(log.date),
                          style: LumiTextStyles.h3().copyWith(
                            color: AppColors.rosePink,
                          ),
                        ),
                        Text(
                          DateFormat('MMM').format(log.date),
                          style: LumiTextStyles.bodySmall().copyWith(
                            color: AppColors.rosePink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  LumiGap.horizontalS,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reading Session',
                          style: LumiTextStyles.h3(),
                        ),
                        LumiGap.xxs,
                        Row(
                          children: [
                            Icon(
                              Icons.timer,
                              size: 16,
                              color: log.hasMetTarget
                                  ? AppColors.mintGreen
                                  : AppColors.charcoal.withValues(alpha: 0.7),
                            ),
                            LumiGap.horizontalXXS,
                            Text(
                              '${log.minutesRead} minutes',
                              style: LumiTextStyles.bodySmall().copyWith(
                                color: log.hasMetTarget
                                    ? AppColors.mintGreen
                                    : AppColors.charcoal
                                        .withValues(alpha: 0.7),
                              ),
                            ),
                            if (log.hasMetTarget) ...[
                              LumiGap.horizontalXS,
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: LumiSpacing.xxs,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.mintGreen
                                      .withValues(alpha: 0.1),
                                  borderRadius: LumiBorders.circular,
                                ),
                                child: Text(
                                  'Goal Met',
                                  style: LumiTextStyles.label().copyWith(
                                    color: AppColors.mintGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            LumiGap.s,
            Divider(
              height: 1,
              color: AppColors.charcoal.withValues(alpha: 0.1),
            ),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.all(LumiSpacing.m),
                children: [
                  // Books section
                  Text(
                    log.bookTitles.length == 1
                        ? 'Book'
                        : 'Books (${log.bookTitles.length})',
                    style: LumiTextStyles.bodySmall().copyWith(
                      color: AppColors.charcoal.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  LumiGap.xs,
                  ...log.bookTitles.map(
                    (title) => Padding(
                      padding: EdgeInsets.only(bottom: LumiSpacing.xs),
                      child: LumiCard(
                        padding: EdgeInsets.symmetric(
                          horizontal: LumiSpacing.s,
                          vertical: LumiSpacing.xs + 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.menu_book_rounded,
                              size: 20,
                              color: AppColors.rosePink,
                            ),
                            LumiGap.horizontalS,
                            Expanded(
                              child: Text(
                                title,
                                style: LumiTextStyles.body().copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Child feeling
                  if (log.childFeeling != null) ...[
                    LumiGap.s,
                    Text(
                      'How it felt',
                      style: LumiTextStyles.bodySmall().copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    LumiGap.xs,
                    Row(
                      children: [
                        Image.asset(
                          _feelingAsset(log.childFeeling!),
                          width: 36,
                          height: 36,
                        ),
                        LumiGap.horizontalS,
                        Text(
                          _feelingLabel(log.childFeeling!),
                          style: LumiTextStyles.body(),
                        ),
                      ],
                    ),
                  ],
                  // Parent comment selections
                  if (log.parentCommentSelections.isNotEmpty) ...[
                    LumiGap.s,
                    Text(
                      'Parent feedback',
                      style: LumiTextStyles.bodySmall().copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    LumiGap.xs,
                    Wrap(
                      spacing: LumiSpacing.xs,
                      runSpacing: LumiSpacing.xs,
                      children: log.parentCommentSelections
                          .map(
                            (chip) => Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: LumiSpacing.xs + 2,
                                vertical: LumiSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.rosePink
                                    .withValues(alpha: 0.08),
                                borderRadius: LumiBorders.circular,
                              ),
                              child: Text(
                                chip,
                                style: LumiTextStyles.bodySmall().copyWith(
                                  color: AppColors.rosePink,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  // Parent notes
                  if (log.notes != null && log.notes!.isNotEmpty) ...[
                    LumiGap.s,
                    Text(
                      'Notes',
                      style: LumiTextStyles.bodySmall().copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    LumiGap.xs,
                    Text(
                      log.notes!,
                      style: LumiTextStyles.body().copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                  // Teacher comment
                  if (log.teacherComment != null) ...[
                    LumiGap.s,
                    Text(
                      'Teacher comment',
                      style: LumiTextStyles.bodySmall().copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    LumiGap.xs,
                    Container(
                      padding: LumiPadding.allS,
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: LumiBorders.small,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.comment,
                            size: 16,
                            color: AppColors.info,
                          ),
                          LumiGap.horizontalXS,
                          Expanded(
                            child: Text(
                              log.teacherComment!,
                              style: LumiTextStyles.body().copyWith(
                                color: AppColors.info,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
