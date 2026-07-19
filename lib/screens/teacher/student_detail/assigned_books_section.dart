import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/lumi/teacher_book_assignment_card.dart';
import '../../../data/models/allocation_model.dart';
import '../../../data/providers/student_detail_providers.dart';
import '../../../services/book_cover_cache_service.dart';
import '../../../services/book_lookup_service.dart';
import '../../../services/book_metadata_resolver.dart';
import '../../../services/isbn_assignment_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'reading_log_snapshot.dart';
import 'section_info_card.dart';

/// True when [cachedCoverUrl] should still be hydrated from the ISBN APIs —
/// i.e. it is missing or known to be a fallback/placeholder URL.
/// (Moved unchanged from student_detail_screen.dart; kept public for tests.)
@visibleForTesting
bool shouldHydrateStudentDetailIsbnCover(String? cachedCoverUrl) {
  final trimmed = cachedCoverUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) return true;
  return BookCoverCacheService.isFallbackCoverUrl(trimmed);
}

/// View model for one card in the "Assigned Books" section. Public because the
/// parent screen's action sheets receive it. [canMutateAssignment] is the
/// verbatim former `_canMutateAssignment` gate: only books backed by a real
/// allocation assignment item may be edited/swapped/removed from this surface.
class AssignedBookViewData {
  final String title;
  final String subtitle;
  final String bookType;
  final String status;
  final List<Color> coverGradient;
  final String? coverImageUrl;
  final bool shouldResolveCover;
  final String? allocationId;
  final String? assignmentItemId;

  const AssignedBookViewData({
    required this.title,
    required this.subtitle,
    required this.bookType,
    required this.status,
    required this.coverGradient,
    this.coverImageUrl,
    this.shouldResolveCover = false,
    this.allocationId,
    this.assignmentItemId,
  });

  bool get canMutateAssignment {
    return allocationId != null &&
        allocationId!.isNotEmpty &&
        assignmentItemId != null &&
        assignmentItemId!.isNotEmpty;
  }
}

class _CachedBookCover {
  const _CachedBookCover({
    required this.bookId,
    required this.title,
    this.isbn,
    this.coverImageUrl,
  });

  final String bookId;
  final String title;
  final String? isbn;
  final String? coverImageUrl;
}

/// "Assigned Books" section of the teacher student-detail screen.
///
/// Owns the section's Firestore streams (via the shared autoDispose
/// providers), the [BookCoverCacheService]/[BookMetadataResolver] listeners
/// and the screen-local ISBN cover caches — so cover/metadata ticks rebuild
/// only this section instead of the whole screen, and never re-create a
/// Firestore subscription. Actions (sheets, scanners, log/renew flows) stay
/// with the parent via callbacks.
class AssignedBooksSection extends ConsumerStatefulWidget {
  final StudentDetailLookup lookup;
  final FirebaseFirestore firestore;
  final String teacherId;
  final VoidCallback onLogReading;
  final VoidCallback onRenew;
  final VoidCallback onScanIsbn;
  final VoidCallback onAssignBooks;
  final void Function(AssignedBookViewData book, TeacherBookCardAction action)
      onBookAction;
  final void Function(AssignedBookViewData book) onBookTap;

  const AssignedBooksSection({
    super.key,
    required this.lookup,
    required this.firestore,
    required this.teacherId,
    required this.onLogReading,
    required this.onRenew,
    required this.onScanIsbn,
    required this.onAssignBooks,
    required this.onBookAction,
    required this.onBookTap,
  });

  @override
  ConsumerState<AssignedBooksSection> createState() =>
      _AssignedBooksSectionState();
}

class _AssignedBooksSectionState extends ConsumerState<AssignedBooksSection> {
  late final BookLookupService _bookLookupService;
  BookMetadataResolver? _metadataResolverInstance;
  // Screen-local ISBN API results (separate from Firestore-doc-based data
  // which is owned by BookCoverCacheService).
  final Map<String, _CachedBookCover> _bookCoverByIsbn = {};
  final Set<String> _isbnCoverLoadsInFlight = <String>{};
  final Set<String> _isbnCoverLoadsCompleted = <String>{};

  @override
  void initState() {
    super.initState();
    _bookLookupService = BookLookupService(firestore: widget.firestore);
    BookCoverCacheService.instance.addListener(_onCoversUpdated);
    _ensureMetadataResolver();
  }

  @override
  void didUpdateWidget(covariant AssignedBooksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirrors the original screen's metadata-scope reset: a new school or
    // acting teacher invalidates the resolver and the ISBN cover caches.
    final metadataScopeChanged =
        oldWidget.lookup.schoolId != widget.lookup.schoolId ||
            oldWidget.teacherId != widget.teacherId;
    if (!metadataScopeChanged) return;

    _disposeMetadataResolver();
    _bookCoverByIsbn.clear();
    _isbnCoverLoadsInFlight.clear();
    _isbnCoverLoadsCompleted.clear();
    _ensureMetadataResolver();
  }

  @override
  void dispose() {
    BookCoverCacheService.instance.removeListener(_onCoversUpdated);
    _disposeMetadataResolver();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allocationsAsync =
        ref.watch(studentAllocationsProvider(widget.lookup));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Assigned Books', style: LumiType.subhead),
        const SizedBox(height: 12),
        allocationsAsync.when(
          error: (_, __) => const SectionInfoCard(
            'Could not load assigned books',
            isError: true,
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          data: (allocationSnapshot) {
            final allocations = allocationSnapshot.docs
                .map((doc) => AllocationModel.fromFirestore(doc))
                .toList();
            BookCoverCacheService.instance.primeFromAllocations(
              allocations,
              widget.firestore,
            );
            _primeIsbnCovers(allocations);

            final logsAsync = ref.watch(allocationLogsProvider(widget.lookup));
            return logsAsync.when(
              error: (_, __) => const SectionInfoCard(
                'Could not load reading progress',
                isError: true,
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              data: (logSnapshot) {
                final logs = toReadingLogSnapshots(logSnapshot);
                final books = _mapAssignedBooks(allocations, logs);
                _resolveMissingBookMetadata(books);

                if (books.isEmpty) {
                  return _buildNoBookCard();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAssignedActionsRow(),
                    const SizedBox(height: 12),
                    ...books.map((book) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TeacherBookAssignmentCard(
                          title: book.title,
                          subtitle: book.subtitle,
                          coverGradient: book.coverGradient,
                          coverImageUrl: book.coverImageUrl,
                          bookType: book.bookType,
                          status: book.status,
                          onActionSelected: book.canMutateAssignment
                              ? (action) => widget.onBookAction(book, action)
                              : null,
                          onTap: book.canMutateAssignment
                              ? () => widget.onBookTap(book)
                              : null,
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  BookMetadataResolver get _metadataResolver {
    final existing = _metadataResolverInstance;
    if (existing != null) return existing;

    final resolver = BookMetadataResolver(
      lookupService: _bookLookupService,
      schoolId: widget.lookup.schoolId,
      actorId: widget.teacherId,
    );
    resolver.addListener(_onMetadataUpdated);
    _metadataResolverInstance = resolver;
    return resolver;
  }

  void _onCoversUpdated() {
    if (mounted) setState(() {});
  }

  void _onMetadataUpdated() {
    if (mounted) setState(() {});
  }
  void _disposeMetadataResolver() {
    final resolver = _metadataResolverInstance;
    if (resolver == null) return;
    resolver.removeListener(_onMetadataUpdated);
    resolver.dispose();
    _metadataResolverInstance = null;
  }

  void _ensureMetadataResolver() {
    _metadataResolver;
  }
  Widget _buildActionHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
    bool outlinedAccent = false,
  }) {
    // The single primary action ("Assign") carries the green accent; the rest
    // are calm neutral ghost buttons so the toolbar doesn't shout.
    final isAccent = primary || outlinedAccent;
    final fg = isAccent ? LumiTokens.green : LumiTokens.ink;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: primary && !outlinedAccent
              ? LumiTokens.tintGreen
              : LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          border: outlinedAccent
              ? Border.all(color: LumiTokens.green, width: 1.3)
              : primary
                  ? null
                  : Border.all(color: LumiTokens.rule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LumiType.caption.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedActionsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildActionHeaderButton(
            icon: Icons.edit_note_rounded,
            label: 'Log',
            onPressed: widget.onLogReading,
            outlinedAccent: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionHeaderButton(
            icon: Icons.refresh_rounded,
            label: 'Renew',
            onPressed: widget.onRenew,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionHeaderButton(
            icon: Icons.qr_code_scanner,
            label: 'Scan',
            onPressed: widget.onScanIsbn,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionHeaderButton(
            icon: Icons.add,
            label: 'Assign',
            onPressed: widget.onAssignBooks,
          ),
        ),
      ],
    );
  }

  // Deliberate empty state when no book is assigned: one clear next step.
  Widget _buildNoBookCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: LumiTokens.muted.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.menu_book_outlined,
                    size: 18, color: LumiTokens.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No book currently assigned',
                  style: LumiType.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Assign a classroom, library or take-home book to start tracking progress.',
            style: LumiType.caption,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildActionHeaderButton(
                  icon: Icons.add,
                  label: 'Assign a book',
                  onPressed: widget.onAssignBooks,
                  primary: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionHeaderButton(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan',
                  onPressed: widget.onScanIsbn,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onLogReading,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Log a read without a book',
                style: LumiType.caption.copyWith(
                  color: LumiTokens.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  List<AssignedBookViewData> _mapAssignedBooks(
    List<AllocationModel> allocations,
    List<ReadingLogSnapshot> logs,
  ) {
    final now = DateTime.now();
    final seen = <String>{};
    final results = <AssignedBookViewData>[];

    for (final allocation in allocations) {
      final withinWindow = !allocation.startDate.isAfter(now) &&
          !allocation.endDate.isBefore(now);
      final appliesToStudent = allocation.isForWholeClass ||
          allocation.studentIds.contains(widget.lookup.studentId);
      if (!withinWindow || !appliesToStudent) continue;

      if (allocation.type == AllocationType.byTitle) {
        final type = _inferBookType(allocation);
        final effectiveItems =
            allocation.effectiveAssignmentItemsForStudent(widget.lookup.studentId);
        if (effectiveItems.isNotEmpty) {
          for (final item in effectiveItems) {
            final itemIsbn = _isbnKey(item.resolvedIsbn ?? '');
            if (itemIsbn.isNotEmpty) {
              final dedupeKey = 'isbn:$itemIsbn';
              if (seen.contains(dedupeKey)) continue;
              seen.add(dedupeKey);

              final cachedBook = _bookCoverByIsbn[itemIsbn];
              final cachedTitle =
                  BookCoverCacheService.instance.resolveTitleByIsbn(itemIsbn);
              final cachedCover = BookCoverCacheService.instance
                  .resolveCoverUrlByIsbn(itemIsbn);
              final rawTitle = cachedBook?.title.isNotEmpty == true
                  ? cachedBook!.title
                  : (item.title.trim().isNotEmpty
                      ? item.title.trim()
                      : (cachedTitle ?? 'Unknown Book (ISBN $itemIsbn)'));
              final status = _statusWithRenewal(
                  _deriveStatusForTitle(allocation, logs, rawTitle), item);
              final displayTitle =
                  IsbnAssignmentService.sanitizeDisplayTitle(rawTitle);

              results.add(
                AssignedBookViewData(
                  title: displayTitle,
                  subtitle:
                      '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
                  bookType: type,
                  status: status,
                  coverGradient: _coverGradient(type, itemIsbn),
                  coverImageUrl: cachedBook?.coverImageUrl ?? cachedCover,
                  shouldResolveCover: false,
                  allocationId: allocation.id,
                  assignmentItemId: item.id,
                ),
              );
              continue;
            }

            final title = item.title.trim();
            if (title.isEmpty) continue;
            final dedupeKey = 'item:${item.id}';
            if (seen.contains(dedupeKey)) continue;
            seen.add(dedupeKey);
            final status = _statusWithRenewal(
                _deriveStatusForTitle(allocation, logs, title), item);
            final displayTitle =
                IsbnAssignmentService.sanitizeDisplayTitle(title);
            results.add(
              AssignedBookViewData(
                title: displayTitle,
                subtitle:
                    '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
                bookType: type,
                status: status,
                coverGradient: _coverGradient(type, item.id),
                coverImageUrl: _resolveCoverUrlForTitle(title),
                shouldResolveCover: true,
                allocationId: allocation.id,
                assignmentItemId: item.id,
              ),
            );
          }
          continue;
        }

        // effectiveItems is empty for this student (all items removed via
        // student-level override). Don't fall through to the generic
        // allocation path below — this allocation simply has no books for
        // this student.
        continue;
      }

      final dedupeKey = 'allocation:${allocation.id}';
      if (seen.contains(dedupeKey)) continue;
      seen.add(dedupeKey);
      final status = _deriveStatusForAllocation(allocation, logs);
      final type = _inferBookType(allocation);
      results.add(
        AssignedBookViewData(
          title: _allocationTitle(allocation),
          subtitle:
              '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
          bookType: type,
          status: status,
          coverGradient: _coverGradient(type, allocation.id),
          shouldResolveCover: false,
        ),
      );
    }

    return results;
  }

  List<String> _scannedIsbnsForAllocation(AllocationModel allocation) {
    final itemIsbns = allocation
        .effectiveAssignmentItemsForStudent(widget.lookup.studentId)
        .map((item) => _isbnKey(item.resolvedIsbn ?? ''))
        .where((isbn) => isbn.isNotEmpty)
        .toSet()
        .toList();
    if (itemIsbns.isNotEmpty) {
      return itemIsbns;
    }

    final rawMetadataIsbns = allocation.metadata?['scannedIsbns'];
    final metadataIsbns = rawMetadataIsbns is! List
        ? const <String>[]
        : rawMetadataIsbns
            .whereType<String>()
            .map(_isbnKey)
            .where((isbn) => isbn.isNotEmpty)
            .toSet()
            .toList();

    if (metadataIsbns.isNotEmpty) {
      return metadataIsbns;
    }

    final parsed = <String>{};

    final bookIds = allocation.bookIds;
    if (bookIds != null && bookIds.isNotEmpty) {
      for (final rawId in bookIds) {
        final id = rawId.trim();
        if (!id.startsWith('isbn_')) continue;
        final isbn = _isbnKey(id.substring(5));
        if (isbn.isNotEmpty) parsed.add(isbn);
      }
    }

    if (parsed.isNotEmpty) {
      return parsed.toList();
    }

    // Legacy fallback: older allocations can store ISBNs in the visible title.
    final bookTitles = allocation.bookTitles;
    if (bookTitles == null || bookTitles.isEmpty) {
      return const [];
    }

    final isbnPattern = RegExp(r'ISBN\s*([0-9Xx\- ]{10,20})');
    for (final rawTitle in bookTitles) {
      final match = isbnPattern.firstMatch(rawTitle);
      if (match == null) continue;
      final isbn = _isbnKey(match.group(1) ?? '');
      if (isbn.isNotEmpty) parsed.add(isbn);
    }
    return parsed.toList();
  }

  String _isbnKey(String rawIsbn) {
    final trimmed = rawIsbn.trim();
    if (trimmed.isEmpty) return '';
    return IsbnAssignmentService.normalizeIsbn(trimmed) ?? trimmed;
  }

  void _primeIsbnCovers(List<AllocationModel> allocations) {
    final missingIsbns = <String>{};

    for (final allocation in allocations) {
      for (final isbn in _scannedIsbnsForAllocation(allocation)) {
        final singletonCover =
            BookCoverCacheService.instance.resolveCoverUrlByIsbn(isbn);
        if (!shouldHydrateStudentDetailIsbnCover(singletonCover)) {
          _isbnCoverLoadsCompleted.add(isbn);
          continue;
        }
        final localCover = _bookCoverByIsbn[isbn]?.coverImageUrl;
        final hasResolvedLocalCover =
            !shouldHydrateStudentDetailIsbnCover(localCover);
        if (hasResolvedLocalCover ||
            _isbnCoverLoadsInFlight.contains(isbn) ||
            _isbnCoverLoadsCompleted.contains(isbn)) {
          continue;
        }
        missingIsbns.add(isbn);
      }
    }

    if (missingIsbns.isEmpty) return;

    for (final isbn in missingIsbns) {
      _isbnCoverLoadsInFlight.add(isbn);
      unawaited(_loadCoverFromIsbn(isbn));
    }
  }

  Future<void> _loadCoverFromIsbn(String isbn) async {
    try {
      final resolved = await _bookLookupService.lookupByIsbn(
        isbn: isbn,
        schoolId: widget.lookup.schoolId,
        actorId: widget.teacherId,
        useFirestoreCache: true,
        persistToFirestoreCache: false,
      );
      if (resolved == null) return;

      final resolvedIsbn = _isbnKey(resolved.isbn ?? isbn);
      final title = resolved.title.trim();
      final rawCoverImageUrl = resolved.coverImageUrl?.trim();
      final hasHttpCover = rawCoverImageUrl != null &&
          rawCoverImageUrl.isNotEmpty &&
          rawCoverImageUrl.startsWith('http');
      final coverImageUrl = hasHttpCover
          ? rawCoverImageUrl.replaceFirst('http://', 'https://')
          : (resolvedIsbn.isNotEmpty
              ? 'https://covers.openlibrary.org/b/isbn/$resolvedIsbn-M.jpg?default=false'
              : null);

      final cached = _CachedBookCover(
        bookId: resolved.id,
        title: title,
        isbn: resolvedIsbn,
        coverImageUrl: coverImageUrl,
      );
      _bookCoverByIsbn[resolvedIsbn] = cached;

      // Also populate the session-level singleton so other screens benefit.
      BookCoverCacheService.instance.cacheFromIsbnLookup(
        isbn: resolvedIsbn,
        title: title,
        coverImageUrl: coverImageUrl,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Best-effort ISBN hydration; keep placeholder when lookup fails.
    } finally {
      _isbnCoverLoadsInFlight.remove(isbn);
      _isbnCoverLoadsCompleted.add(isbn);
    }
  }

  void _resolveMissingBookMetadata(List<AssignedBookViewData> books) {
    // Title-based API lookups disabled — they fuzzy-match covers from
    // unrelated books.  Books without ISBN-resolved covers show a placeholder.
  }

  String? _resolveCoverUrlForTitle(String title) {
    // 1. Session-level singleton — Firestore doc loads shared across screens,
    //    plus any ISBN API results fed in via cacheFromIsbnLookup.
    final singletonUrl = BookCoverCacheService.instance.resolveCoverUrl(title);
    if (singletonUrl != null) return singletonUrl;

    // 2. Screen-local ISBN API results (keyed directly by isbn in _bookCoverByIsbn).
    final titleKey = BookLookupService.normalizeTitle(title);
    final localIsbnEntry = _bookCoverByIsbn.values
        .where((c) => BookLookupService.normalizeTitle(c.title) == titleKey)
        .firstOrNull;
    final localIsbnUrl = localIsbnEntry?.coverImageUrl;
    if (localIsbnUrl != null && localIsbnUrl.startsWith('http')) {
      return localIsbnUrl;
    }

    return null;
  }

  /// Promotes a book to the 'renewed' badge when it was carried over from the
  /// prior week, but only if it hasn't already started/finished this week (a
  /// 'completed'/'in_progress' status is more informative and takes priority).
  String _statusWithRenewal(String baseStatus, AllocationBookItem item) {
    if (baseStatus == 'new' && item.metadata?['renewed'] == true) {
      return 'renewed';
    }
    return baseStatus;
  }

  String _deriveStatusForTitle(
    AllocationModel allocation,
    List<ReadingLogSnapshot> logs,
    String title,
  ) {
    final titleKey = title.trim().toLowerCase();
    final matching = logs.where((log) {
      final inWindow = !log.date.isBefore(allocation.startDate) &&
          !log.date.isAfter(allocation.endDate.add(const Duration(days: 1)));
      if (!inWindow) return false;
      if (log.allocationId == allocation.id) return true;
      return log.bookTitles
          .any((book) => book.trim().toLowerCase() == titleKey);
    }).toList();

    if (matching.isEmpty) return 'new';
    final hasCompletion = matching.any((log) =>
        log.status == 'completed' || log.minutesRead >= log.targetMinutes);
    return hasCompletion ? 'completed' : 'in_progress';
  }

  String _deriveStatusForAllocation(
    AllocationModel allocation,
    List<ReadingLogSnapshot> logs,
  ) {
    final matching = logs.where((log) {
      if (log.allocationId != allocation.id) return false;
      return !log.date.isBefore(allocation.startDate) &&
          !log.date.isAfter(allocation.endDate.add(const Duration(days: 1)));
    }).toList();
    if (matching.isEmpty) return 'new';
    final hasCompletion = matching.any((log) =>
        log.status == 'completed' || log.minutesRead >= log.targetMinutes);
    return hasCompletion ? 'completed' : 'in_progress';
  }

  String _allocationTitle(AllocationModel allocation) {
    if (allocation.type == AllocationType.byLevel) {
      if (allocation.levelStart != null && allocation.levelEnd != null) {
        return 'Level ${allocation.levelStart}-${allocation.levelEnd} Reading';
      }
      if (allocation.levelStart != null) {
        return 'Level ${allocation.levelStart} Reading';
      }
    }
    if (allocation.type == AllocationType.freeChoice) {
      return 'Free Choice Reading';
    }
    return 'Reading Allocation';
  }

  String _cadenceLabel(AllocationCadence cadence) {
    switch (cadence) {
      case AllocationCadence.daily:
        return 'Daily';
      case AllocationCadence.weekly:
        return 'Weekly';
      case AllocationCadence.fortnightly:
        return 'Fortnightly';
      case AllocationCadence.custom:
        return 'Custom';
    }
  }

  String _inferBookType(AllocationModel allocation) {
    if (allocation.type == AllocationType.byLevel ||
        allocation.levelStart != null) {
      return 'decodable';
    }
    return 'library';
  }

  List<Color> _coverGradient(String type, String seed) {
    if (type == 'decodable') {
      const palettes = <List<Color>>[
        [AppColors.levelCVC, AppColors.error],
        [AppColors.levelDigraphs, AppColors.warmOrange],
        [AppColors.levelBlends, AppColors.secondaryYellow],
        [AppColors.levelCVCE, AppColors.secondaryGreen],
        [AppColors.levelVowelTeams, AppColors.decodableBlue],
        [AppColors.levelRControlled, AppColors.secondaryPurple],
      ];
      final index = seed.hashCode.abs() % palettes.length;
      return palettes[index];
    }
    return const [AppColors.libraryGreen, Color(0xFF388E3C)];
  }

  /// Builds a full [ReadingLogModel] from a row snapshot, carrying the ids and
}
