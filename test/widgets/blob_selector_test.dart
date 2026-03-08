import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/blob_selector.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';

void main() {
  // Disable flutter_animate in tests to avoid pending timer issues
  setUp(() {
    Animate.restartOnHotReload = false;
  });

  Widget wrapWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  group('BlobSelector', () {
    testWidgets('displays heading text', (tester) async {
      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          onFeelingSelected: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('How did reading feel?'), findsOneWidget);
      expect(find.text('Let your child choose'), findsOneWidget);
    });

    testWidgets('displays all 5 blob labels', (tester) async {
      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          onFeelingSelected: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Hard'), findsOneWidget);
      expect(find.text('Tricky'), findsOneWidget);
      expect(find.text('Okay'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Great!'), findsOneWidget);
    });

    testWidgets('tapping a blob calls onFeelingSelected', (tester) async {
      ReadingFeeling? selected;

      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          onFeelingSelected: (feeling) => selected = feeling,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Great!'));
      await tester.pumpAndSettle();

      expect(selected, ReadingFeeling.great);
    });

    testWidgets('tapping Hard returns ReadingFeeling.hard', (tester) async {
      ReadingFeeling? selected;

      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          onFeelingSelected: (feeling) => selected = feeling,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hard'));
      await tester.pumpAndSettle();

      expect(selected, ReadingFeeling.hard);
    });

    testWidgets('tapping Okay returns ReadingFeeling.okay', (tester) async {
      ReadingFeeling? selected;

      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          onFeelingSelected: (feeling) => selected = feeling,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Okay'));
      await tester.pumpAndSettle();

      expect(selected, ReadingFeeling.okay);
    });

    testWidgets('renders with pre-selected feeling', (tester) async {
      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          selectedFeeling: ReadingFeeling.good,
          onFeelingSelected: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Good'), findsOneWidget);
    });

    testWidgets('renders with no selection', (tester) async {
      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          selectedFeeling: null,
          onFeelingSelected: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Hard'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
    });

    testWidgets('each blob has an Image.asset widget', (tester) async {
      await tester.pumpWidget(wrapWidget(
        BlobSelector(
          onFeelingSelected: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      // 5 blobs with Image.asset (which will show error builder since assets
      // aren't available in test, but the widget still renders)
      expect(find.byType(Image), findsNWidgets(5));
    });
  });
}
