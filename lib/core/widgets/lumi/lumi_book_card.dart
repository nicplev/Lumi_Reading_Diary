import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// Book type for badge coloring
enum BookType {
  library,
  decodable,
  other,
}

/// Lumi Design System - Book Card
///
/// Displays a book with cover thumbnail, title, type badge, and status.
/// Matches Style Preview: 16px radius, 12px padding, flex layout.
class LumiBookCard extends StatelessWidget {
  final String title;
  final String? author;
  final BookType bookType;
  final String? statusText;
  final String? coverUrl;
  final VoidCallback? onTap;

  const LumiBookCard({
    super.key,
    required this.title,
    this.author,
    this.bookType = BookType.other,
    this.statusText,
    this.coverUrl,
    this.onTap,
  });

  Color get _badgeColor {
    switch (bookType) {
      case BookType.library:
        return AppColors.libraryGreen;
      case BookType.decodable:
        return AppColors.decodableBlue;
      case BookType.other:
        return AppColors.textSecondary;
    }
  }

  String get _badgeLabel {
    switch (bookType) {
      case BookType.library:
        return 'Library';
      case BookType.decodable:
        return 'Decodable';
      case BookType.other:
        return 'Book';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.charcoal.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Book cover thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 65,
                child: coverUrl != null && coverUrl!.startsWith('http')
                    ? Image.network(
                        coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),

            // Book info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LumiTextStyles.bodyMedium(color: AppColors.charcoal)
                        .copyWith(fontSize: 15),
                  ),
                  if (author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LumiTextStyles.caption(),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _badgeLabel,
                          style: LumiTextStyles.caption(color: _badgeColor)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (statusText != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          statusText!,
                          style: LumiTextStyles.caption(),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Chevron
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: AppColors.charcoal.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _badgeColor.withValues(alpha: 0.3),
            _badgeColor.withValues(alpha: 0.1),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.menu_book,
          size: 24,
          color: _badgeColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
