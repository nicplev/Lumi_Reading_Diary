import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/teacher/dashboard/models/widget_registry.dart';
import 'package:lumi_reading_tracker/screens/teacher/dashboard/widgets/widget_gallery_sheet.dart';

void main() {
  DashboardWidgetDefinition def(int i) => DashboardWidgetDefinition(
        id: 'w$i',
        displayName: 'Widget $i',
        description: 'Description for widget $i',
        icon: Icons.widgets,
        dataDependencies: const {},
        builder: (_) => const SizedBox(),
      );

  testWidgets(
      'gallery with many widgets scrolls inside a short sheet (no overflow)',
      (tester) async {
    // Regression: with all six widgets available the plain Column overflowed
    // the modal sheet by 22px on iPad. Constrain the sheet hard and verify
    // the list scrolls instead of overflowing.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: 420, // deliberately too short for 6 rows
            child: WidgetGallerySheet(
              availableWidgets: [for (var i = 0; i < 6; i++) def(i)],
              onAddWidget: (_) {},
            ),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull); // no RenderFlex overflow
    expect(find.text('Widget 0'), findsOneWidget);

    // Last item is reachable by scrolling.
    await tester.scrollUntilVisible(find.text('Widget 5'), 200);
    expect(find.text('Widget 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state still renders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WidgetGallerySheet(
          availableWidgets: const [],
          onAddWidget: (_) {},
        ),
      ),
    ));
    expect(find.text("You're using every widget"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
