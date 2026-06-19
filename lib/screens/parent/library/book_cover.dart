import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../core/widgets/lumi/persistent_cached_image.dart';

/// Brand-coloured palette for placeholder covers. Hashed by title so a given
/// book keeps the same colour across the shelf, list and detail sheet.
const _coverPalette = <Color>[
  LumiTokens.red,
  LumiTokens.orange,
  LumiTokens.green,
  LumiTokens.blue,
  LumiTokens.purple,
  LumiTokens.pink,
];

Color bookCoverColor(String title) =>
    _coverPalette[title.hashCode.abs() % _coverPalette.length];

/// A book cover that fills its parent's constraints — the cached cover image
/// when one has resolved, otherwise a soft letter-tile placeholder (or a small
/// spinner while metadata is still resolving).
class BookCover extends StatelessWidget {
  final String title;
  final String? coverUrl;
  final bool isLoading;
  final double radius;

  const BookCover({
    super.key,
    required this.title,
    this.coverUrl,
    this.isLoading = false,
    this.radius = LumiTokens.radiusMedium,
  });

  bool get _hasCover => coverUrl != null && coverUrl!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: _hasCover
          ? PersistentCachedImage(
              imageUrl: coverUrl!,
              fit: BoxFit.cover,
              fallback: _placeholder(),
            )
          : _placeholder(),
    );
  }

  /// Up to two initials from the title's first words (e.g. "Harry Potter…" →
  /// "HP", "Matilda" → "MA"), so a coverless book still reads as intentional.
  String get _initials {
    final words = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length == 1 ? w : w.substring(0, 2)).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  Widget _placeholder() {
    final color = bookCoverColor(title);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0.16),
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
                  color: color.withValues(alpha: 0.7),
                ),
              )
            : Text(
                _initials,
                style: LumiType.subhead.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}
