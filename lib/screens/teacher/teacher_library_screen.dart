import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi/persistent_cached_image.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../data/models/book_model.dart';
import '../../services/school_library_assignment_service.dart';
import '../../services/school_library_service.dart';

/// Teacher Library Screen — school-wide book library.
///
/// All books are sourced from `schools/{schoolId}/books`, populated
/// automatically whenever any teacher scans a new ISBN.
class TeacherLibraryScreen extends StatefulWidget {
  const TeacherLibraryScreen({super.key, required this.schoolId});

  final String schoolId;

  @override
  State<TeacherLibraryScreen> createState() => _TeacherLibraryScreenState();
}

class _TeacherLibraryScreenState extends State<TeacherLibraryScreen> {
  final _libraryService = SchoolLibraryService();
  final _assignmentService = SchoolLibraryAssignmentService();
  final _searchController = TextEditingController();

  String _activeFilter = 'All';
  String _searchQuery = '';

  static const _filters = ['All', 'Decodable', 'Library', 'Recently Added'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.schoolId.isEmpty) {
      return const _ErrorState(message: 'School ID not available.');
    }

    return SafeArea(
      child: StreamBuilder<List<BookModel>>(
        stream: _libraryService.booksStream(widget.schoolId),
        builder: (context, librarySnapshot) {
          if (librarySnapshot.hasError) {
            return const _ErrorState(
                message: 'Could not load library. Please try again.');
          }

          final isLoading = !librarySnapshot.hasData;
          final allBooks = librarySnapshot.data ?? [];
          final filtered = SchoolLibraryService.applyFilter(
            books: allBooks,
            filter: _activeFilter,
            searchQuery: _searchQuery,
          );
          final decodableCount =
              allBooks.where(SchoolLibraryService.isDecodable).length;

          return StreamBuilder<LibraryAssignmentSnapshot>(
            stream: _assignmentService.summaryStream(widget.schoolId),
            builder: (context, assignmentSnapshot) {
              final assignmentSummary =
                  assignmentSnapshot.data ?? const LibraryAssignmentSnapshot();

              return CustomScrollView(
                slivers: [
                  // ── Header ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Book Library', style: TeacherTypography.h1),
                          const SizedBox(height: 4),
                          isLoading
                              ? const LumiSkeleton(width: 180, height: 16)
                              : Text(
                                  '${allBooks.length} book${allBooks.length == 1 ? '' : 's'} in your school library'
                                  '${decodableCount > 0 ? ' · $decodableCount decodable' : ''}',
                                  style: TeacherTypography.bodyMedium.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),

                  // ── Search ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search books...',
                          hintStyle: TeacherTypography.bodyMedium
                              .copyWith(color: AppColors.textSecondary),
                          prefixIcon: const Icon(Icons.search,
                              color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                TeacherDimensions.radiusM),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        style: TeacherTypography.bodyMedium,
                      ),
                    ),
                  ),

                  // ── Filter chips ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 0, 16),
                      child: SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _filters.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          padding: const EdgeInsets.only(right: 20),
                          itemBuilder: (context, i) {
                            final f = _filters[i];
                            return TeacherFilterChip(
                              label: f,
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

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          );
        },
      ),
    );
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _LibraryBookCard(
            book: books[i],
            currentAssignedCount:
                assignmentSummary.currentAssignedCountForBook(books[i]),
            onTap: () => _showBookDetail(
              books[i],
              currentAssignedCount:
                  assignmentSummary.currentAssignedCountForBook(books[i]),
            ),
          ),
          childCount: books.length,
        ),
      ),
    );
  }

  // ── Loading skeleton ─────────────────────────────────────────────────────

  Widget _buildSkeletonSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, __) => const LumiSkeleton(borderRadius: 12),
          childCount: 9,
        ),
      ),
    );
  }

  // ── Empty / no-results states ─────────────────────────────────────────────

  Widget _buildEmptySliver() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book_outlined,
                  size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              Text('No books yet',
                  style: TeacherTypography.h2, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Scan a book ISBN from the student detail screen to start building your school library.',
                style: TeacherTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoResultsSliver() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Text(
          'No books match your search.',
          style: TeacherTypography.bodyMedium
              .copyWith(color: AppColors.textSecondary),
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
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          stage,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.charcoal,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '($count book${count == 1 ? '' : 's'})',
          style: TeacherTypography.bodySmall,
        ),
      ],
    );
  }
}

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: AppColors.libraryGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'Library Books',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.charcoal,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '($count book${count == 1 ? '' : 's'})',
          style: TeacherTypography.bodySmall,
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: TeacherDimensions.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: _BookCoverWidget(
                  book: book,
                  stageColor: stageColor,
                  currentAssignedCount: currentAssignedCount,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: TeacherTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
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

  Widget _placeholder(Color color) => Center(
        child: Icon(Icons.menu_book,
            color: color.withValues(alpha: 0.6), size: 32),
      );
}

class _AssignedBadge extends StatelessWidget {
  const _AssignedBadge({required this.count, this.compact = false});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.teacherPrimaryLight.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
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
              fontSize: compact ? 10 : 9,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              style: TeacherTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Book Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class BookDetailSheet extends StatelessWidget {
  const BookDetailSheet({
    super.key,
    required this.book,
    required this.currentAssignedCount,
  });

  final BookModel book;
  final int currentAssignedCount;

  @override
  Widget build(BuildContext context) {
    final isDecodable = SchoolLibraryService.isDecodable(book);
    final stageColor = isDecodable
        ? Color(SchoolLibraryService.stageColor(book.readingLevel ?? ''))
        : AppColors.libraryGreen;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Cover + basic info
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 72,
                        height: 100,
                        child: _BookCoverWidget(
                          book: book,
                          stageColor: stageColor,
                          currentAssignedCount: currentAssignedCount,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(book.title, style: TeacherTypography.h2),
                          if (book.author?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              book.author!,
                              style: TeacherTypography.bodyMedium
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _TypeBadge(
                            label: isDecodable
                                ? (book.readingLevel ?? 'Decodable')
                                : 'Library',
                            color: stageColor,
                          ),
                          if (currentAssignedCount > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.people_outline,
                                    size: 14, color: AppColors.teacherPrimary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Currently assigned to $currentAssignedCount student${currentAssignedCount == 1 ? '' : 's'}',
                                    style: TeacherTypography.caption.copyWith(
                                      color: AppColors.teacherPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 6),
                  child: Text(
                    'About',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoal,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    book.description!,
                    style: TeacherTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary, height: 1.5),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: TeacherTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ),
        Expanded(child: Text(value, style: TeacherTypography.bodySmall)),
      ],
    );
  }
}
