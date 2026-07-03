import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/stats_card.dart';

void main() {
  Widget wrapWidget(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('StatsCard', () {
    testWidgets('displays all three stat values', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          totalNights: 48,
          currentStreak: 7,
          totalMinutes: 45,
        ),
      ));

      expect(find.text('48'), findsOneWidget); // nights
      expect(find.text('7'), findsOneWidget); // streak
      expect(find.text('45m'), findsOneWidget); // read time
    });

    testWidgets('displays stat labels', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          totalNights: 0,
          currentStreak: 0,
          totalMinutes: 0,
        ),
      ));

      expect(find.text('Nights'), findsOneWidget);
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('Read time'), findsOneWidget);
    });

    testWidgets('displays stat icons', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          totalNights: 3,
          currentStreak: 1,
          totalMinutes: 30,
        ),
      ));

      expect(find.byIcon(Icons.nightlight_round), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    testWidgets('renders with zero values', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          totalNights: 0,
          currentStreak: 0,
          totalMinutes: 0,
        ),
      ));

      // Nights and streak both render "0"; read time renders "0m".
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('0m'), findsOneWidget);
    });

    testWidgets('renders with large values', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          totalNights: 1000,
          currentStreak: 365,
          totalMinutes: 600,
        ),
      ));

      expect(find.text('1000'), findsOneWidget); // nights
      expect(find.text('365'), findsOneWidget); // streak
      expect(find.text('10h'), findsOneWidget); // 600 minutes -> 10h
    });

    testWidgets('has two vertical dividers between the three columns',
        (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          totalNights: 3,
          currentStreak: 1,
          totalMinutes: 30,
        ),
      ));

      // The three stat columns sit inside a single IntrinsicHeight > Row,
      // separated by two VerticalDivider rules.
      expect(find.byType(IntrinsicHeight), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNWidgets(2));
    });

    testWidgets('shows the rest-day reassurance footer when one rest day is left',
        (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          totalNights: 10,
          currentStreak: 5,
          totalMinutes: 120,
          restDaysRemaining: 1,
        ),
      ));

      expect(
        find.text('🌙 1 rest day left — your streak is safe'),
        findsOneWidget,
      );
    });
  });
}
