import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Wraps a dashboard widget card during edit mode with:
/// - A jiggle (wobble) animation similar to iOS home screen
/// - An X button overlay in the top-left for removal
/// - A slight scale-down to 0.95
class EditModeWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onRemove;

  const EditModeWrapper({
    super.key,
    required this.child,
    required this.onRemove,
  });

  @override
  State<EditModeWrapper> createState() => _EditModeWrapperState();
}

class _EditModeWrapperState extends State<EditModeWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _jiggleController;
  late final double _phaseOffset;

  @override
  void initState() {
    super.initState();
    // Randomise phase so cards don't wobble in sync
    _phaseOffset = math.Random().nextDouble() * math.pi * 2;
    _jiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _jiggleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _jiggleController,
      builder: (context, child) {
        final t = _jiggleController.value;
        final angle =
            math.sin(t * math.pi * 2 + _phaseOffset) * 0.008; // ~0.45 degrees
        return Transform.rotate(
          angle: angle,
          child: child,
        );
      },
      child: Transform.scale(
        scale: 0.95,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            Positioned(
              top: -8,
              left: -8,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onRemove();
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
