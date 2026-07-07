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
///   `lumi://widget/teacher` → opens TeacherHomeScreen
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
    // For `lumi://widget/home`, scheme=lumi, host=widget, path=/home — so the
    // action lives in pathSegments, not uri.host.
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (action == 'teacher') {
      router.go('/teacher/home');
      return;
    }

    final route = Uri(
      path: '/parent/home',
      queryParameters: {
        if (childId.isNotEmpty) 'widgetChildId': childId,
        'widgetAction': action == 'log' ? 'log' : 'home',
        'widgetTap': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    ).toString();

    router.go(route);
  }
}
