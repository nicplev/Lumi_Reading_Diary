import 'package:flutter/widgets.dart';

/// Releases keyboard focus whenever a new route is pushed.
///
/// `showModalBottomSheet` and `showDialog` push `ModalBottomSheetRoute` /
/// `DialogRoute` onto the navigator, so a single observer covers ordinary route
/// pushes, bottom sheets AND dialogs. This fixes a whole class of TestFlight
/// reports where a keyboard survived a navigation into a context whose text
/// field was gone or hidden (e.g. opening the comments sheet over a screen whose
/// search field still held focus).
///
/// Only `didPush` unfocuses. `didPop` deliberately does NOT: popping a sheet back
/// to a screen whose field was legitimately focused should not clear it.
///
/// A screen that intentionally autofocuses a field claims focus when its route
/// builds, which happens after this fires, so autofocus is unaffected.
class UnfocusOnRouteChangeObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
