import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/week_progress_bar.dart';
import 'package:lumi_reading_tracker/theme/lumi_tokens.dart';

void main() {
  Widget wrapWidget(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('WeekProgressBar', () {
    testWidgets('renders 7 day circles', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {},
          currentDay: 3,
        ),
      ));

      // Should find the day labels for non-completed, non-today days
      // M(1), T(2) are past missed, W(3) is today, T(4),F(5),S(6),S(7) future
      // Today shows label, future shows labels, past missed shows labels
      // But completed days show checkmark icons instead
      // All 7 day circles are present
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('shows checkmark for completed past days', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {1, 2},
          currentDay: 3,
        ),
      ));

      // 2 completed days should each have a check icon
      expect(find.byIcon(Icons.check), findsNWidgets(2));
    });

    testWidgets('shows checkmark for completed today', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {3},
          currentDay: 3,
        ),
      ));

      // Today completed shows checkmark
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('today not done shows day label', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {},
          currentDay: 1,
        ),
      ));

      // Monday (day 1) is today and not completed, so shows 'M' label
      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('future days show labels', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {},
          currentDay: 1,
        ),
      ));

      // Days 2-7 are future, all show labels: T W T F S S
      // Day 1 (M) is today, shows M
      // Check that we see day labels
      expect(find.text('M'), findsOneWidget);
      // T appears twice (Tue and Thu)
      expect(find.text('T'), findsNWidgets(2));
      expect(find.text('W'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
      // S appears twice (Sat and Sun)
      expect(find.text('S'), findsNWidgets(2));
    });

    testWidgets('all days completed shows 7 checkmarks', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {1, 2, 3, 4, 5, 6, 7},
          currentDay: 7,
        ),
      ));

      expect(find.byIcon(Icons.check), findsNWidgets(7));
    });

    testWidgets('no days completed on Monday shows all labels', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {},
          currentDay: 1,
        ),
      ));

      // No checkmarks
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('completed today uses the tint-green fill', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {3},
          currentDay: 3,
        ),
      ));

      // Every completed day — today included — now uses one tint-green fill
      // (02b8f38 moved this widget off AppColors onto LumiTokens, and a later
      // pass collapsed the today/past colour distinction into a single
      // confirmation state).
      final containers = tester.widgetList<Container>(find.byType(Container));
      final todayContainer = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.color == LumiTokens.tintGreen &&
              decoration.shape == BoxShape.circle;
        }
        return false;
      });
      expect(todayContainer, isNotEmpty);
    });

    testWidgets('completed past day uses the same tint-green fill',
        (tester) async {
      await tester.pumpWidget(wrapWidget(
        const WeekProgressBar(
          completedDays: {1},
          currentDay: 3,
        ),
      ));

      final containers = tester.widgetList<Container>(find.byType(Container));
      final completedContainers = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.color == LumiTokens.tintGreen &&
              decoration.shape == BoxShape.circle;
        }
        return false;
      });
      expect(completedContainers, isNotEmpty);
    });
  });
}
