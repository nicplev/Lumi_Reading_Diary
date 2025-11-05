// This is a basic Flutter widget test for Lumi Reading Tracker.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumi_reading_tracker/main.dart';

void main() {
  testWidgets('Lumi app launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: LumiApp(),
      ),
    );

    // Wait for any animations to complete
    await tester.pumpAndSettle();

    // Verify that the app launches (checking for common UI elements)
    // The splash screen should show the app title
    expect(find.text('Lumi'), findsWidgets);
  });
}
