import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import 'cover_crop_screen.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi/persistent_cached_image.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../data/models/book_model.dart';
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

  static const _filters = [
    'All',
    'Decodable',
    'Library',
    'Recently Added',
    'Hidden',
  ];

  String get _hiddenPrefsKey => 'hidden_books_${widget.teacher.schoolId ?? ''}';

  @override
  void initState() {
    super.initState();
    _libraryService = widget._libraryService ?? SchoolLibraryService();
    _assignmentService =
        widget._assignmentService ?? SchoolLibraryAssignmentService();
    _loadHiddenBooks();
  }

  Future<void> _loadHiddenBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_hiddenPrefsKey) ?? [];
    setState(() => _hiddenBookIds = ids.toSet());
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

  void _openAddBook() {
    context.push(
      '/teacher/community-scanner',
      extra: widget.teacher,
    );
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = widget.teacher.schoolId?.trim() ?? '';
    if (schoolId.isEmpty) {
      return const _ErrorState(message: 'School ID not available.');
    }

    return SafeArea(
      child: StreamBuilder<List<BookModel>>(
        stream: _libraryService.booksStream(schoolId),
        builder: (context, librarySnapshot) {
          if (librarySnapshot.hasError) {
            return const _ErrorState(
                message: 'Could not load library. Please try again.');
          }

          final isLoading = !librarySnapshot.hasData;
          final allBooks = librarySnapshot.data ?? [];
          final hiddenCount =
              allBooks.where((b) => _hiddenBookIds.contains(b.id)).length;

          // For the Hidden filter, show hidden books; otherwise exclude them
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
          final decodableCount = allBooks
              .where((b) =>
                  SchoolLibraryService.isDecodable(b) &&
                  !_hiddenBookIds.contains(b.id))
              .length;
          final visibleCount = allBooks.length - hiddenCount;
          final libraryCount = allBooks
              .where((b) =>
                  !SchoolLibraryService.isDecodable(b) &&
                  !_hiddenBookIds.contains(b.id))
              .length;

          return StreamBuilder<LibraryAssignmentSnapshot>(
            stream: _assignmentService.summaryStream(schoolId),
            builder: (context, assignmentSnapshot) {
              final assignmentSummary =
                  assignmentSnapshot.data ?? const LibraryAssignmentSnapshot();

              return CustomScrollView(
                slivers: [
                  // ── Header ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _LibraryHeader(
                        isLoading: isLoading,
                        visibleCount: visibleCount,
                        decodableCount: decodableCount,
                        hiddenCount: hiddenCount,
                        onAddBook: _openAddBook,
                      ),
                    ),
                  ),

                  // ── Search ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _LibrarySearchBar(
                        controller: _searchController,
                        query: _searchQuery,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        onClear: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                    ),
                  ),

                  // ── Filter chips ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 0, 18),
                      child: SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _filters.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          padding: const EdgeInsets.only(right: 16),
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
                              onTap: () => setState(() => _activeFilter = f),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // ── Body ──────────────────────────────────────────────────
                  if (isLoading)
                    _buildSkeletonSliver()
                  else if (allBooks.isEmpty)
                    _buildEmptySliver()
                  else if (filtered.isEmpty)
                    _buildNoResultsSliver()
                  else if (_activeFilter == 'All' ||
                      _activeFilter == 'Decodable')
                    ..._buildTierSections(
                      filtered,
                      assignmentSummary: assignmentSummary,
                    )
                  else
                    _buildFlatGrid(
                      filtered,
                      assignmentSummary: assignmentSummary,
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
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

  // ── Tier sections (LLLL stages + library books) ──────────────────────────

  List<Widget> _buildTierSections(
    List<BookModel> books, {
    required LibraryAssignmentSnapshot assignmentSummary,
  }) {
    final slivers = <Widget>[];
    final stageGroups = SchoolLibraryService.groupDecodableByStage(books);

    for (final entry in stageGroups.entries) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child:
              _StageSectionHeader(stage: entry.key, count: entry.value.length),
        ),
      ));
      slivers.add(_bookGrid(entry.value, assignmentSummary: assignmentSummary));
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }

    if (_activeFilter == 'All') {
      final libBooks = SchoolLibraryService.libraryBooks(books);
      if (libBooks.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: _LibrarySectionHeader(count: libBooks.length),
          ),
        ));
        slivers.add(_bookGrid(libBooks, assignmentSummary: assignmentSummary));
      }
    }

    return slivers;
  }

  Widget _buildFlatGrid(
    List<BookModel> books, {
    required LibraryAssignmentSnapshot assignmentSummary,
  }) =>
      _bookGrid(books, assignmentSummary: assignmentSummary);

  SliverPadding _bookGrid(
    List<BookModel> books, {
    required LibraryAssignmentSnapshot assignmentSummary,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final book = books[i];
            final assignedCount =
                assignmentSummary.currentAssignedCountForBook(book);
            final card = _LibraryBookCard(
              book: book,
              currentAssignedCount: assignedCount,
              onTap: () => _showBookDetail(
                book,
                currentAssignedCount: assignedCount,
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

  Widget _buildSkeletonSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, __) => const LumiSkeleton(borderRadius: 16),
          childCount: 9,
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
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookDetailSheet(
        book: book,
        currentAssignedCount: currentAssignedCount,
        teacher: widget.teacher,
        isHidden: _hiddenBookIds.contains(book.id),
        onToggleHide: () async {
          await _toggleHideBook(book.id);
          if (mounted) Navigator.pop(context); // close sheet
        },
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.isLoading,
    required this.visibleCount,
    required this.decodableCount,
    required this.hiddenCount,
    required this.onAddBook,
  });

  final bool isLoading;
  final int visibleCount;
  final int decodableCount;
  final int hiddenCount;
  final VoidCallback onAddBook;

  @override
  Widget build(BuildContext context) {
    final bookLabel = visibleCount == 1 ? 'book' : 'books';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Book Library', style: TeacherTypography.h1),
                    const SizedBox(height: 4),
                    isLoading
                        ? const LumiSkeleton(width: 188, height: 16)
                        : Text(
                            '$visibleCount $bookLabel in your school library',
                            style: TeacherTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: onAddBook,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teacherPrimary,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusL),
                    ),
                  ),
                  icon: const Icon(Icons.document_scanner_outlined, size: 18),
                  label: Text(
                    'Add Book',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!isLoading && (decodableCount > 0 || hiddenCount > 0)) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (decodableCount > 0)
                  _HeaderMetricPill(
                    icon: Icons.auto_stories_outlined,
                    label:
                        '$decodableCount decodable${decodableCount == 1 ? '' : 's'}',
                    color: AppColors.teacherPrimary,
                  ),
                if (hiddenCount > 0)
                  _HeaderMetricPill(
                    icon: Icons.visibility_off_outlined,
                    label: '$hiddenCount hidden',
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderMetricPill extends StatelessWidget {
  const _HeaderMetricPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TeacherTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
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
    final borderRadius = BorderRadius.circular(TeacherDimensions.radiusL);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.teacherBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
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
                  color: AppColors.teacherPrimaryLight.withValues(alpha: 0.82),
                ),
              ),
            ),
            TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.rosePink,
              style: TeacherTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Search by title, author, or ISBN...',
                hintStyle: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary.withValues(alpha: 0.65),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isActive
                      ? AppColors.teacherPrimary
                      : AppColors.textSecondary.withValues(alpha: 0.58),
                ),
                suffixIcon: hasQuery
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.textSecondary,
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
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.teacherSurfaceTint,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 34, color: AppColors.teacherPrimary),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TeacherTypography.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TeacherTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.teacherPrimary,
                foregroundColor: AppColors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusL),
                ),
              ),
              icon: Icon(
                actionText == 'Add Book'
                    ? Icons.document_scanner_outlined
                    : Icons.close_rounded,
                size: 18,
              ),
              label: Text(
                actionText!,
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                ),
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
      color: AppColors.libraryGreen,
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
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TeacherTypography.h3.copyWith(fontSize: 17),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.teacherBorder),
          ),
          child: Text(
            '$count book${count == 1 ? '' : 's'}',
            style: TeacherTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
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

class _LibraryBookCard extends StatelessWidget {
  const _LibraryBookCard({
    required this.book,
    required this.currentAssignedCount,
    required this.onTap,
  });

  final BookModel book;
  final int currentAssignedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDecodable = SchoolLibraryService.isDecodable(book);
    final stageColor = isDecodable
        ? Color(SchoolLibraryService.stageColor(book.readingLevel ?? ''))
        : AppColors.libraryGreen;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.teacherPrimary.withValues(alpha: 0.10),
            blurRadius: 20,
            spreadRadius: -10,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.04),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppColors.teacherBorder.withValues(alpha: 0.7),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _BookCoverWidget(
                  book: book,
                  stageColor: stageColor,
                  currentAssignedCount: currentAssignedCount,
                ),
              ),
              SizedBox(
                height: 54,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: TeacherTypography.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.charcoal,
                          height: 1.18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Container(
                        width: 24,
                        height: 3,
                        decoration: BoxDecoration(
                          color: stageColor.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: stageColor.withValues(alpha: 0.15),
            child: hasCover
                ? PersistentCachedImage(
                    imageUrl: book.coverImageUrl!,
                    fit: BoxFit.cover,
                    fallback: _placeholder(stageColor),
                  )
                : _placeholder(stageColor),
          ),
        ),
        if (currentAssignedCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: _AssignedBadge(count: currentAssignedCount, compact: true),
          ),
      ],
    );
  }

  Widget _placeholder(Color color) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.22),
              AppColors.white.withValues(alpha: 0.40),
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.menu_book_rounded,
              color: color.withValues(alpha: 0.74),
              size: 30,
            ),
          ),
        ),
      );
}

class _AssignedBadge extends StatelessWidget {
  const _AssignedBadge({required this.count, this.compact = false});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.teacherPrimary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.10),
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
            color: AppColors.teacherPrimary,
          ),
          const SizedBox(width: 3),
          Text(
            compact ? '$count' : '$count assigned',
            style: TeacherTypography.caption.copyWith(
              color: AppColors.teacherPrimary,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 10 : 11,
            ),
          ),
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
  });

  final BookModel book;
  final int currentAssignedCount;
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

  bool get _isCommunityBook =>
      widget.book.metadata?['source'] == 'community_books';

  bool get _hasCover {
    final url = _uploadedCoverUrl ?? widget.book.coverImageUrl;
    return url != null && url.startsWith('http');
  }

  @override
  void initState() {
    super.initState();
    _checkCoverOwnership();
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
          color: AppColors.white,
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
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Add Cover Photo', style: TeacherTypography.h3),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.teacherPrimary),
              title: Text('Take Photo', style: TeacherTypography.bodyMedium),
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.teacherPrimary),
              title: Text('Choose from Gallery',
                  style: TeacherTypography.bodyMedium),
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM)),
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
      );

      if (!mounted) return;

      if (url == null) {
        setState(() => _isUploadingCover = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload cover image')),
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cover photo added! It will appear for all teachers.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingCover = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding cover: $e')),
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
        : AppColors.libraryGreen;

    return DraggableScrollableSheet(
      initialChildSize: 0.64,
      minChildSize: 0.42,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.16),
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
                    color: AppColors.teacherBorder,
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
                    color: AppColors.teacherBackground,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusXL),
                    border: Border.all(color: AppColors.teacherBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.charcoal.withValues(alpha: 0.10),
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
                              style: TeacherTypography.h2,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (book.author?.isNotEmpty == true) ...[
                              const SizedBox(height: 5),
                              Text(
                                book.author!,
                                style: TeacherTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _TypeBadge(
                                  label: isDecodable
                                      ? (book.readingLevel ?? 'Decodable')
                                      : 'Library',
                                  color: stageColor,
                                ),
                                if (currentAssignedCount > 0)
                                  _AssignedBadge(
                                    count: currentAssignedCount,
                                  ),
                              ],
                            ),
                            if (currentAssignedCount > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Currently assigned to $currentAssignedCount student${currentAssignedCount == 1 ? '' : 's'}',
                                style: TeacherTypography.caption.copyWith(
                                  color: AppColors.teacherPrimary,
                                  fontWeight: FontWeight.w700,
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
                                color: AppColors.teacherPrimary,
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
                            color: AppColors.teacherPrimary,
                          ),
                          label: Text(
                            _hasCover
                                ? 'Change Cover Photo'
                                : 'Add Cover Photo',
                            style: TeacherTypography.bodySmall.copyWith(
                              color: AppColors.teacherPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.teacherPrimary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
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
                  child: _InfoRow(label: 'Publisher', value: book.publisher!),
                ),

              if (book.description?.isNotEmpty == true) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.teacherBackground,
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusL),
                      border: Border.all(color: AppColors.teacherBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About',
                          style: TeacherTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          book.description!,
                          style: TeacherTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusL),
                    border: Border.all(color: AppColors.teacherBorder),
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onToggleHide,
                          icon: Icon(
                            widget.isHidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          label: Text(
                            widget.isHidden
                                ? 'Unhide from Library'
                                : 'Hide from Library',
                            style: TeacherTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
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
                              style: TeacherTypography.bodySmall.copyWith(
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
        );
      },
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
                  color: AppColors.white,
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
                          color: AppColors.textSecondary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      'Request Book Deletion',
                      style: TeacherTypography.h3,
                    ),
                    const SizedBox(height: 8),

                    // Description
                    Text(
                      'This will send a request to Lumi to remove this book from the community library.',
                      style: TeacherTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),

                    // Reason dropdown
                    Text('Reason',
                        style: TeacherTypography.caption
                            .copyWith(color: AppColors.charcoal)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius:
                            BorderRadius.circular(TeacherDimensions.radiusM),
                        border: Border.all(
                          color: AppColors.teacherBorder,
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
                        style: TeacherTypography.bodyMedium
                            .copyWith(color: AppColors.charcoal),
                        dropdownColor: AppColors.white,
                        borderRadius:
                            BorderRadius.circular(TeacherDimensions.radiusM),
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
                        style: TeacherTypography.caption
                            .copyWith(color: AppColors.charcoal)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius:
                            BorderRadius.circular(TeacherDimensions.radiusM),
                        border: Border.all(
                          color: AppColors.teacherBorder,
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: notesController,
                        enabled: !isSubmitting,
                        maxLines: 3,
                        style: TeacherTypography.bodyMedium,
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
                                    TeacherDimensions.radiusM),
                              ),
                              side: const BorderSide(
                                  color: AppColors.teacherBorder),
                            ),
                            child: Text(
                              'Cancel',
                              style: TeacherTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
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

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Deletion request submitted. The Lumi team will review it.',
                                            style: TeacherTypography.bodySmall
                                                .copyWith(
                                                    color: AppColors.white),
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: AppColors.charcoal,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                TeacherDimensions.radiusM),
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      setSheetState(() => isSubmitting = false);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to submit request: $e',
                                            style: TeacherTypography.bodySmall
                                                .copyWith(
                                                    color: AppColors.white),
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: Colors.red,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                TeacherDimensions.radiusM),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusM),
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
                                    style:
                                        TeacherTypography.bodyMedium.copyWith(
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
        color: AppColors.teacherBackground,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        border: Border.all(color: AppColors.teacherBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TeacherTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TeacherTypography.bodySmall.copyWith(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
