import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';

/// Shared chrome for the allocation form cards.
///
/// On these deep Class pages the canvas stays neutral (cream/paper). Green is
/// spent only where it carries meaning — the selected option, focus, and the
/// primary action — not as decoration.
class AllocationFormCard extends StatelessWidget {
  const AllocationFormCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: child,
    );
  }
}

/// Numbered, neutral section header — frames the page as a guided 3-step
/// workflow (1 Reading type → 2 Schedule → 3 Students) without a green icon box.
class AllocationSectionHeader extends StatelessWidget {
  const AllocationSectionHeader({
    super.key,
    required this.step,
    required this.title,
  });

  final int step;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LumiTokens.cream,
            shape: BoxShape.circle,
            border: Border.all(color: LumiTokens.rule),
          ),
          child: Text(
            '$step',
            style: LumiType.button.copyWith(
              color: LumiTokens.muted,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: LumiType.subhead),
      ],
    );
  }
}

/// A full-width, descriptive choice row used for the mutually-exclusive
/// choosers (reading type, student scope). The icon carries a soft content
/// colour; the selected state is restrained — pale green fill, a 2px green
/// border and a green check — with the title kept in ink.
class AllocationOptionCard extends StatelessWidget {
  const AllocationOptionCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  /// Optional preview slot rendered below the description when selected
  /// (e.g. a strip of student avatars or group dots).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? LumiTokens.green.withValues(alpha: 0.08)
              : LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(
            color: isSelected ? LumiTokens.green : LumiTokens.rule,
            width: isSelected ? 2 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: LumiType.body.copyWith(
                          color: LumiTokens.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(description, style: LumiType.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: isSelected ? LumiTokens.green : LumiTokens.rule,
                ),
              ],
            ),
            if (isSelected && trailing != null) ...[
              const SizedBox(height: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Stacks option cards vertically with even gaps.
class AllocationOptionList extends StatelessWidget {
  const AllocationOptionList({super.key, required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          cards[i],
        ],
      ],
    );
  }
}

/// A bottom-sheet grabber handle in the warm rule colour.
class AllocationSheetGrabber extends StatelessWidget {
  const AllocationSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: LumiTokens.rule,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
    );
  }
}
