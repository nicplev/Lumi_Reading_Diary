import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Pill-shaped tab bar with smooth transitions
class PillTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final Function(int) onTabSelected;

  const PillTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MinimalTheme.lightPurple.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
      ),
      child: Row(
        children: List.generate(
          tabs.length,
          (index) => Expanded(
            child: GestureDetector(
              onTap: () => onTabSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selectedIndex == index
                      ? MinimalTheme.primaryPurple
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selectedIndex == index
                        ? MinimalTheme.white
                        : MinimalTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
