import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';

/// Semantic flavour of a Lumi toast. Drives the leading icon + accent colour,
/// reusing the same palette as the service-status banner so all transient
/// feedback reads as one system.
enum LumiToastType { success, error, info, warning }

extension LumiToastTypeVisuals on LumiToastType {
  /// Accent colour for the leading icon (and any action label).
  Color get accent {
    switch (this) {
      case LumiToastType.success:
        return LumiTokens.green;
      case LumiToastType.error:
        return LumiTokens.red;
      case LumiToastType.info:
        return LumiTokens.blue;
      case LumiToastType.warning:
        return LumiTokens.orange;
    }
  }

  IconData get icon {
    switch (this) {
      case LumiToastType.success:
        return Icons.check_circle_outline;
      case LumiToastType.error:
        return Icons.error_outline;
      case LumiToastType.info:
        return Icons.info_outline;
      case LumiToastType.warning:
        return Icons.warning_amber_rounded;
    }
  }

  /// Default on-screen lifetime when the caller doesn't override it. Errors and
  /// action toasts linger a little longer so they can be read / acted on.
  Duration get defaultDuration {
    switch (this) {
      case LumiToastType.error:
      case LumiToastType.warning:
        return const Duration(seconds: 4);
      case LumiToastType.success:
      case LumiToastType.info:
        return const Duration(seconds: 3);
    }
  }
}

/// One in-flight toast. Immutable; identified by an auto-assigned [id] so the
/// overlay can key its widgets and the controller can dismiss individually.
@immutable
class LumiToastData {
  const LumiToastData({
    required this.id,
    required this.message,
    required this.type,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });

  final int id;
  final String message;
  final LumiToastType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  bool get hasAction => actionLabel != null && onAction != null;
}

/// App-lifetime singleton that owns the queue of visible toasts. Any code can
/// fire a toast through the top-level [showLumiToast] — no [BuildContext]
/// required — and the [LumiToastOverlay] mounted in `main.dart` renders whatever
/// this controller holds.
class LumiToastController extends ChangeNotifier {
  LumiToastController._();
  static final LumiToastController instance = LumiToastController._();

  /// How many toasts stack on screen at once. Extra ones drop the oldest so the
  /// newest feedback is always visible (transient by nature — nothing is lost).
  static const int maxVisible = 3;

  final List<LumiToastData> _toasts = <LumiToastData>[];
  final Map<int, Timer> _timers = <int, Timer>{};
  int _nextId = 0;

  /// The currently visible toasts, oldest first.
  List<LumiToastData> get toasts => List<LumiToastData>.unmodifiable(_toasts);

  /// Enqueue a toast. Returns its id (rarely needed — auto-dismisses on a timer).
  int show(LumiToastData Function(int id) build) {
    final id = _nextId++;
    final data = build(id);
    _toasts.add(data);

    // Keep only the newest [maxVisible]; evict the oldest so a burst never
    // pushes toasts off the top of the screen.
    while (_toasts.length > maxVisible) {
      _removeAt(0);
    }

    _timers[id] = Timer(data.duration, () => dismiss(id));
    notifyListeners();
    return id;
  }

  /// Dismiss a specific toast (auto-expiry, tap, or swipe).
  void dismiss(int id) {
    final index = _toasts.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _removeAt(index);
    notifyListeners();
  }

  void _removeAt(int index) {
    final removed = _toasts.removeAt(index);
    _timers.remove(removed.id)?.cancel();
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _toasts.clear();
    super.dispose();
  }
}

/// Show a Lumi bento toast. Context-free — safe to call after an `await`
/// without a `mounted` guard, since it targets the app-wide overlay rather than
/// the current widget's `ScaffoldMessenger`.
///
/// - [type] selects the accent colour + leading icon (defaults to [info]).
/// - [duration] overrides the per-type default lifetime.
/// - [actionLabel] + [onAction] render a tappable action (e.g. "Undo"); tapping
///   runs [onAction] and dismisses the toast.
void showLumiToast({
  required String message,
  LumiToastType type = LumiToastType.info,
  Duration? duration,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  // An action toast lingers longer so the user has time to act.
  final resolved = duration ??
      (actionLabel != null && onAction != null
          ? const Duration(seconds: 6)
          : type.defaultDuration);
  LumiToastController.instance.show(
    (id) => LumiToastData(
      id: id,
      message: message,
      type: type,
      duration: resolved,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}
