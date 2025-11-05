import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Selectable chip for genres or categories
class GenreChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? color;

  const GenreChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? MinimalTheme.primaryPurple;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : chipColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
          border: Border.all(
            color: isSelected ? chipColor : chipColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? MinimalTheme.white : chipColor,
          ),
        ),
      ),
    );
  }
}

/// Wrapper widget for multiple genre chips
class GenreChipList extends StatelessWidget {
  final List<String> genres;
  final List<String> selectedGenres;
  final Function(String)? onGenreSelected;

  const GenreChipList({
    super.key,
    required this.genres,
    this.selectedGenres = const [],
    this.onGenreSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: genres.map((genre) {
        return GenreChip(
          label: genre,
          isSelected: selectedGenres.contains(genre),
          onTap: () => onGenreSelected?.call(genre),
        );
      }).toList(),
    );
  }
}
