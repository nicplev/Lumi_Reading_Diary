import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';

/// Rounded card with soft shadow following minimal design system
class RoundedCard extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? borderRadius;

  const RoundedCard({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? MinimalTheme.white,
        borderRadius: BorderRadius.circular(
          borderRadius ?? MinimalTheme.radiusLarge,
        ),
        boxShadow: MinimalTheme.cardShadow(),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(
          borderRadius ?? MinimalTheme.radiusLarge,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            borderRadius ?? MinimalTheme.radiusLarge,
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(MinimalTheme.spaceM),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Animated rounded card with hover effect
class AnimatedRoundedCard extends StatefulWidget {
  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? borderRadius;

  const AnimatedRoundedCard({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding,
    this.onTap,
    this.borderRadius,
  });

  @override
  State<AnimatedRoundedCard> createState() => _AnimatedRoundedCardState();
}

class _AnimatedRoundedCardState extends State<AnimatedRoundedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: RoundedCard(
          backgroundColor: widget.backgroundColor,
          padding: widget.padding,
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}
