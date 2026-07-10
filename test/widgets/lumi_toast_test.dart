import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/models/service_status.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/lumi_toast.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi_toast_overlay.dart';
import 'package:lumi_reading_tracker/data/providers/service_status_provider.dart';

void main() {
  // Mount the overlay with the service-status streams overridden to never emit,
  // so the banner-offset logic sees "no banner" and no singleton/network is
  // touched.
  Widget harness() {
    return ProviderScope(
      overrides: [
        serviceStatusProvider
            .overrideWith((ref) => Stream<ServiceStatusSnapshot>.empty()),
        pendingSyncHealthProvider
            .overrideWith((ref) => Stream<PendingSyncHealth>.empty()),
      ],
      child: const MaterialApp(
        home: LumiToastOverlay(
          child: Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
  }

  // The controller is an app-lifetime singleton with per-toast auto-dismiss
  // timers. Any toast left alive at the end of a test would trip flutter_test's
  // "Timer still pending" invariant (which runs before tearDown), so each test
  // clears its toasts before returning; this also cancels their timers.
  Future<void> clearToasts(WidgetTester tester) async {
    for (final t in LumiToastController.instance.toasts) {
      LumiToastController.instance.dismiss(t.id);
    }
    await tester.pump();
  }

  testWidgets('shows a success toast (message + icon) then auto-dismisses',
      (tester) async {
    await tester.pumpWidget(harness());
    expect(find.text('Saved'), findsNothing);

    showLumiToast(
      message: 'Saved',
      type: LumiToastType.success,
      duration: const Duration(seconds: 2),
    );
    await tester.pump(); // controller notifies → rebuild
    await tester.pump(const Duration(milliseconds: 300)); // entrance animation

    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    // Auto-dismiss after its duration.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('error toast uses the error icon', (tester) async {
    await tester.pumpWidget(harness());
    showLumiToast(
      message: 'Something went wrong',
      type: LumiToastType.error,
      duration: const Duration(seconds: 30),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await clearToasts(tester);
  });

  testWidgets('renders an action and fires its callback on tap',
      (tester) async {
    await tester.pumpWidget(harness());
    var undone = false;
    showLumiToast(
      message: 'Log removed',
      type: LumiToastType.info,
      actionLabel: 'Undo',
      onAction: () => undone = true,
      duration: const Duration(seconds: 30),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(undone, isTrue);
    // Tapping the action also dismisses the toast.
    await tester.pumpAndSettle();
    expect(find.text('Log removed'), findsNothing);
  });

  testWidgets('caps visible toasts at maxVisible, keeping the newest',
      (tester) async {
    await tester.pumpWidget(harness());
    for (var i = 0; i < 5; i++) {
      showLumiToast(
        message: 'Toast $i',
        type: LumiToastType.info,
        duration: const Duration(seconds: 30),
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(LumiToastController.instance.toasts.length,
        LumiToastController.maxVisible);
    expect(find.text('Toast 0'), findsNothing); // evicted (oldest)
    expect(find.text('Toast 4'), findsOneWidget); // newest kept

    await clearToasts(tester);
  });
}
