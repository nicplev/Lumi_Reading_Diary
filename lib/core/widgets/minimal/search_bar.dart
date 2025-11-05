import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Custom search bar with filter button
class CustomSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final Function(String)? onChanged;
  final Function(String)? onSubmitted;
  final VoidCallback? onFilterTap;
  final bool showFilter;

  const CustomSearchBar({
    super.key,
    this.controller,
    this.hintText = 'Search books...',
    this.onChanged,
    this.onSubmitted,
    this.onFilterTap,
    this.showFilter = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MinimalTheme.white,
        borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
        boxShadow: MinimalTheme.cardShadow(),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: MinimalTheme.textSecondary,
                  fontSize: 15,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: MinimalTheme.textSecondary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: MinimalTheme.spaceM,
                  vertical: 16,
                ),
              ),
              style: const TextStyle(
                fontSize: 15,
                color: MinimalTheme.textPrimary,
              ),
            ),
          ),
          if (showFilter)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: MinimalTheme.primaryPurple,
                    borderRadius: BorderRadius.circular(MinimalTheme.radiusSmall),
                  ),
                  child: const Icon(
                    Icons.tune,
                    color: MinimalTheme.white,
                    size: 20,
                  ),
                ),
                onPressed: onFilterTap,
              ),
            ),
        ],
      ),
    );
  }
}
