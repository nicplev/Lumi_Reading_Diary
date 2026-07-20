import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/lumi_buttons.dart';
import 'package:lumi_reading_tracker/theme/lumi_tokens.dart';

// The determinate mode exists so a parent uploading a large comprehension
// recording can see the submit advancing. These pin the behaviour that makes
// it honest: it only appears when a progress value is supplied, it reflects
// that value, and it never overruns the track.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 380, child: child))),
      );

  Future<void> pumpButton(
    WidgetTester tester, {
    required bool isLoading,
    double? progress,
    String? loadingLabel,
    bool settle = true,
  }) async {
    await tester.pumpWidget(host(
      LumiPrimaryButton(
        onPressed: () {},
        text: 'Save reading log',
        isLoading: isLoading,
        progress: progress,
        loadingLabel: loadingLabel,
        isFullWidth: true,
        color: LumiTokens.green,
      ),
    ));
    // Settle the implicit fill/label animations; leaving them running trips
    // the "Timer still pending" invariant at teardown. Callers showing the
    // indeterminate spinner must pass settle: false — it never stops, so
    // pumpAndSettle would spin until the test times out.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // Advance past flutter_animate's entry animation so its timer is
      // flushed, without pumpAndSettle (the indeterminate spinner never ends).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('no progress value keeps the existing spinner', (tester) async {
    await pumpButton(tester, isLoading: true, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AnimatedFractionallySizedBox), findsNothing);
  });

  testWidgets('a progress value swaps the spinner for a determinate bar',
      (tester) async {
    await pumpButton(
      tester,
      isLoading: true,
      progress: 0.5,
      loadingLabel: 'Uploading recording',
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final bar = tester.widget<AnimatedFractionallySizedBox>(
      find.byType(AnimatedFractionallySizedBox),
    );
    expect(bar.widthFactor, 0.5);
    expect(bar.alignment, Alignment.centerLeft, reason: 'fills left to right');
    expect(find.text('Uploading recording'), findsOneWidget);
    expect(find.text('Save reading log'), findsNothing);
  });

  testWidgets('progress is clamped so an overshooting caller cannot throw',
      (tester) async {
    await pumpButton(tester, isLoading: true, progress: 1.4);
    expect(
      tester
          .widget<AnimatedFractionallySizedBox>(
            find.byType(AnimatedFractionallySizedBox),
          )
          .widthFactor,
      1.0,
    );

    await pumpButton(tester, isLoading: true, progress: -0.3);
    expect(
      tester
          .widget<AnimatedFractionallySizedBox>(
            find.byType(AnimatedFractionallySizedBox),
          )
          .widthFactor,
      0.0,
    );
  });

  testWidgets('progress is ignored when not loading', (tester) async {
    await pumpButton(tester, isLoading: false, progress: 0.5);

    expect(find.byType(AnimatedFractionallySizedBox), findsNothing);
    expect(find.text('Save reading log'), findsOneWidget);
  });

  testWidgets('falls back to the button text when no label is given',
      (tester) async {
    await pumpButton(tester, isLoading: true, progress: 0.2);
    expect(find.text('Save reading log'), findsOneWidget);
  });

  testWidgets('keeps the same height as the normal button', (tester) async {
    await pumpButton(tester, isLoading: false);
    final idle = tester.getSize(find.byType(LumiPrimaryButton));

    await pumpButton(tester, isLoading: true, progress: 0.3);
    final loading = tester.getSize(find.byType(LumiPrimaryButton));

    expect(loading.height, idle.height,
        reason: 'swapping mid-press must not shift the layout');
  });
}
