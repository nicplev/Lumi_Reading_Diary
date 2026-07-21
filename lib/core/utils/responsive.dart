import 'package:flutter/widgets.dart';

/// Shortest-side threshold (logical pixels) above which a device counts as
/// tablet-sized, matching Apple's iPad/iPhone size-class split.
const double kTabletBreakpoint = 600.0;

/// Whether [context]'s device is tablet-sized (iPad, Android tablet),
/// independent of current orientation. Phone-sized layouts (including
/// phones in landscape) always return false.
bool isTablet(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= kTabletBreakpoint;
