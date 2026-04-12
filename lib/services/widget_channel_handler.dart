import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

/// Listens for widget taps forwarded by the home_widget plugin and routes
/// them to the correct screen via GoRouter.
///
/// URL format: `lumi://widget/{action}?childId={studentId}`
///   `lumi://widget/log`  → opens LogReadingScreen (pre-selects child)
///   `lumi://widget/home` → opens ParentHomeScreen (pre-selects child)
class WidgetChannelHandler {
  WidgetChannelHandler._();

  static void initialize(GoRouter router) {
    if (kIsWeb || !Platform.isIOS) return;

    HomeWidget.widgetClicked.listen((uri) {
      if (uri == null) return;
      _handle(uri, router);
    });

    // Also handle the URL that launched the app from a cold start via widget tap.
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      if (uri != null) _handle(uri, router);
    });
  }

  static void _handle(Uri uri, GoRouter router) {
    final childId = uri.queryParameters['childId'] ?? '';
    final action = uri.host; // 'log' or 'home'

    switch (action) {
      case 'log':
        // Store child ID in query so the route builder can pre-select the child.
        // The route uses NavigationStateService; we pass childId via query param
        // and let ParentHomeScreen handle navigation into log-reading for that child.
        router.go('/parent/home?widgetChildId=$childId');
      case 'home':
      default:
        router.go('/parent/home?widgetChildId=$childId');
    }
  }
}
