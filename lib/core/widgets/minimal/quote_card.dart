import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';
import 'rounded_card.dart';

/// Quote display card with book attribution
class QuoteCard extends StatelessWidget {
  final String quote;
  final String bookTitle;
  final String author;
  final int? pageNumber;
  final VoidCallback? onShare;
  final VoidCallback? onSave;

  const QuoteCard({
    super.key,
    required this.quote,
    required this.bookTitle,
    required this.author,
    this.pageNumber,
    this.onShare,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      backgroundColor: MinimalTheme.lightPurple.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quote Icon
          const Icon(
            Icons.format_quote,
            size: 32,
            color: MinimalTheme.primaryPurple,
          ),
          const SizedBox(height: MinimalTheme.spaceM),

          // Quote Text
          Text(
            quote,
            style: const TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: MinimalTheme.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: MinimalTheme.spaceM),

          // Book Info
          Container(
            padding: const EdgeInsets.all(MinimalTheme.spaceM),
            decoration: BoxDecoration(
              color: MinimalTheme.white,
              borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MinimalTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        author,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MinimalTheme.textSecondary,
                        ),
                      ),
                      if (pageNumber != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Page $pageNumber',
                          style: const TextStyle(
                            fontSize: 11,
                            color: MinimalTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onShare != null)
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    onPressed: onShare,
                    color: MinimalTheme.primaryPurple,
                  ),
                if (onSave != null)
                  IconButton(
                    icon: const Icon(Icons.bookmark_outline),
                    onPressed: onSave,
                    color: MinimalTheme.primaryPurple,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
