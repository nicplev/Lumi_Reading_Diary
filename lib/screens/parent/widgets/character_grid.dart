import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/characters/lumi_character.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../theme/lumi_tokens.dart';

/// Reusable grid of selectable Lumi characters.
///
/// Renders [LumiCharacters.all] as a 3-column grid of character images with
/// the name beneath each and an animated selected state (no background ring —
/// selection shows as a scale-up, a check badge, and a bold pink label). Shared
/// by the character picker bottom sheet and the link-child onboarding flow so
/// both surfaces look identical.
///
/// The grid shrink-wraps and disables its own scrolling, so drop it inside a
/// scrollable parent (a sheet body or a `SingleChildScrollView`).
class CharacterGrid extends StatelessWidget {
  /// The currently selected character id, or null when none is chosen.
  final String? selectedId;

  /// Called with the tapped character's id.
  final ValueChanged<String> onSelect;

  const CharacterGrid({
    super.key,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: LumiCharacters.all.length,
      itemBuilder: (context, index) {
        final character = LumiCharacters.all[index];
        final isSelected = selectedId == character.id;

        return _CharacterTile(
          character: character,
          isSelected: isSelected,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(character.id);
          },
        );
      },
    );
  }
}

class _CharacterTile extends StatelessWidget {
  final LumiCharacter character;
  final bool isSelected;
  final VoidCallback onTap;

  const _CharacterTile({
    required this.character,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: isSelected ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              // clipBehavior: none keeps the inset badge fully visible even at
              // the grid's edge columns.
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  // Image is centered within the full cell width by BoxFit.contain.
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      character.assetPath,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 4,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: LumiTokens.green,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: LumiTokens.paper, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              character.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: LumiTextStyles.bodySmall(
                color: isSelected
                    ? LumiTokens.green
                    : AppColors.charcoal.withValues(alpha: 0.75),
              ).copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
