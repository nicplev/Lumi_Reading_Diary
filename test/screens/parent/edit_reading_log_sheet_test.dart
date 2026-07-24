import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import 'package:lumi_reading_tracker/screens/parent/widgets/edit_reading_log_sheet.dart';

/// Edit-this-log sheet (plan §5.2): the editable field set, the un-removable
/// last book, and the manual-title auto-commit rule (§4.2 — typed text is
/// retained without tapping any + affordance).
void main() {
  ReadingLogModel log({List<String> titles = const ['The Bad Guys']}) =>
      ReadingLogModel(
        id: 'log_1',
        studentId: 'student_1',
        parentId: 'parent_1',
        schoolId: 'school_1',
        classId: 'class_1',
        date: DateTime(2026, 7, 24, 19, 30),
        minutesRead: 15,
        targetMinutes: 20,
        status: LogStatus.completed,
        bookTitles: titles,
        notes: 'First note',
        createdAt: DateTime(2026, 7, 24, 19, 30),
        loggedByRole: LoggedByRole.parent,
        occurredOn: '2026-07-24',
        context: 'home',
      );

  Future<void> pumpSheet(WidgetTester tester, ReadingLogModel target) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showEditReadingLogSheet(context, target),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows current values and the immutable-date explanation',
      (tester) async {
    await pumpSheet(tester, log());

    expect(find.text('Edit this log'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('The Bad Guys'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'First note'), findsOneWidget);
    expect(
      find.textContaining("The session date can't be changed"),
      findsOneWidget,
    );
  });

  testWidgets('minutes steppers adjust within 1..240 and have 44pt targets',
      (tester) async {
    await pumpSheet(tester, log());

    await tester.tap(find.bySemanticsLabel('Increase minutes'));
    await tester.pump();
    expect(find.text('20 min'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Decrease minutes'));
    await tester.tap(find.bySemanticsLabel('Decrease minutes'));
    await tester.pump();
    expect(find.text('10 min'), findsOneWidget);

    final size =
        tester.getSize(find.bySemanticsLabel('Increase minutes'));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });

  testWidgets('keyboard Done commits a typed title without any + tap',
      (tester) async {
    await pumpSheet(tester, log());

    await tester.enterText(
        find.widgetWithText(TextField, 'Add a book title'), 'Dog Man');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Dog Man'), findsOneWidget,
        reason: 'typed text is retained as a chip, no + icon required');
  });

  testWidgets('the last remaining book cannot be removed', (tester) async {
    await pumpSheet(tester, log());

    final chip = tester.widget<InputChip>(find.byType(InputChip));
    expect(chip.onDeleted, isNull,
        reason: 'a session can never be edited into having no book');
  });

  testWidgets('duplicate typed title is not added twice', (tester) async {
    await pumpSheet(tester, log());

    await tester.enterText(
        find.widgetWithText(TextField, 'Add a book title'), 'the bad guys');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byType(InputChip), findsOneWidget,
        reason: 'case-insensitive dedupe against existing titles');
  });
}
