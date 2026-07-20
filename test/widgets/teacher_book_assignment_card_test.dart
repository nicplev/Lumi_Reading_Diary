import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/teacher_book_assignment_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

// This card used to own a PopupMenuButton (tooltip 'Book actions'). That was
// replaced by tap-the-whole-card -> modal bottom sheet, and the sheet now
// lives in the caller (student_detail_screen.dart). The card's only remaining
// responsibility here is showing the editable affordance, so the old
// menu-selection test was removed rather than rewritten against a widget that
// no longer has a menu.
void main() {
  group('TeacherBookAssignmentCard', () {
    testWidgets('shows the editable affordance only when actions are allowed',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TeacherBookAssignmentCard(
            title: 'Little Bear',
            subtitle: '20 min • Weekly',
            coverGradient: [Colors.green, Colors.green],
            bookType: 'library',
            status: 'new',
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

      await tester.pumpWidget(
        _wrap(
          TeacherBookAssignmentCard(
            title: 'Little Bear',
            subtitle: '20 min • Weekly',
            coverGradient: const [Colors.green, Colors.green],
            bookType: 'library',
            status: 'new',
            onActionSelected: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('tapping the card is what opens the caller-owned sheet',
        (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        _wrap(
          TeacherBookAssignmentCard(
            title: 'Far Away',
            subtitle: '20 min • Weekly',
            coverGradient: const [Colors.green, Colors.green],
            bookType: 'library',
            status: 'new',
            onActionSelected: (_) {},
            onTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.text('Far Away'));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });
  });
}
