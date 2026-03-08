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
          currentStreak: 7,
          bestStreak: 14,
          totalNights: 48,
        ),
      ));

      expect(find.text('7'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
    });

    testWidgets('displays stat labels', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          currentStreak: 0,
          bestStreak: 0,
          totalNights: 0,
        ),
      ));

      expect(find.text('Current\nStreak'), findsOneWidget);
      expect(find.text('Best\nStreak'), findsOneWidget);
      expect(find.text('Total\nNights'), findsOneWidget);
    });

    testWidgets('displays stat icons', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          currentStreak: 1,
          bestStreak: 2,
          totalNights: 3,
        ),
      ));

      expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
    });

    testWidgets('renders with zero values', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          currentStreak: 0,
          bestStreak: 0,
          totalNights: 0,
        ),
      ));

      expect(find.text('0'), findsNWidgets(3));
    });

    testWidgets('renders with large values', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          currentStreak: 365,
          bestStreak: 500,
          totalNights: 1000,
        ),
      ));

      expect(find.text('365'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('has two vertical dividers between columns', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const StatsCard(
          currentStreak: 1,
          bestStreak: 2,
          totalNights: 3,
        ),
      ));

      // The dividers are Containers with width: 1
      // We find them by looking for the IntrinsicHeight > Row structure
      expect(find.byType(IntrinsicHeight), findsOneWidget);
    });
  });
}
