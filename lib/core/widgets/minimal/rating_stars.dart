import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Star rating widget with interactive and display modes
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  final bool isInteractive;
  final Function(double)? onRatingChanged;
  final Color activeColor;
  final Color inactiveColor;

  const RatingStars({
    super.key,
    required this.rating,
    this.size = 24,
    this.isInteractive = false,
    this.onRatingChanged,
    this.activeColor = MinimalTheme.orange,
    this.inactiveColor = MinimalTheme.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return GestureDetector(
          onTap: isInteractive ? () => onRatingChanged?.call(index + 1.0) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              _getStarIcon(index),
              size: size,
              color: _getStarColor(index),
            ),
          ),
        );
      }),
    );
  }

  IconData _getStarIcon(int index) {
    if (rating >= index + 1) {
      return Icons.star;
    } else if (rating > index && rating < index + 1) {
      return Icons.star_half;
    } else {
      return Icons.star_border;
    }
  }

  Color _getStarColor(int index) {
    if (rating > index) {
      return activeColor;
    } else {
      return inactiveColor.withValues(alpha: 0.3);
    }
  }
}
