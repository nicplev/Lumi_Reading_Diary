import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/book_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'book_cover.dart';
import 'book_history_item.dart';

const _accent = LumiTokens.yellow;

/// Opens the book-detail sheet for a [book], using any resolved [metadata]
/// (cover, author, blurb, genres) the caller already has cached.
void showBookDetailSheet(
  BuildContext context,
  BookHistoryItem book,
  BookModel? metadata,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _BookDetailSheet(book: book, metadata: metadata),
  );
}

class _BookDetailSheet extends StatelessWidget {
  final BookHistoryItem book;
  final BookModel? metadata;

  const _BookDetailSheet({required this.book, required this.metadata});

  @override
  Widget build(BuildContext context) {
    final coverUrl = metadata?.coverImageUrl;
    final displayTitle = metadata?.title ?? book.title;
    final author = metadata?.author;
    final publisher = metadata?.publisher;
    final description = metadata?.description;
    final pageCount = metadata?.pageCount;
    final genres = metadata?.genres ?? const <String>[];
    final readingLevel = metadata?.readingLevel;
    final avgPerSession =
        book.sessions > 0 ? book.totalMinutes ~/ book.sessions : 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiTokens.radiusXL),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Padding(
              padding: const EdgeInsets.only(top: LumiTokens.space2),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LumiTokens.rule,
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
              ),
            ),
            // Header — cover + title.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LumiTokens.space5,
                LumiTokens.space4,
                LumiTokens.space5,
                0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    height: 120,
                    child: BookCover(title: book.title, coverUrl: coverUrl),
                  ),
                  const SizedBox(width: LumiTokens.space4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: LumiType.subhead,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (author != null) ...[
                          const SizedBox(height: LumiTokens.space1),
                          Text(author, style: LumiType.body),
                        ],
                        if (publisher != null) ...[
                          const SizedBox(height: LumiTokens.space1),
                          Text(publisher, style: LumiType.caption),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LumiTokens.space4),
            const Divider(height: 1, color: LumiTokens.rule),
            // Scrollable detail.
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(LumiTokens.space5),
                children: [
                  Row(
                    children: [
                      _Stat(
                        icon: Icons.menu_book_rounded,
                        value: '${book.sessions}',
                        label: book.sessions == 1 ? 'Session' : 'Sessions',
                      ),
                      const SizedBox(width: LumiTokens.space2),
                      _Stat(
                        icon: Icons.timer_rounded,
                        value: formatReadingDuration(book.totalMinutes),
                        label: 'Total time',
                      ),
                      const SizedBox(width: LumiTokens.space2),
                      _Stat(
                        icon: Icons.timer_outlined,
                        value: formatReadingDuration(avgPerSession),
                        label: 'Avg / session',
                      ),
                    ],
                  ),
                  const SizedBox(height: LumiTokens.space3),
                  Row(
                    children: [
                      Expanded(
                        child: _DateChip(
                          label: 'First read',
                          value:
                              DateFormat('d MMM yyyy').format(book.firstReadAt),
                        ),
                      ),
                      const SizedBox(width: LumiTokens.space2),
                      Expanded(
                        child: _DateChip(
                          label: 'Last read',
                          value:
                              DateFormat('d MMM yyyy').format(book.lastReadAt),
                        ),
                      ),
                    ],
                  ),
                  if (readingLevel != null || genres.isNotEmpty) ...[
                    const SizedBox(height: LumiTokens.space3),
                    Wrap(
                      spacing: LumiTokens.space2,
                      runSpacing: LumiTokens.space2,
                      children: [
                        if (readingLevel != null)
                          _Tag('Level $readingLevel', LumiTokens.yellow),
                        ...genres.take(4).map((g) => _Tag(g, LumiTokens.blue)),
                      ],
                    ),
                  ],
                  if (pageCount != null || metadata?.isbn != null) ...[
                    const SizedBox(height: LumiTokens.space3),
                    Text(
                      [
                        if (pageCount != null) '$pageCount pages',
                        if (metadata?.isbn != null) 'ISBN ${metadata!.isbn}',
                      ].join('  ·  '),
                      style: LumiType.caption,
                    ),
                  ],
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: LumiTokens.space4),
                    Text(
                      'ABOUT THIS BOOK',
                      style: LumiType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: LumiTokens.muted,
                      ),
                    ),
                    const SizedBox(height: LumiTokens.space2),
                    Text(description, style: LumiType.body),
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

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Stat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: LumiTokens.space3),
        decoration: BoxDecoration(
          color: LumiTokens.cream,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: _accent),
            const SizedBox(height: LumiTokens.space1),
            Text(
              value,
              style: LumiType.body.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: LumiType.caption.copyWith(fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final String value;

  const _DateChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiTokens.space3,
        vertical: LumiTokens.space2,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LumiType.caption.copyWith(fontSize: 11)),
          Text(
            value,
            style: LumiType.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiTokens.space3,
        vertical: LumiTokens.space1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
      child: Text(
        label,
        style: LumiType.caption.copyWith(
          color: LumiTokens.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
