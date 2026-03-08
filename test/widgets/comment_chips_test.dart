import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/comment_chips.dart';

void main() {
  Widget wrapWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  group('CommentChips', () {
    testWidgets('displays heading and subtitle', (tester) async {
      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const [],
          onCommentsChanged: (_) {},
        ),
      ));

      expect(find.text('How did it go?'), findsOneWidget);
      expect(find.text('Select any that apply (optional)'), findsOneWidget);
    });

    testWidgets('displays all category headers', (tester) async {
      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const [],
          onCommentsChanged: (_) {},
        ),
      ));

      expect(find.text('Encouragement'), findsOneWidget);
      expect(find.text('Reading Skills'), findsOneWidget);
      expect(find.text('Comprehension'), findsOneWidget);
    });

    testWidgets('displays comment text in chips', (tester) async {
      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const [],
          onCommentsChanged: (_) {},
        ),
      ));

      expect(find.text('Great job!'), findsOneWidget);
      expect(find.text('Keep it up!'), findsOneWidget);
      expect(find.text('Sounded out words well'), findsOneWidget);
      expect(find.text('Understood the story well'), findsOneWidget);
    });

    testWidgets('tapping a chip adds it to selection', (tester) async {
      List<String>? result;

      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const [],
          onCommentsChanged: (comments) => result = comments,
        ),
      ));

      await tester.tap(find.text('Great job!'));
      await tester.pump();

      expect(result, isNotNull);
      expect(result, contains('Great job!'));
    });

    testWidgets('tapping a selected chip removes it', (tester) async {
      List<String>? result;

      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const ['Great job!'],
          onCommentsChanged: (comments) => result = comments,
        ),
      ));

      await tester.tap(find.text('Great job!'));
      await tester.pump();

      expect(result, isNotNull);
      expect(result, isNot(contains('Great job!')));
    });

    testWidgets('selected chip shows checkmark icon', (tester) async {
      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const ['Great job!'],
          onCommentsChanged: (_) {},
        ),
      ));

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('unselected chips show no checkmark', (tester) async {
      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const [],
          onCommentsChanged: (_) {},
        ),
      ));

      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('multiple chips can be selected', (tester) async {
      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const ['Great job!', 'Keep it up!', 'Made predictions'],
          onCommentsChanged: (_) {},
        ),
      ));

      // 3 selected chips should each show a checkmark
      expect(find.byIcon(Icons.check), findsNWidgets(3));
    });

    testWidgets('multi-select adds to existing selection', (tester) async {
      List<String>? result;

      await tester.pumpWidget(wrapWidget(
        CommentChips(
          selectedComments: const ['Great job!'],
          onCommentsChanged: (comments) => result = comments,
        ),
      ));

      await tester.tap(find.text('Keep it up!'));
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.length, 2);
      expect(result, contains('Great job!'));
      expect(result, contains('Keep it up!'));
    });
  });
}
