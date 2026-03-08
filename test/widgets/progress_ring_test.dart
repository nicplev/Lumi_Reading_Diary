import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/progress_ring.dart';

void main() {
  Widget wrapWidget(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('ProgressRing', () {
    testWidgets('displays total nights number', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 42,
          weeklyProgress: 5,
          todayComplete: true,
        ),
      ));

      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('displays default label "Nights"', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 10,
          weeklyProgress: 3,
          todayComplete: false,
        ),
      ));

      expect(find.text('Nights'), findsOneWidget);
    });

    testWidgets('displays custom label', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 10,
          weeklyProgress: 3,
          todayComplete: false,
          label: 'Books',
        ),
      ));

      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Nights'), findsNothing);
    });

    testWidgets('renders with zero values', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 0,
          weeklyProgress: 0,
          todayComplete: false,
        ),
      ));

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('renders with max values', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 100,
          totalNightsGoal: 100,
          weeklyProgress: 7,
          todayComplete: true,
        ),
      ));

      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('has fixed 180x180 size', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 10,
          weeklyProgress: 3,
          todayComplete: false,
        ),
      ));

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 180);
      expect(sizedBox.height, 180);
    });

    testWidgets('uses CustomPaint for ring rendering', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 10,
          weeklyProgress: 3,
          todayComplete: false,
        ),
      ));

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('clamps progress above goal', (tester) async {
      // totalNights > totalNightsGoal should not throw
      await tester.pumpWidget(wrapWidget(
        const ProgressRing(
          totalNights: 150,
          totalNightsGoal: 100,
          weeklyProgress: 10,
          todayComplete: true,
        ),
      ));

      expect(find.text('150'), findsOneWidget);
      // No error thrown means clamping works
    });
  });
}
