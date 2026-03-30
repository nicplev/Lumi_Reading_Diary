import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/teacher_book_assignment_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('TeacherBookAssignmentCard action menu', () {
    testWidgets('shows action menu only when callback is provided',
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

      expect(find.byTooltip('Book actions'), findsNothing);

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

      expect(find.byTooltip('Book actions'), findsOneWidget);
    });

    testWidgets('selecting menu item sends selected action', (tester) async {
      TeacherBookCardAction? selectedAction;

      await tester.pumpWidget(
        _wrap(
          TeacherBookAssignmentCard(
            title: 'Far Away',
            subtitle: '20 min • Weekly',
            coverGradient: const [Colors.green, Colors.green],
            bookType: 'library',
            status: 'new',
            onActionSelected: (action) => selectedAction = action,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Book actions'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Swap'));
      await tester.pumpAndSettle();

      expect(selectedAction, TeacherBookCardAction.swap);
    });
  });
}
