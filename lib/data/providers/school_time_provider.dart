import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/school_time.dart';

/// The school-local calendar day ('YYYY-MM-DD'), keyed by the school's IANA
/// timezone (null → server-default Australia/Sydney).
///
/// Emits immediately and again at every school-local midnight, so the Home
/// screen's "today" — row states, the sessions query window, and the quick-
/// slot date — rolls over without an app restart (persona date-handling
/// requirement). DST-safe: each firing re-derives the next midnight instead
/// of assuming 24-hour days.
final schoolTodayProvider =
    StreamProvider.family<String, String?>((ref, timezone) {
  final controller = StreamController<String>();
  Timer? timer;

  void emitAndArm() {
    if (controller.isClosed) return;
    controller.add(SchoolTime.todayFor(timezone));
    var delay = SchoolTime.nextMidnight(timezone).difference(DateTime.now());
    // Never arm a non-positive timer (clock skew right at midnight).
    if (delay <= Duration.zero) delay = const Duration(seconds: 1);
    timer = Timer(delay, emitAndArm);
  }

  emitAndArm();
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});
