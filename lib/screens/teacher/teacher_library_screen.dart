import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/tour/lumi_app_tour.dart';
import 'cover_crop_screen.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../core/widgets/lumi/persistent_cached_image.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../data/models/book_model.dart';
import '../../data/models/school_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/community_book_service.dart';
import '../../services/school_library_assignment_service.dart';
import '../../services/school_library_service.dart';
import '../../services/teacher_device_book_cache_service.dart';

/// Teacher Library Screen — school-wide book library.
///
/// All books are sourced from `schools/{schoolId}/books`, populated
/// automatically whenever any teacher scans a new ISBN.
class TeacherLibraryScreen extends StatefulWidget {
  const TeacherLibraryScreen({
    super.key,
    required this.teacher,
    SchoolLibraryService? libraryService,
    SchoolLibraryAssignmentService? assignmentService,
  })  : _libraryService = libraryService,
        _assignmentService = assignmentService;

  final UserModel teacher;
  final SchoolLibraryService? _libraryService;
  final SchoolLibraryAssignmentService? _assignmentService;

  @override
  State<TeacherLibraryScreen> createState() => _TeacherLibraryScreenState();
}

class _TeacherLibraryScreenState extends State<TeacherLibraryScreen> {
  late final SchoolLibraryService _libraryService;
  late final SchoolLibraryAssignmentService _assignmentService;
  final _searchController = TextEditingController();

  String _activeFilter = 'All';
  String _searchQuery = '';
  Set<String> _hiddenBookIds = {};

  // Paginated books — fetched in pages of [SchoolLibraryService.pageSize]
  // and appended to _books. The legacy real-time listener over the whole
  // collection was the main scaling problem this screen had — every open
  // re-subscribed to all 5k+ books and kept the listener live for the
  // session. The version-bump listener mentioned in the cost report is
  // intentionally deferred: pull-to-refresh covers the same need without
  // adding a new Firestore doc to the schema.
  final List<BookModel> _books = [];
  String? _cursor;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _loadingAll = false;
  Object? _loadError;

  // Header badge counts come from the server-maintained
  // schools/{id}/libraryMeta/counts doc, so the screen can render
  // accurate totals without loading every book client-side.
  LibraryCounts _counts = LibraryCounts.empty;

  // iPad-only grid density: number of columns to show. Large=3 / Medium=4 /
  // Small=5. Phones always use 3. Persisted per-school so a teacher's choice
  // sticks. Ignored on phones (see `_isTablet`).
  int _tabletColumns = _defaultTabletColumns;
  static const int _defaultTabletColumns = 4;
  static const int _minTabletColumns = 3;
  static const int _maxTabletColumns = 5;

  static const _filters = [
    'All',
    'Decodable',
    'Library',
    'Recently Added',
    'Hidden',
  ];

  String get _hiddenPrefsKey => 'hidden_books_${widget.teacher.schoolId ?? ''}';
  String get _densityPrefsKey =>
      'library_density_${widget.teacher.schoolId ?? ''}';

  @override
  void initState() {
    super.initState();
    _libraryService = widget._libraryService ?? SchoolLibraryService();
    _assignmentService = widget._assignmentService ??
        SchoolLibraryAssignmentService(
          staffId: widget.teacher.id,
          schoolWide: widget.teacher.role == UserRole.schoolAdmin,
        );
    _loadHiddenBooks();
    _loadDensity();
    _loadCounts();
    _loadNextPage();
  }

  Future<void> _loadCounts() async {
    final schoolId = widget.teacher.schoolId?.trim() ?? '';
    if (schoolId.isEmpty) return;
    try {
      final counts = await _libraryService.fetchCounts(schoolId);
      if (!mounted) return;
      setState(() => _counts = counts);
    } catch (_) {
      // Counts are non-critical UI — silently leave _counts at empty.
      // The next refresh / next library-screen open will try again.
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    final schoolId = widget.teacher.schoolId?.trim() ?? '';
    if (schoolId.isEmpty) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final page = await _libraryService.fetchBooksPage(
        schoolId,
        startAfterDocId: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _books.addAll(page.books);
        _cursor = page.lastDocId ?? _cursor;
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _books.clear();
      _cursor = null;
      _hasMore = true;
      _loadError = null;
    });
    await Future.wait([_loadCounts(), _loadNextPage()]);
  }

  /// Search filters the loaded books client-side, but pages load lazily (50 at
  /// a time), so a title on an unfetched page read as "No books match". When a
  /// search is active, drain the remaining pages once so the filter sees the
  /// whole library. Guarded against re-entry and no-progress (concurrent
  /// scroll load) so it can't busy-loop.
  Future<void> _loadAllRemaining() async {
    if (_loadingAll) return;
    _loadingAll = true;
    try {
      while (_hasMore && mounted && _loadError == null) {
        final before = _books.length;
        await _loadNextPage();
        if (_books.length == before) break; // no progress → stop
      }
    } finally {
      _loadingAll = false;
    }
  }

  Future<void> _loadHiddenBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_hiddenPrefsKey) ?? [];
    setState(() => _hiddenBookIds = ids.toSet());
  }

  Future<void> _loadDensity() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_densityPrefsKey);
    if (stored == null || !mounted) return;
    setState(() =>
        _tabletColumns = stored.clamp(_minTabletColumns, _maxTabletColumns));
  }

  Future<void> _setDensity(int columns) async {
    final clamped = columns.clamp(_minTabletColumns, _maxTabletColumns);
    if (clamped == _tabletColumns) return;
    setState(() => _tabletColumns = clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_densityPrefsKey, clamped);
  }

  Future<void> _toggleHideBook(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_hiddenBookIds.contains(bookId)) {
        _hiddenBookIds.remove(bookId);
      } else {
        _hiddenBookIds.add(bookId);
      }
    });
    await prefs.setStringList(_hiddenPrefsKey, _hiddenBookIds.toList());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAddBook() async {
    final changed = await context.push<bool>(
      '/teacher/community-scanner',
      extra: widget.teacher,
    );
    if (!mounted || changed != true) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = widget.teacher.schoolId?.trim() ?? '';
    if (schoolId.isEmpty) {
      return const _ErrorState(message: 'School ID not available.');
    }

    return SafeArea(
      child: Builder(
        builder: (context) {
          // Hard error from the first page fetch. Subsequent failures
          // (mid-pagination) surface as a retry footer instead.
          if (_loadError != null && _books.isEmpty) {
            return const _ErrorState(
                message: 'Could not load library. Please try again.');
          }

          final isLoading = _isLoading && _books.isEmpty;
          final allBooks = _books;

          // Hidden count is a property of *the user*, not the library —
          // it's the size of the SharedPreferences-backed hidden set,
          // independent of which books are currently loaded. This keeps
          // the badge stable across pagination.
          final hiddenCount = _hiddenBookIds.length;

          // For the Hidden filter, show hidden books; otherwise exclude them.
          // Filters apply over currently-loaded pages — see the Caveats
          // section of the PR for the UX implications.
          List<BookModel> visibleBooks;
          if (_activeFilter == 'Hidden') {
            visibleBooks =
                allBooks.where((b) => _hiddenBookIds.contains(b.id)).toList();
          } else {
            visibleBooks =
                allBooks.where((b) => !_hiddenBookIds.contains(b.id)).toList();
          }

          final filtered = _activeFilter == 'Hidden'
              ? _searchQuery.isEmpty
                  ? visibleBooks
                  : SchoolLibraryService.applyFilter(
                      books: visibleBooks,
                      filter: 'All',
                      searchQuery: _searchQuery,
                    )
              : SchoolLibraryService.applyFilter(
                  books: visibleBooks,
                  filter: _activeFilter,
                  searchQuery: _searchQuery,
                );

          // Chip counts. Prefer the server-maintained libraryMeta/counts doc
          // while paginating — it covers the whole library without loading
          // every page. But the doc isn't seeded for schools that had books
          // before the maintainLibraryCounts function shipped, so it reads a
          // misleading `total: 0` while the grid is clearly full. In that case
          // (and whenever we've already loaded every page) count the loaded
          // books directly so the chips never show 0 under a full grid.
          final bool docSeeded = _counts.total > 0;
          final bool useLoadedCounts = !_hasMore || !docSeeded;

          final int decodableCount;
          final int libraryCount;
          final int visibleCount;
          if (useLoadedCounts) {
            final loadedVisible =
                allBooks.where((b) => !_hiddenBookIds.contains(b.id)).toList();
            visibleCount = loadedVisible.length;
            decodableCount =
                loadedVisible.where(SchoolLibraryService.isDecodable).length;
            libraryCount = visibleCount - decodableCount;
          } else {
            // Server doc available and library not fully loaded — trust it,
            // subtracting the (small) hidden set as an approximation.
            decodableCount =
                (_counts.decodable - hiddenCount).clamp(0, _counts.decodable);
            libraryCount =
                (_counts.library - hiddenCount).clamp(0, _counts.library);
            visibleCount =
                (_counts.total - hiddenCount).clamp(0, _counts.total);
          }

          // iPad-only grid density. Phones always use 3 columns.
          final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
          final gridColumns = isTablet ? _tabletColumns : 3;

          return StreamBuilder<LibraryAssignmentSnapshot>(
            stream: _assignmentService.summaryStream(schoolId),
            builder: (context, assignmentSnapshot) {
              final assignmentSummary =
                  assignmentSnapshot.data ?? const LibraryAssignmentSnapshot();

              return ColoredBox(
                color: LumiTokens.cream,
                child: Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (_hasMore &&
                              !_isLoading &&
                              n.metrics.extentAfter < 600) {
                            _loadNextPage();
                          }
                          return false;
                        },
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // ── Header ────────────────────────────────────────────────
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: _LibraryHeader(
                                  isLoading: isLoading,
                                  visibleCount: visibleCount,
                                  decodableCount: decodableCount,
                                  hiddenCount: hiddenCount,
                                ),
                              ),
                            ),

                            // ── Search ────────────────────────────────────────────────
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: _LibrarySearchBar(
                                  controller: _searchController,
                                  query: _searchQuery,
                                  onChanged: (v) {
                                    setState(() => _searchQuery = v);
                                    // Searching must cover the whole library, not just
                                    // the pages scrolled-in so far.
                                    if (v.trim().isNotEmpty && _hasMore) {
                                      _loadAllRemaining();
                                    }
                                  },
                                  onClear: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                              ),
                            ),

                            // ── Filter chips (+ iPad density control) ──────────────────
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 0, 18),
                                child: SizedBox(
                                  height: 40,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _filters.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(width: 8),
                                          padding:
                                              const EdgeInsets.only(right: 16),
                                          itemBuilder: (context, i) {
                                            final f = _filters[i];
                                            return TeacherFilterChip(
                                              label: _filterLabel(
                                                f,
                                                visibleCount: visibleCount,
                                                decodableCount: decodableCount,
                                                libraryCount: libraryCount,
                                                hiddenCount: hiddenCount,
                                              ),
                                              isActive: _activeFilter == f,
                                              onTap: () => setState(
                                                  () => _activeFilter = f),
                                              icon: _filterIcon(f),
                                              activeColor: _filterColor(f),
                                              activeForegroundColor:
                                                  LumiTokens.ink,
                                            );
                                          },
                                        ),
                                      ),
                                      // iPad-only: choose how many books per row.
                                      if (isTablet)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8, right: 16),
                                          child: _DensityControl(
                                            columns: _tabletColumns,
                                            onChanged: _setDensity,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // ── Body ──────────────────────────────────────────────────
                            if (isLoading)
                              _buildSkeletonSliver(gridColumns)
                            else if (allBooks.isEmpty)
                              _buildEmptySliver()
                            else if (filtered.isEmpty)
                              _buildNoResultsSliver()
                            else if (_activeFilter == 'All' ||
                                _activeFilter == 'Decodable')
                              ..._buildTierSections(
                                filtered,
                                assignmentSummary: assignmentSummary,
                                columns: gridColumns,
                              )
                            else
                              _buildFlatGrid(
                                filtered,
                                assignmentSummary: assignmentSummary,
                                columns: gridColumns,
                              ),

                            const SliverToBoxAdapter(
                                child: SizedBox(height: 200)),
                          ],
                        ),
                      ),
                    ),
                    // ── Scan FAB ───────────────────────────────────────────
                    Positioned(
                      right: 16,
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 84,
                      child: LumiTourTarget(
                        id: 'teacher.library.addBook',
                        child: FloatingActionButton.extended(
                          heroTag: 'library_add_book_fab',
                          onPressed: _openAddBook,
                          backgroundColor: LumiTokens.yellow,
                          foregroundColor: LumiTokens.ink,
                          icon: const Icon(Icons.document_scanner_rounded),
                          label: Text(
                            'Add book',
                            style:
                                LumiType.button.copyWith(color: LumiTokens.ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _filterLabel(
    String filter, {
    required int visibleCount,
    required int decodableCount,
    required int libraryCount,
    required int hiddenCount,
  }) {
    switch (filter) {
      case 'All':
        return 'All $visibleCount';
      case 'Decodable':
        return 'Decodable $decodableCount';
      case 'Library':
        return 'Library $libraryCount';
      case 'Hidden':
        return hiddenCount > 0 ? 'Hidden $hiddenCount' : 'Hidden';
      default:
        return filter;
    }
  }

  IconData? _filterIcon(String filter) {
    switch (filter) {
      case 'All':
        return Icons.grid_view_rounded;
      case 'Decodable':
        return Icons.auto_stories_outlined;
      case 'Library':
        return Icons.local_library_outlined;
      case 'Recently Added':
        return Icons.schedule_rounded;
      case 'Hidden':
        return Icons.visibility_off_outlined;
      default:
        return null;
    }
  }

  Color? _filterColor(String filter) {
    // Library is the yellow section; active chips take the section accent.
    return LumiTokens.yellow;
  }

  // ── Tier sections (LLLL stages + library books) ──────────────────────────

  List<Widget> _buildTierSections(
    List<BookModel> books, {
    required LibraryAssignmentSnapshot assignmentSummary,
    required int columns,
  }) {
    final slivers = <Widget>[];
    final stageGroups = SchoolLibraryService.groupDecodableByStage(books);
    var sectionIndex = 0;

    for (final entry in stageGroups.entries) {
      // Colored divider between sections (skip first)
      if (sectionIndex > 0) {
        final dividerColor = Color(SchoolLibraryService.stageColor(entry.key));
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: _SectionDivider(color: dividerColor),
          ),
        ));
      }
      final headerWidget = Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: _StageSectionHeader(stage: entry.key, count: entry.value.length),
      );
      final animateHeaders = !MediaQuery.of(context).disableAnimations;
      slivers.add(SliverPersistentHeader(
        pinned: true,
        delegate: _StickySectionHeaderDelegate(
          child: animateHeaders
              ? headerWidget
                  .animate()
                  .fadeIn(
                    delay: Duration(milliseconds: sectionIndex * 80),
                    duration: 250.ms,
                    curve: Curves.easeOut,
                  )
                  .move(
                    begin: const Offset(-16, 0),
                    end: Offset.zero,
                    duration: 250.ms,
                    curve: Curves.easeOutCubic,
                  )
              : headerWidget,
        ),
      ));
      slivers.add(_bookGrid(entry.value,
          assignmentSummary: assignmentSummary, columns: columns));
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
      sectionIndex++;
    }

    if (_activeFilter == 'All') {
      final libBooks = SchoolLibraryService.libraryBooks(books);
      if (libBooks.isNotEmpty) {
        if (sectionIndex > 0) {
          slivers.add(SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
              child: _SectionDivider(color: LumiTokens.muted),
            ),
          ));
        }
        final libHeader = Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: _LibrarySectionHeader(count: libBooks.length),
        );
        final animateLib = !MediaQuery.of(context).disableAnimations;
        slivers.add(SliverPersistentHeader(
          pinned: true,
          delegate: _StickySectionHeaderDelegate(
            child: animateLib
                ? libHeader
                    .animate()
                    .fadeIn(
                      delay: Duration(milliseconds: sectionIndex * 80),
                      duration: 250.ms,
                      curve: Curves.easeOut,
                    )
                    .move(
                      begin: const Offset(-16, 0),
                      end: Offset.zero,
                      duration: 250.ms,
                      curve: Curves.easeOutCubic,
                    )
                : libHeader,
          ),
        ));
        slivers.add(_bookGrid(libBooks,
            assignmentSummary: assignmentSummary, columns: columns));
      }
    }

    return slivers;
  }

  Widget _buildFlatGrid(
    List<BookModel> books, {
    required LibraryAssignmentSnapshot assignmentSummary,
    required int columns,
  }) =>
      _bookGrid(books, assignmentSummary: assignmentSummary, columns: columns);

  SliverPadding _bookGrid(
    List<BookModel> books, {
    required LibraryAssignmentSnapshot assignmentSummary,
    required int columns,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final book = books[i];
            final assignedIds =
                assignmentSummary.assignedStudentIdsForBook(book).toList();
            final assignedCount = assignedIds.length;
            final card = Builder(
              builder: (cardContext) => _LibraryBookCard(
                book: book,
                currentAssignedCount: assignedCount,
                onTap: () => _showBookDetail(
                  book,
                  currentAssignedCount: assignedCount,
                  assignedStudentIds: assignedIds,
                ),
                onLongPress: () => _showBookContextMenu(
                  cardContext,
                  book,
                  currentAssignedCount: assignedCount,
                  assignedStudentIds: assignedIds,
                ),
              ),
            );

            if (MediaQuery.of(context).disableAnimations) return card;

            return card
                .animate()
                .fadeIn(
                  delay: Duration(milliseconds: (i % 9) * 30),
                  duration: 220.ms,
                  curve: Curves.easeOut,
                )
                .move(
                  begin: const Offset(0, 6),
                  end: Offset.zero,
                  duration: 220.ms,
                  curve: Curves.easeOutCubic,
                );
          },
          childCount: books.length,
        ),
      ),
    );
  }

  // ── Loading skeleton ─────────────────────────────────────────────────────

  Widget _buildSkeletonSliver(int columns) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, __) => const LumiSkeleton(borderRadius: 16),
          childCount: columns * 3,
        ),
      ),
    );
  }

  // ── Empty / no-results states ─────────────────────────────────────────────

  Widget _buildEmptySliver() {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return SliverFillRemaining(
      hasScrollBody: false,
      child: AnimatedSwitcher(
        duration: duration,
        child: Center(
          key: const ValueKey('empty-library'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            child: _LibraryStateCard(
              icon: Icons.menu_book_outlined,
              title: 'No books yet',
              message:
                  'Scan a book ISBN to start building a shared school library.',
              actionText: 'Add Book',
              onAction: _openAddBook,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoResultsSliver() {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return SliverFillRemaining(
      hasScrollBody: false,
      child: AnimatedSwitcher(
        duration: duration,
        child: Center(
          key: ValueKey('no-results-$_activeFilter-$_searchQuery'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            child: _LibraryStateCard(
              icon: Icons.search_off_rounded,
              title: 'No matches found',
              message: _searchQuery.isEmpty
                  ? 'There are no books in this filter yet.'
                  : 'No books match "$_searchQuery". Try another title, author, or ISBN.',
              actionText: _searchQuery.isEmpty ? null : 'Clear Search',
              onAction: _searchQuery.isEmpty
                  ? null
                  : () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
            ),
          ),
        ),
      ),
    );
  }

  void _showBookDetail(
    BookModel book, {
    required int currentAssignedCount,
    List<String> assignedStudentIds = const [],
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookDetailSheet(
        book: book,
        currentAssignedCount: currentAssignedCount,
        assignedStudentIds: assignedStudentIds,
        teacher: widget.teacher,
        isHidden: _hiddenBookIds.contains(book.id),
        onToggleHide: () async {
          await _toggleHideBook(book.id);
          if (mounted) Navigator.pop(context); // close sheet
        },
      ),
    );
  }

  void _showBookContextMenu(
    BuildContext cardContext,
    BookModel book, {
    required int currentAssignedCount,
    List<String> assignedStudentIds = const [],
  }) async {
    HapticFeedback.mediumImpact();
    final renderBox = cardContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(cardContext).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero, ancestor: overlay),
        renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final isHidden = _hiddenBookIds.contains(book.id);

    final result = await showMenu<String>(
      context: cardContext,
      position: position,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      color: LumiTokens.paper,
      elevation: 8,
      items: [
        const PopupMenuItem(
          value: 'detail',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18),
              SizedBox(width: 10),
              Text('View Details'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'hide',
          child: Row(
            children: [
              Icon(
                isHidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(isHidden ? 'Unhide' : 'Hide'),
            ],
          ),
        ),
        if (book.isbn != null && book.isbn!.isNotEmpty)
          PopupMenuItem(
            value: 'isbn',
            child: Row(
              children: [
                const Icon(Icons.copy_rounded, size: 18),
                const SizedBox(width: 10),
                Text('Copy ISBN'),
              ],
            ),
          ),
      ],
    );

    if (!mounted || result == null) return;

    switch (result) {
      case 'detail':
        _showBookDetail(
          book,
          currentAssignedCount: currentAssignedCount,
          assignedStudentIds: assignedStudentIds,
        );
        break;
      case 'hide':
        await _toggleHideBook(book.id);
        break;
      case 'isbn':
        await Clipboard.setData(ClipboardData(text: book.isbn!));
        showLumiToast(
          message: 'ISBN copied: ${book.isbn}',
          type: LumiToastType.success,
          duration: const Duration(seconds: 2),
        );
        break;
    }
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.isLoading,
    required this.visibleCount,
    required this.decodableCount,
    required this.hiddenCount,
  });

  final bool isLoading;
  final int visibleCount;
  final int decodableCount;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    // Lean ink hero on the cream page — yellow is too light for a white-on-fill
    // banner, so the section is branded by the nav + accents, not a hero box.
    // (The server total count is unreliable, so we frame the screen's purpose
    // rather than show a misleading number — the section header carries the
    // real loaded count.)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_library_rounded,
                size: 24, color: LumiTokens.yellow),
            const SizedBox(width: 8),
            Text('Library', style: LumiType.heading),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          "Browse your school's books",
          style: LumiType.body.copyWith(color: LumiTokens.muted),
        ),
        if (!isLoading && (decodableCount > 0 || hiddenCount > 0)) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (decodableCount > 0)
                _HeaderMetricPill(
                  icon: Icons.auto_stories_outlined,
                  label:
                      '$decodableCount decodable${decodableCount == 1 ? '' : 's'}',
                ),
              if (hiddenCount > 0)
                _HeaderMetricPill(
                  icon: Icons.visibility_off_outlined,
                  label: '$hiddenCount hidden',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeaderMetricPill extends StatelessWidget {
  const _HeaderMetricPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LumiTokens.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySearchBar extends StatefulWidget {
  const _LibrarySearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_LibrarySearchBar> createState() => _LibrarySearchBarState();
}

class _LibrarySearchBarState extends State<_LibrarySearchBar>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode;
  late final AnimationController _fillController;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _fillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _fillController.value = _focusNode.hasFocus ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _fillController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final targetValue = _focusNode.hasFocus ? 1.0 : 0.0;

    if (MediaQuery.of(context).disableAnimations) {
      _fillController.value = targetValue;
    } else if (_focusNode.hasFocus) {
      _fillController.forward();
    } else {
      _fillController.reverse();
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.query.isNotEmpty;
    final isActive = hasQuery || _focusNode.hasFocus;
    final borderRadius = BorderRadius.circular(LumiTokens.radiusLarge);

    return Container(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: borderRadius,
        border: Border.all(color: LumiTokens.rule, width: 1.2),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _fillController,
                builder: (context, child) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const ValueKey('library_search_focus_fill'),
                      widthFactor: _fillController.value.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: child,
                    ),
                  );
                },
                child: ColoredBox(
                  color: LumiTokens.yellow.withValues(alpha: 0.16),
                ),
              ),
            ),
            TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.search,
              cursorColor: LumiTokens.ink,
              style: LumiType.body.copyWith(
                color: LumiTokens.ink,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search by title, author, or ISBN...',
                hintStyle: LumiType.body.copyWith(color: LumiTokens.muted),
                prefixIcon: AnimatedBuilder(
                  animation: _fillController,
                  builder: (context, child) {
                    final t = Curves.elasticOut
                        .transform(_fillController.value.clamp(0.0, 1.0));
                    return Transform.scale(
                      scale: 1.0 + 0.15 * t,
                      child: child,
                    );
                  },
                  child: Icon(
                    Icons.search_rounded,
                    color: isActive ? LumiTokens.yellow : LumiTokens.muted,
                  ),
                ),
                suffixIcon: hasQuery
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: LumiTokens.muted,
                        onPressed: widget.onClear,
                      )
                    : null,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryStateCard extends StatelessWidget {
  const _LibraryStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionText,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: LumiTokens.yellow.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            ),
            child: Icon(icon, size: 34, color: LumiTokens.yellow),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: LumiType.subhead,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: LumiType.body.copyWith(
              color: LumiTokens.muted,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: LumiTokens.yellow,
                foregroundColor: LumiTokens.ink,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                ),
              ),
              icon: Icon(
                actionText == 'Add Book'
                    ? Icons.document_scanner_rounded
                    : Icons.close_rounded,
                size: 18,
              ),
              label: Text(
                actionText!,
                style: LumiType.button.copyWith(color: LumiTokens.ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section headers
// ─────────────────────────────────────────────────────────────────────────────

class _StickySectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickySectionHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: overlapsContent || shrinkOffset > 0
          ? LumiTokens.cream.withValues(alpha: 0.96)
          : Colors.transparent,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickySectionHeaderDelegate oldDelegate) =>
      child != oldDelegate.child;
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: color.withValues(alpha: 0.18),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.50),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: color.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

class _StageSectionHeader extends StatelessWidget {
  const _StageSectionHeader({required this.stage, required this.count});

  final String stage;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Color(SchoolLibraryService.stageColor(stage));
    return _LibrarySectionTitle(
      title: stage,
      count: count,
      color: color,
      icon: Icons.auto_stories_outlined,
    );
  }
}

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _LibrarySectionTitle(
      title: 'Library Books',
      count: count,
      color: LumiTokens.yellow,
      icon: Icons.local_library_outlined,
    );
  }
}

class _LibrarySectionTitle extends StatelessWidget {
  const _LibrarySectionTitle({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String title;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LumiType.subhead.copyWith(fontSize: 17),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            border: Border.all(color: LumiTokens.rule),
          ),
          child: Text(
            '$count book${count == 1 ? '' : 's'}',
            style: LumiType.caption.copyWith(
              color: LumiTokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid book card
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryBookCard extends StatefulWidget {
  const _LibraryBookCard({
    required this.book,
    required this.currentAssignedCount,
    required this.onTap,
    this.onLongPress,
  });

  final BookModel book;
  final int currentAssignedCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_LibraryBookCard> createState() => _LibraryBookCardState();
}

class _LibraryBookCardState extends State<_LibraryBookCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 140),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _scaleController.forward();
    HapticFeedback.lightImpact();
  }

  void _onTapUp(TapUpDetails _) {
    _scaleController.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final isDecodable = SchoolLibraryService.isDecodable(book);
    final stageColor = isDecodable
        ? Color(SchoolLibraryService.stageColor(book.readingLevel ?? ''))
        : LumiTokens.yellow;
    final level = book.readingLevel?.trim() ?? '';
    final metaLabel = isDecodable
        ? (level.isNotEmpty ? 'Decodable · $level' : 'Decodable')
        : 'Library';

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: LumiTokens.shadowCard,
        ),
        child: Material(
          color: LumiTokens.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: LumiTokens.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            onLongPress: widget.onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _BookCoverWidget(
                    book: book,
                    stageColor: stageColor,
                    currentAssignedCount: widget.currentAssignedCount,
                  ),
                ),
                // Title + a compact category/level line. The small coloured dot
                // replaces the old decorative underline and now carries meaning
                // (decodable stage colour, or yellow for a library book).
                SizedBox(
                  height: 66,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            book.title,
                            style: LumiType.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: LumiTokens.ink,
                              height: 1.18,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: stageColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                metaLabel,
                                style: LumiType.caption.copyWith(
                                  color: LumiTokens.muted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookCoverWidget extends StatelessWidget {
  const _BookCoverWidget({
    required this.book,
    required this.stageColor,
    this.currentAssignedCount = 0,
  });

  final BookModel book;
  final Color stageColor;
  final int currentAssignedCount;

  @override
  Widget build(BuildContext context) {
    final hasCover = book.coverImageUrl?.startsWith('http') == true;
    final placeholder = _placeholder(stageColor, book.title);
    final isNew = DateTime.now().difference(book.createdAt).inHours < 24;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: stageColor.withValues(alpha: 0.15),
            child: hasCover
                ? PersistentCachedImage(
                    imageUrl: book.coverImageUrl!,
                    fit: BoxFit.cover,
                    fallback: placeholder,
                  )
                : placeholder,
          ),
        ),
        if (isNew)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: LumiTokens.yellow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'NEW',
                style: LumiType.caption.copyWith(
                  color: LumiTokens.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 8,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        if (currentAssignedCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Semantics(
              label:
                  '$currentAssignedCount ${currentAssignedCount == 1 ? 'student' : 'students'} assigned',
              child: _AssignedBadge(count: currentAssignedCount, compact: true),
            ),
          ),
      ],
    );
  }

  Widget _placeholder(Color color, String title) {
    final letter = title.isNotEmpty ? title[0].toUpperCase() : '';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.40),
            LumiTokens.paper.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Large watermark letter
          if (letter.isNotEmpty)
            Text(
              letter,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: LumiTokens.paper.withValues(alpha: 0.5),
                height: 1,
              ),
            ),
          // Small book icon below
          Positioned(
            bottom: 10,
            child: Icon(
              Icons.menu_book_rounded,
              color: color.withValues(alpha: 0.40),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedBadge extends StatelessWidget {
  const _AssignedBadge({
    required this.count,
    this.compact = false,
    this.showChevron = false,
  });

  final int count;
  final bool compact;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.paper.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: [
          BoxShadow(
            color: LumiTokens.ink.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_alt_outlined,
            size: compact ? 10 : 11,
            color: LumiTokens.ink,
          ),
          const SizedBox(width: 3),
          Text(
            compact ? '$count' : '$count assigned',
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 10 : 11,
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                size: 14, color: LumiTokens.muted),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error state
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _LibraryStateCard(
            icon: Icons.cloud_off_outlined,
            title: 'Library unavailable',
            message: message,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// iPad density control
// ─────────────────────────────────────────────────────────────────────────────

/// Compact segmented control (iPad only) letting a teacher choose how many
/// book covers appear per row: Large (3), Medium (4) or Small (5). On phones
/// the grid is always 3 columns and this control isn't shown.
class _DensityControl extends StatelessWidget {
  const _DensityControl({required this.columns, required this.onChanged});

  final int columns;
  final ValueChanged<int> onChanged;

  static const List<({int cols, IconData icon, String label})> _options = [
    (cols: 3, icon: Icons.grid_view_rounded, label: 'Large'),
    (cols: 4, icon: Icons.window_rounded, label: 'Medium'),
    (cols: 5, icon: Icons.apps_rounded, label: 'Small'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _options)
            _DensityButton(
              icon: o.icon,
              tooltip: '${o.label} — ${o.cols} per row',
              active: columns == o.cols,
              onTap: () => onChanged(o.cols),
            ),
        ],
      ),
    );
  }
}

class _DensityButton extends StatelessWidget {
  const _DensityButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? LumiTokens.yellow.withValues(alpha: 0.9)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? LumiTokens.ink : LumiTokens.muted,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Book Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class BookDetailSheet extends StatefulWidget {
  const BookDetailSheet({
    super.key,
    required this.book,
    required this.currentAssignedCount,
    required this.teacher,
    required this.isHidden,
    required this.onToggleHide,
    this.assignedStudentIds = const [],
  });

  final BookModel book;
  final int currentAssignedCount;
  final List<String> assignedStudentIds;
  final UserModel teacher;
  final bool isHidden;
  final VoidCallback onToggleHide;

  @override
  State<BookDetailSheet> createState() => _BookDetailSheetState();
}

class _BookDetailSheetState extends State<BookDetailSheet> {
  bool _isUploadingCover = false;
  String? _uploadedCoverUrl;
  bool _isCoverOwner = false;

  // School-level schema data, fetched once on open.
  String? _schoolLevelSchemaKey; // e.g. 'pmBenchmark', 'aToZ', 'none'
  List<String> _schoolLevels = [];
  bool _isSettingLevel = false;

  bool get _isCommunityBook =>
      widget.book.metadata?['source'] == 'community_books';

  // ── "Assigned to" — assigned-class visibility ─────────────────────────────

  /// Resolves assigned student IDs only within classes this teacher owns or
  /// co-teaches. School admins retain whole-school visibility.
  Future<List<_AssigneeClass>> _loadAssignees() async {
    final schoolId = widget.teacher.schoolId;
    final ids = widget.assignedStudentIds;
    if (schoolId == null || schoolId.isEmpty || ids.isEmpty) {
      return const [];
    }

    final fs = FirebaseFirestore.instance;
    final school = fs.collection('schools').doc(schoolId);
    final classesCol = school.collection('classes');
    final classNames = <String, String>{};

    if (widget.teacher.role == UserRole.schoolAdmin) {
      final snap = await classesCol.get();
      for (final doc in snap.docs) {
        final name = (doc.data()['name'] as String?)?.trim();
        classNames[doc.id] = (name != null && name.isNotEmpty) ? name : 'Class';
      }
    } else {
      final owned = await classesCol
          .where('teacherId', isEqualTo: widget.teacher.id)
          .get();
      final coTaught = await classesCol
          .where('teacherIds', arrayContains: widget.teacher.id)
          .get();
      for (final doc in [...owned.docs, ...coTaught.docs]) {
        final name = (doc.data()['name'] as String?)?.trim();
        classNames[doc.id] = (name != null && name.isNotEmpty) ? name : 'Class';
      }
    }

    if (classNames.isEmpty) return const [];

    final studentsCol = school.collection('students');

    final students = <StudentModel>[];
    for (final classId in classNames.keys) {
      for (var i = 0; i < ids.length; i += 10) {
        final end = (i + 10) > ids.length ? ids.length : i + 10;
        final snap = await studentsCol
            .where('classId', isEqualTo: classId)
            .where(FieldPath.documentId, whereIn: ids.sublist(i, end))
            .get();
        students.addAll(snap.docs.map(StudentModel.fromFirestore));
      }
    }

    final byClass = <String, List<StudentModel>>{};
    for (final s in students) {
      byClass.putIfAbsent(s.classId, () => <StudentModel>[]).add(s);
    }

    final result = byClass.entries.map((e) {
      final list = e.value
        ..sort((a, b) =>
            a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
      return _AssigneeClass(
        className: classNames[e.key] ?? 'Unknown class',
        students: list,
      );
    }).toList()
      ..sort((a, b) =>
          a.className.toLowerCase().compareTo(b.className.toLowerCase()));
    return result;
  }

  void _showAssignedToSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, controller) {
          return Container(
            decoration: const BoxDecoration(
              color: LumiTokens.paper,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(LumiTokens.radiusXL)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: LumiTokens.rule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.people_alt_rounded,
                              size: 20, color: LumiTokens.yellow),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Currently assigned to',
                                style: LumiType.subhead),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.book.title} · visible in your classes',
                        style:
                            LumiType.caption.copyWith(color: LumiTokens.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: LumiTokens.rule),
                Expanded(
                  child: FutureBuilder<List<_AssigneeClass>>(
                    future: _loadAssignees(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: LumiTokens.yellow),
                        );
                      }
                      final groups = snap.data ?? const [];
                      if (groups.isEmpty) {
                        return Center(
                          child: Text(
                            'No active assignments found',
                            style:
                                LumiType.body.copyWith(color: LumiTokens.muted),
                          ),
                        );
                      }
                      return ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, i) =>
                            _buildAssigneeClass(groups[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAssigneeClass(_AssigneeClass group) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.meeting_room_outlined,
                  size: 16, color: LumiTokens.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.className,
                  style: LumiType.body.copyWith(
                    color: LumiTokens.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${group.students.length}',
                style: LumiType.caption.copyWith(color: LumiTokens.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.students
                .map(
                  (s) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: LumiTokens.paper,
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusPill),
                      border: Border.all(color: LumiTokens.rule),
                    ),
                    child: Text(
                      _assigneeName(s),
                      style: LumiType.caption.copyWith(color: LumiTokens.ink),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  String _assigneeName(StudentModel s) {
    final last = s.lastName.trim();
    return last.isNotEmpty ? '${s.firstName} ${last[0]}.' : s.firstName;
  }

  bool get _hasCover {
    final url = _uploadedCoverUrl ?? widget.book.coverImageUrl;
    return url != null && url.startsWith('http');
  }

  @override
  void initState() {
    super.initState();
    _checkCoverOwnership();
    _fetchSchoolLevelData();
  }

  Future<void> _fetchSchoolLevelData() async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .get();
      if (!mounted) return;
      final data = doc.data();
      if (data == null) return;

      final school = SchoolModel.fromFirestore(doc);
      if (!mounted) return;
      setState(() {
        _schoolLevelSchemaKey = school.levelSchema.name; // e.g. 'pmBenchmark'
        _schoolLevels = school.readingLevels;
      });
    } catch (_) {
      // Best-effort — level display falls back to community value
    }
  }

  Future<void> _saveSchoolLevel(String level) async {
    final schoolId = widget.teacher.schoolId;
    final bookId = widget.book.id;
    if (schoolId == null || schoolId.isEmpty || bookId.isEmpty) return;
    setState(() => _isSettingLevel = true);
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('books')
          .doc(bookId)
          .update({'schoolReadingLevel': level});
    } catch (_) {
      // Ignore — user will see no change, can retry
    } finally {
      if (mounted) setState(() => _isSettingLevel = false);
    }
  }

  void _showSetLevelSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SetSchoolLevelSheet(
        levels: _schoolLevels,
        currentLevel: widget.book.schoolReadingLevel,
        onSelect: (level) {
          Navigator.pop(context);
          _saveSchoolLevel(level);
        },
      ),
    );
  }

  Future<void> _checkCoverOwnership() async {
    final isbn = widget.book.isbn;
    if (isbn == null || isbn.isEmpty || !_hasCover) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('community_books')
          .doc(isbn)
          .get();
      if (!mounted) return;

      final coverUploadedBy = doc.data()?['coverUploadedBy'] as String?;
      setState(() {
        _isCoverOwner = coverUploadedBy == widget.teacher.id;
      });
    } catch (_) {
      // Best-effort — if lookup fails, don't show edit button
    }
  }

  Future<void> _showAddCoverOptions() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LumiTokens.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Add Cover Photo', style: LumiType.subhead),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: LumiTokens.yellow),
              title: Text('Take Photo', style: LumiType.body),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: LumiTokens.yellow),
              title: Text('Choose from Gallery', style: LumiType.body),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final image = await picker.pickImage(source: source, imageQuality: 92);
    if (image == null || !mounted) return;

    final bytes = await File(image.path).readAsBytes();
    if (!mounted) return;

    final croppedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => CoverCropScreen(imageBytes: bytes),
      ),
    );
    if (croppedFile == null || !mounted) return;

    await _uploadCoverImage(croppedFile);
  }

  Future<void> _uploadCoverImage(File imageFile) async {
    final book = widget.book;
    final isbn = book.isbn;
    if (isbn == null || isbn.isEmpty) return;

    setState(() => _isUploadingCover = true);

    try {
      final communityService = CommunityBookService();
      final url = await communityService.uploadCoverImage(
        isbn: isbn,
        imageFile: imageFile,
        contributorId: widget.teacher.id,
        contributorSchoolId: widget.teacher.schoolId ?? '',
      );

      if (!mounted) return;

      if (url == null) {
        setState(() => _isUploadingCover = false);
        showLumiToast(
          message: 'Failed to upload cover image',
          type: LumiToastType.error,
        );
        return;
      }

      // Update community_books (global) so all schools benefit
      await communityService.addBook(
        isbn: isbn,
        title: book.title,
        contributorId: widget.teacher.id,
        contributorSchoolId: widget.teacher.schoolId ?? '',
        contributorName: widget.teacher.fullName,
        author: book.author,
        coverImageUrl: url,
        coverStoragePath: 'community_books/covers/$isbn.jpg',
        source: 'teacher_cover_upload',
        metadata: {'coverSource': 'camera_scan'},
      );

      // Track who uploaded the cover so only they can edit it later
      await FirebaseFirestore.instance
          .collection('community_books')
          .doc(isbn)
          .update({'coverUploadedBy': widget.teacher.id});

      // Update the school's local book document
      final schoolId = widget.teacher.schoolId;
      if (schoolId != null) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('books')
            .doc(book.id)
            .update({'coverImageUrl': url});

        // Update device cache
        try {
          final cacheService = TeacherDeviceBookCacheService.instance;
          await cacheService.cacheBook(
            teacherId: widget.teacher.id,
            schoolId: schoolId,
            book: book.copyWith(coverImageUrl: url),
          );
        } catch (_) {
          // Device cache update is best-effort
        }
      }

      if (!mounted) return;
      setState(() {
        _isUploadingCover = false;
        _uploadedCoverUrl = url;
        _isCoverOwner = true;
      });

      showLumiToast(
        message: 'Cover photo added! It will appear for all teachers.',
        type: LumiToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingCover = false);
      showLumiToast(
        message: 'Error adding cover: $e',
        type: LumiToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _uploadedCoverUrl != null
        ? widget.book.copyWith(coverImageUrl: _uploadedCoverUrl)
        : widget.book;
    final currentAssignedCount = widget.currentAssignedCount;
    final isDecodable = SchoolLibraryService.isDecodable(book);
    final stageColor = isDecodable
        ? Color(SchoolLibraryService.stageColor(book.readingLevel ?? ''))
        : LumiTokens.yellow;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
        initialChildSize: 0.64,
        minChildSize: 0.42,
        maxChildSize: 0.94,
        builder: (context, scrollController) {
          return GestureDetector(
            onTap: () {},
            child: Container(
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: LumiTokens.ink.withValues(alpha: 0.16),
                    blurRadius: 32,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 14),
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: LumiTokens.rule,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),

                  // Cover + basic info
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: LumiTokens.cream,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusXL),
                        border: Border.all(color: LumiTokens.rule),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: LumiTokens.ink.withValues(alpha: 0.10),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: 82,
                                height: 116,
                                child: _BookCoverWidget(
                                  book: book,
                                  stageColor: stageColor,
                                  currentAssignedCount: currentAssignedCount,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book.title,
                                  style: LumiType.subhead,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (book.author?.isNotEmpty == true) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    book.author!,
                                    style: LumiType.body.copyWith(
                                      color: LumiTokens.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 10),
                                _BookLevelBadgeRow(
                                  book: book,
                                  isDecodable: isDecodable,
                                  stageColor: stageColor,
                                  currentAssignedCount: currentAssignedCount,
                                  schoolLevelSchemaKey: _schoolLevelSchemaKey,
                                  onTapAssigned: currentAssignedCount > 0
                                      ? _showAssignedToSheet
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Add / Change Cover Photo button
                  // "Add" shown for any teacher when no cover exists
                  // "Change" shown only to the teacher who uploaded the current cover
                  if (book.isbn?.isNotEmpty == true &&
                      (!_hasCover || (_hasCover && _isCoverOwner)))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: _isUploadingCover
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: LumiTokens.yellow,
                                  ),
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _showAddCoverOptions,
                              icon: Icon(
                                _hasCover
                                    ? Icons.edit_outlined
                                    : Icons.add_a_photo_outlined,
                                size: 18,
                                color: LumiTokens.yellow,
                              ),
                              label: Text(
                                _hasCover
                                    ? 'Change Cover Photo'
                                    : 'Add Cover Photo',
                                style: LumiType.caption.copyWith(
                                  color: LumiTokens.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: LumiTokens.yellow),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      LumiTokens.radiusMedium),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                              ),
                            ),
                    ),

                  if (book.isbn?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _InfoRow(label: 'ISBN', value: book.isbn!),
                    ),

                  if (book.publisher?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child:
                          _InfoRow(label: 'Publisher', value: book.publisher!),
                    ),

                  if (book.description?.isNotEmpty == true) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: LumiTokens.cream,
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusLarge),
                          border: Border.all(color: LumiTokens.rule),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'About',
                              style: LumiType.body.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              book.description!,
                              style: LumiType.caption.copyWith(
                                color: LumiTokens.muted,
                                height: 1.5,
                              ),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Library actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: LumiTokens.paper,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusLarge),
                        border: Border.all(color: LumiTokens.rule),
                      ),
                      child: Column(
                        children: [
                          // Set school level — always visible so schools without a
                          // schema can still enter a free-form level.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _isSettingLevel
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: LumiTokens.yellow),
                                    ),
                                  )
                                : TextButton.icon(
                                    onPressed: _showSetLevelSheet,
                                    icon: const Icon(
                                      Icons.tune_rounded,
                                      size: 16,
                                      color: LumiTokens.yellow,
                                    ),
                                    label: Text(
                                      widget.book.schoolReadingLevel
                                                  ?.isNotEmpty ==
                                              true
                                          ? 'Change school level'
                                          : 'Set level for your school',
                                      style: LumiType.caption.copyWith(
                                        color: LumiTokens.ink,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: widget.onToggleHide,
                              icon: Icon(
                                widget.isHidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 16,
                                color: LumiTokens.muted,
                              ),
                              label: Text(
                                widget.isHidden
                                    ? 'Unhide from Library'
                                    : 'Hide from Library',
                                style: LumiType.caption.copyWith(
                                  color: LumiTokens.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          if (_isCommunityBook && book.isbn?.isNotEmpty == true)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _showDeletionRequestDialog,
                                icon: Icon(
                                  Icons.flag_outlined,
                                  size: 16,
                                  color: Colors.red.shade400,
                                ),
                                label: Text(
                                  'Request Deletion',
                                  style: LumiType.caption.copyWith(
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeletionRequestDialog() {
    String? selectedReason;
    final notesController = TextEditingController();
    bool isSubmitting = false;

    const reasons = [
      'Inappropriate content',
      'Duplicate entry',
      'Incorrect data / wrong book',
      'Low quality cover or metadata',
      'Other',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: LumiTokens.paper,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: LumiTokens.muted.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      'Request Book Deletion',
                      style: LumiType.subhead,
                    ),
                    const SizedBox(height: 8),

                    // Description
                    Text(
                      'This will send a request to Lumi to remove this book from the community library.',
                      style: LumiType.caption.copyWith(color: LumiTokens.muted),
                    ),
                    const SizedBox(height: 20),

                    // Reason dropdown
                    Text('Reason',
                        style:
                            LumiType.caption.copyWith(color: LumiTokens.ink)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: LumiTokens.cream,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
                        border: Border.all(
                          color: LumiTokens.rule,
                          width: 1,
                        ),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedReason,
                        decoration: const InputDecoration(
                          hintText: 'Select a reason',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        style: LumiType.body.copyWith(color: LumiTokens.ink),
                        dropdownColor: LumiTokens.paper,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
                        items: reasons
                            .map((r) =>
                                DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                setSheetState(() => selectedReason = value);
                              },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Notes field
                    Text('Additional Details',
                        style:
                            LumiType.caption.copyWith(color: LumiTokens.ink)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: LumiTokens.cream,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
                        border: Border.all(
                          color: LumiTokens.rule,
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: notesController,
                        enabled: !isSubmitting,
                        maxLines: 3,
                        style: LumiType.body,
                        decoration: const InputDecoration(
                          hintText: 'Optional',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                              ),
                              side: const BorderSide(color: LumiTokens.rule),
                            ),
                            child: Text(
                              'Cancel',
                              style: LumiType.body.copyWith(
                                color: LumiTokens.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: (selectedReason == null || isSubmitting)
                                ? null
                                : () async {
                                    setSheetState(() => isSubmitting = true);

                                    final notes = notesController.text.trim();
                                    final reason = notes.isNotEmpty
                                        ? '$selectedReason: $notes'
                                        : selectedReason!;

                                    try {
                                      await CommunityBookService()
                                          .requestDeletion(
                                        isbn: widget.book.isbn!,
                                        reason: reason,
                                        requestedBy: widget.teacher.id,
                                        requestedByName:
                                            widget.teacher.fullName,
                                        schoolId: widget.teacher.schoolId!,
                                        bookTitle: widget.book.title,
                                        bookAuthor: widget.book.author,
                                      );

                                      if (!context.mounted) return;
                                      Navigator.pop(sheetContext); // close form
                                      Navigator.pop(context); // close detail

                                      showLumiToast(
                                        message:
                                            'Deletion request submitted. The Lumi team will review it.',
                                        type: LumiToastType.success,
                                      );
                                    } catch (e) {
                                      setSheetState(() => isSubmitting = false);
                                      showLumiToast(
                                        message: 'Failed to submit request: $e',
                                        type: LumiToastType.error,
                                      );
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Submit Request',
                                    style: LumiType.body.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schema-aware level badge row (used in BookDetailSheet header)
// ─────────────────────────────────────────────────────────────────────────────

class _BookLevelBadgeRow extends StatelessWidget {
  const _BookLevelBadgeRow({
    required this.book,
    required this.isDecodable,
    required this.stageColor,
    required this.currentAssignedCount,
    required this.schoolLevelSchemaKey,
    this.onTapAssigned,
  });

  final BookModel book;
  final bool isDecodable;
  final Color stageColor;
  final int currentAssignedCount;
  final String? schoolLevelSchemaKey;
  final VoidCallback? onTapAssigned;

  @override
  Widget build(BuildContext context) {
    final resolved = SchoolLibraryService.resolveDisplayLevel(
      book,
      schoolLevelSchemaKey,
    );

    final isMismatch = resolved.mode == LevelDisplayMode.communityMismatch;

    // For decodable books: show the resolved level (or 'Decodable' fallback).
    // For library books: show 'Library' type + a level badge if one exists.
    Widget typeBadge;
    if (isDecodable) {
      typeBadge = _TypeBadge(
        label: resolved.level ?? 'Decodable',
        color: isMismatch ? const Color(0xFFF59E0B) : stageColor,
      );
    } else {
      typeBadge = _TypeBadge(label: 'Library', color: stageColor);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        typeBadge,
        // For library books with a level, show it alongside the type badge.
        if (!isDecodable && resolved.level != null)
          _TypeBadge(
            label: resolved.level!,
            color: isMismatch ? const Color(0xFFF59E0B) : stageColor,
          ),
        if (currentAssignedCount > 0)
          GestureDetector(
            onTap: onTapAssigned,
            child: _AssignedBadge(
              count: currentAssignedCount,
              showChevron: onTapAssigned != null,
            ),
          ),
        // Amber "foreign schema" indicator
        if (isMismatch && schoolLevelSchemaKey != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 11, color: Color(0xFFB45309)),
                const SizedBox(width: 4),
                Text(
                  'From another school\'s schema',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Set School Level bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SetSchoolLevelSheet extends StatefulWidget {
  const _SetSchoolLevelSheet({
    required this.levels,
    required this.onSelect,
    this.currentLevel,
  });

  final List<String> levels;
  final String? currentLevel;
  final ValueChanged<String> onSelect;

  @override
  State<_SetSchoolLevelSheet> createState() => _SetSchoolLevelSheetState();
}

class _SetSchoolLevelSheetState extends State<_SetSchoolLevelSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentLevel ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: LumiTokens.rule,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Set level for your school', style: LumiType.subhead),
            const SizedBox(height: 4),
            Text(
              'This only affects your school\'s library — the community record is unchanged.',
              style: LumiType.caption.copyWith(color: LumiTokens.muted),
            ),
            const SizedBox(height: 16),
            if (widget.levels.isEmpty) ...[
              // No predefined levels — free-text input
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'e.g. Level 12, PM 20, Year 2',
                  prefixIcon: Icon(Icons.auto_stories_outlined,
                      color: LumiTokens.yellow, size: 20),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                    borderSide: BorderSide(color: LumiTokens.rule),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                    borderSide: BorderSide(color: LumiTokens.rule),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                    borderSide:
                        const BorderSide(color: LumiTokens.yellow, width: 2),
                  ),
                  filled: true,
                  fillColor: LumiTokens.paper,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : () => widget.onSelect(_controller.text.trim()),
                  style: FilledButton.styleFrom(
                    backgroundColor: LumiTokens.yellow,
                    disabledBackgroundColor:
                        LumiTokens.yellow.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                    ),
                  ),
                  child: Text(
                    'Save',
                    style: LumiType.body.copyWith(
                      color: LumiTokens.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ] else
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.levels.map((level) {
                      final isSelected = level == widget.currentLevel;
                      return GestureDetector(
                        onTap: () => widget.onSelect(level),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? LumiTokens.yellow
                                : LumiTokens.cream,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isSelected
                                  ? LumiTokens.yellow
                                  : LumiTokens.rule,
                            ),
                          ),
                          child: Text(
                            level,
                            style: LumiType.caption.copyWith(
                              color: LumiTokens.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: LumiType.caption.copyWith(
                color: LumiTokens.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: LumiType.caption.copyWith(
                color: LumiTokens.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One class's worth of students assigned a book — used by the "Assigned to"
/// sheet to group assignees by room.
class _AssigneeClass {
  const _AssigneeClass({required this.className, required this.students});

  final String className;
  final List<StudentModel> students;
}
