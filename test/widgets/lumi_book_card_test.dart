import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/lumi_book_card.dart';

void main() {
  Widget wrapWidget(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('LumiBookCard', () {
    testWidgets('displays book title', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(title: 'The Cat in the Hat'),
      ));

      expect(find.text('The Cat in the Hat'), findsOneWidget);
    });

    testWidgets('displays author when provided', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(
          title: 'Green Eggs and Ham',
          author: 'Dr. Seuss',
        ),
      ));

      expect(find.text('Dr. Seuss'), findsOneWidget);
    });

    testWidgets('hides author when null', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(title: 'Test Book'),
      ));

      // No author text should be displayed
      expect(find.text('Dr. Seuss'), findsNothing);
    });

    testWidgets('shows Library badge for library books', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(
          title: 'Library Book',
          bookType: BookType.library,
        ),
      ));

      expect(find.text('Library'), findsOneWidget);
    });

    testWidgets('shows Decodable badge for decodable books', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(
          title: 'Decodable Book',
          bookType: BookType.decodable,
        ),
      ));

      expect(find.text('Decodable'), findsOneWidget);
    });

    testWidgets('shows Book badge for other type', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(
          title: 'Other Book',
          bookType: BookType.other,
        ),
      ));

      expect(find.text('Book'), findsOneWidget);
    });

    testWidgets('defaults to BookType.other', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(title: 'Default Book'),
      ));

      expect(find.text('Book'), findsOneWidget);
    });

    testWidgets('displays status text when provided', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(
          title: 'Test Book',
          statusText: 'Assigned today',
        ),
      ));

      expect(find.text('Assigned today'), findsOneWidget);
    });

    testWidgets('shows chevron when onTap is provided', (tester) async {
      await tester.pumpWidget(wrapWidget(
        LumiBookCard(
          title: 'Tappable Book',
          onTap: () {},
        ),
      ));

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('hides chevron when onTap is null', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(title: 'Non-tappable Book'),
      ));

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('onTap callback fires on tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(wrapWidget(
        LumiBookCard(
          title: 'Tappable Book',
          onTap: () => tapped = true,
        ),
      ));

      await tester.tap(find.text('Tappable Book'));
      expect(tapped, true);
    });

    testWidgets('shows placeholder when no coverUrl', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const LumiBookCard(title: 'No Cover Book'),
      ));

      // Placeholder should show a book icon
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
    });

    testWidgets('BookType enum has 3 values', (tester) async {
      expect(BookType.values.length, 3);
      expect(BookType.values, contains(BookType.library));
      expect(BookType.values, contains(BookType.decodable));
      expect(BookType.values, contains(BookType.other));
    });
  });
}
