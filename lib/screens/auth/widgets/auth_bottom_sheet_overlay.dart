import 'dart:ui';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

/// Floating bottom-card chrome shared by the parent registration modal and
/// the phone-verify recovery screen. Both routes use the same blurred /
/// dimmed backdrop, the same bottom-aligned slide-in card, and the same
/// reverse-transition slide-out, so the user can't tell when the recovery
/// flow has taken over from the live registration modal.
///
/// Use as a route's top-level widget — it pulls the route's animation off
/// [ModalRoute.of] to drive the blur and slide. `barrierColor:
/// Colors.transparent` + `opaque: false` on the route preserves the
/// underlying screen so the blur has something to blur.
class AuthBottomSheetOverlay extends StatelessWidget {
  const AuthBottomSheetOverlay({
    super.key,
    required this.card,
    this.dismissOnTapOutside = true,
    this.debugLabel = 'auth-overlay',
  });

  /// The floating card that rises from the bottom. Renders with the route's
  /// animation already running, so the card's own `.animate()` chain can
  /// drive any per-element intro.
  final Widget card;

  /// When true, tapping the backdrop pops the route. The registration modal
  /// uses `true` (its only action is "cancel"); the recovery screen uses
  /// `false` because it has its own Cancel button and an accidental dismiss
  /// would lose the in-flight verification ID.
  final bool dismissOnTapOutside;

  /// Tag for the `[phone-auth]` debug print fired on a backdrop tap. Helps
  /// pin down which overlay was dismissed when triaging iOS reCAPTCHA
  /// teardowns from logs.
  final String debugLabel;

  static const double _kMaxBlur = 18;
  static const double _kMaxDim = 0.18;

  @override
  Widget build(BuildContext context) {
    final animation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismissOnTapOutside
                  ? () {
                      if (kDebugMode) {
                        debugPrint(
                            '[phone-auth] $debugLabel → tap-outside-card → maybePop()');
                      }
                      Navigator.of(context).maybePop();
                    }
                  : null,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final raw = animation.value.clamp(0.0, 1.0);
                  // easeInCubic stays near 0 early so the blur visibly ramps
                  // up instead of hitting peak sigma immediately.
                  final blurT = Curves.easeInCubic.transform(raw);
                  final dimT = Curves.easeInOutCubic.transform(raw);
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: _kMaxBlur * blurT,
                      sigmaY: _kMaxBlur * blurT,
                    ),
                    child: Container(
                      color: Colors.black.withValues(alpha: _kMaxDim * dimT),
                    ),
                  );
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: animation,
              // Keep the wrapper tree shape constant across the whole lifecycle
              // (swapping between `child` and `Opacity>Transform>child` would
              // re-parent the card and cause a one-frame flicker on dismiss).
              // Entrance runs at opacity 1 / dy 0, so the card's own
              // .animate() chain drives the intro; during reverse we slide it
              // off the bottom.
              builder: (context, child) {
                final isReversing =
                    animation.status == AnimationStatus.reverse ||
                        animation.status == AnimationStatus.dismissed;
                final raw = animation.value.clamp(0.0, 1.0);
                final slideT =
                    isReversing ? Curves.easeInCubic.transform(1 - raw) : 0.0;
                final opacity = isReversing ? raw : 1.0;
                return Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, slideT * 220),
                    child: child,
                  ),
                );
              },
              child: card,
            ),
          ),
        ],
      ),
    );
  }
}
