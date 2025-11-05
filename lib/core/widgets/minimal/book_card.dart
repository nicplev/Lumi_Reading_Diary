import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Book card with cover image and reading progress
class BookCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String author;
  final double progress;
  final int currentPage;
  final int totalPages;
  final VoidCallback? onTap;
  final bool showProgress;

  const BookCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.author,
    this.progress = 0.0,
    this.currentPage = 0,
    this.totalPages = 0,
    this.onTap,
    this.showProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: MinimalTheme.white,
          borderRadius: BorderRadius.circular(MinimalTheme.radiusLarge),
          boxShadow: MinimalTheme.cardShadow(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Book Cover
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(MinimalTheme.radiusLarge),
              ),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: imageUrl.startsWith('http')
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(MinimalTheme.spaceM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MinimalTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Author
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MinimalTheme.textSecondary,
                    ),
                  ),

                  if (showProgress) ...[
                    const SizedBox(height: MinimalTheme.spaceM),

                    // Progress Bar
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(MinimalTheme.radiusPill),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: MinimalTheme.lightPurple,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          MinimalTheme.primaryPurple,
                        ),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Page Count
                    Text(
                      '$currentPage / $totalPages pages',
                      style: const TextStyle(
                        fontSize: 11,
                        color: MinimalTheme.textSecondary,
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

  Widget _buildPlaceholder() {
    return Container(
      color: MinimalTheme.lightPurple,
      child: const Center(
        child: Icon(
          Icons.book,
          size: 48,
          color: MinimalTheme.primaryPurple,
        ),
      ),
    );
  }
}

/// Horizontal book list item
class BookListItem extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String author;
  final double? rating;
  final String? genre;
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback? onMoreTap;

  const BookListItem({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.author,
    this.rating,
    this.genre,
    this.progress,
    this.onTap,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: MinimalTheme.spaceM),
      decoration: BoxDecoration(
        color: MinimalTheme.white,
        borderRadius: BorderRadius.circular(MinimalTheme.radiusLarge),
        boxShadow: MinimalTheme.cardShadow(),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(MinimalTheme.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MinimalTheme.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(MinimalTheme.spaceM),
            child: Row(
              children: [
                // Book Cover
                ClipRRect(
                  borderRadius: BorderRadius.circular(MinimalTheme.radiusSmall),
                  child: SizedBox(
                    width: 60,
                    height: 90,
                    child: imageUrl.startsWith('http')
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),
                const SizedBox(width: MinimalTheme.spaceM),

                // Book Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MinimalTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: MinimalTheme.textSecondary,
                        ),
                      ),
                      if (genre != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: MinimalTheme.lightPurple,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            genre!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: MinimalTheme.primaryPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (rating != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < rating!
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 16,
                              color: MinimalTheme.orange,
                            );
                          }),
                        ),
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(MinimalTheme.radiusPill),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: MinimalTheme.lightPurple,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              MinimalTheme.primaryPurple,
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // More Button
                if (onMoreTap != null)
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: onMoreTap,
                    color: MinimalTheme.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: MinimalTheme.lightPurple,
      child: const Icon(
        Icons.book,
        color: MinimalTheme.primaryPurple,
        size: 24,
      ),
    );
  }
}
