import 'package:flutter/widgets.dart';

/// Reduce Motion support: animation chains must be gated on this instead of
/// running unconditionally (accessibility requirement — plan §3.6).
///
/// `MediaQuery.disableAnimations` is true when the platform's Reduce Motion
/// (iOS) / Remove Animations (Android) setting is on.
extension MotionAllowed on BuildContext {
  bool get motionAllowed => !MediaQuery.of(this).disableAnimations;
}
