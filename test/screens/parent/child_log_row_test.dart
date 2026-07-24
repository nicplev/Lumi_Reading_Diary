import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/screens/parent/widgets/child_log_row.dart';

/// The Home row state machine + layout invariants
/// (docs/PARENT_LOGGING_FLOW_PLAN.md §3, acceptance #1/#2/#5/#13):
///  - labelled button, never a check-circle;
///  - the trailing action never morphs into Undo in place;
///  - rows never move or resize when a sibling logs;
///  - fully operable at 2.0 text scale;
///  - VoiceOver labels state child + book + minutes.
void main() {
  const myUid = 'parent_me';
  const otherUid = 'parent_other';

  StudentModel student({String id = 'student_1', bool activeAccess = true}) =>
      StudentModel(
        id: id,
        firstName: 'Lincoln',
        lastName: 'Reader',
        schoolId: 'school_1',
        classId: 'class_1',
        createdAt: DateTime(2026, 1, 1),
        access: StudentAccess(
          status: activeAccess
              ? StudentAccess.statusActive
              : StudentAccess.statusExpired,
          academicYear: 2026,
          expiresAt: activeAccess
              ? DateTime.now().add(const Duration(days: 365))
              : DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

  ReadingLogModel log({
    String id = 'log_1',
    String parentId = myUid,
    int minutes = 15,
    String? context,
    List<String> titles = const ['The Bad Guys'],
    String loggedByName = 'Jordan',
  }) =>
      ReadingLogModel(
        id: id,
        studentId: 'student_1',
        parentId: parentId,
        schoolId: 'school_1',
        classId: 'class_1',
        date: DateTime(2026, 7, 24, 19, 30),
        minutesRead: minutes,
        targetMinutes: 20,
        status: LogStatus.completed,
        bookTitles: titles,
        createdAt: DateTime(2026, 7, 24, 19, 30),
        loggedByName: loggedByName,
        loggedByRole: LoggedByRole.parent,
        occurredOn: '2026-07-24',
        context: context,
      );

  ChildLogRowState derive({
    List<ReadingLogModel> todayLogs = const [],
    List<String> titles = const ['The Bad Guys'],
    bool quickLoggingEnabled = true,
    bool submitting = false,
    String? justCreatedLogId,
    bool activeAccess = true,
  }) =>
      deriveChildLogRowState(
        student: student(activeAccess: activeAccess),
        todayLogs: todayLogs,
        resolvedBookTitles: titles,
        usualMinutes: 15,
        quickLoggingEnabled: quickLoggingEnabled,
        submitting: submitting,
        myUid: myUid,
        justCreatedLogId: justCreatedLogId,
      );

  group('deriveChildLogRowState', () {
    test('inactive access wins over everything — neutral, no affordance', () {
      expect(
        derive(activeAccess: false, todayLogs: [log()]),
        isA<RowAccessUnavailable>(),
      );
    });

    test('submitting locks the row from the moment of the tap', () {
      expect(derive(submitting: true), isA<RowSubmitting>());
    });

    test('resolvable books → Ready with the union preview', () {
      final state =
          derive(titles: const ['The Bad Guys', 'Zog']) as RowReady;
      expect(state.bookTitles, ['The Bad Guys', 'Zog']);
      expect(state.usualMinutes, 15);
    });

    test('no resolvable book → Choose book, never a fabricated title', () {
      expect(derive(titles: const []), isA<RowNeedsBook>());
    });

    test('school disabled quick logging → no dangling button state', () {
      expect(
        derive(quickLoggingEnabled: false),
        isA<RowQuickLogDisabled>(),
      );
    });

    test('my just-created session → immediate-undo state targeting that id',
        () {
      final state = derive(
        todayLogs: [log(id: 'log_9')],
        justCreatedLogId: 'log_9',
      ) as RowJustCreatedByMe;
      expect(state.log.id, 'log_9');
    });

    test("someone else's session → view-only, no Undo anywhere", () {
      expect(
        derive(todayLogs: [log(parentId: otherUid)]),
        isA<RowLoggedByOther>(),
      );
    });

    test('my own EARLIER session (restart/other device) → durable review, '
        'not immediate undo', () {
      final state = derive(todayLogs: [log()]) as RowMultiSessions;
      expect(state.sessions, 1);
      expect(state.totalMinutes, 15);
    });

    test('two sessions aggregate and NEVER expose Undo', () {
      final state = derive(
        todayLogs: [log(id: 'a'), log(id: 'b', parentId: otherUid, minutes: 20)],
        justCreatedLogId: 'a',
      );
      expect(state, isA<RowMultiSessions>());
      expect((state as RowMultiSessions).totalMinutes, 35);
    });

    test('classroom reading shows but does not satisfy the home slot', () {
      final state = derive(
        todayLogs: [log(context: 'classroom', minutes: 10)],
      ) as RowClassroomOnly;
      expect(state.classroomMinutes, 10);
      expect(state.inner, isA<RowReady>(),
          reason: 'quick log stays available');
    });

    test('a home session outranks classroom display', () {
      expect(
        derive(todayLogs: [
          log(context: 'classroom'),
          log(id: 'h', parentId: otherUid),
        ]),
        isA<RowLoggedByOther>(),
      );
    });

    test('a saved-on-this-phone session shows pending, not Ready', () {
      final state = deriveChildLogRowState(
        student: student(),
        todayLogs: const [],
        resolvedBookTitles: const ['The Bad Guys'],
        usualMinutes: 15,
        quickLoggingEnabled: true,
        submitting: false,
        myUid: myUid,
        pendingLogs: [log(id: 'queued')],
      );
      expect(state, isA<RowOfflinePending>());
      expect((state as RowOfflinePending).pending.id, 'queued');
    });

    test('a parked slot conflict outranks everything except access', () {
      final state = deriveChildLogRowState(
        student: student(),
        todayLogs: [log(parentId: otherUid)],
        resolvedBookTitles: const ['The Bad Guys'],
        usualMinutes: 15,
        quickLoggingEnabled: true,
        submitting: false,
        myUid: myUid,
        pendingLogs: [log(id: 'queued')],
        conflictLogId: 'queued',
      );
      expect(state, isA<RowConflict>());
      expect((state as RowConflict).pendingLogId, 'queued');
    });

    test('a server-confirmed home session outranks a stale pending copy', () {
      final state = deriveChildLogRowState(
        student: student(),
        todayLogs: [log(parentId: otherUid)],
        resolvedBookTitles: const ['The Bad Guys'],
        usualMinutes: 15,
        quickLoggingEnabled: true,
        submitting: false,
        myUid: myUid,
        pendingLogs: [log(id: 'queued')],
      );
      expect(state, isA<RowLoggedByOther>());
    });
  });

  Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: Material(child: child)),
        ),
      );

  group('ChildLogRow widget', () {
    testWidgets('Ready renders a LABELLED button and no check-circle',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(ChildLogRow(
        student: student(),
        state: const RowReady(
            bookTitles: ['The Bad Guys'], usualMinutes: 15),
        onOpenDetail: () {},
        onQuickLog: () => tapped++,
      )));

      expect(find.text('Log 15 min'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.text('The Bad Guys · usual 15 min'), findsOneWidget);

      await tester.tap(find.text('Log 15 min'));
      expect(tapped, 1);
    });

    testWidgets('Submitting is inert — a second tap does nothing',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(ChildLogRow(
        student: student(),
        state: const RowSubmitting(),
        onOpenDetail: () => tapped++,
        onQuickLog: () => tapped++,
      )));

      expect(find.text('Logging…'), findsWidgets);
      await tester.tap(find.text('Logging…').last, warnIfMissed: false);
      await tester.tap(find.text('Lincoln'), warnIfMissed: false);
      expect(tapped, lessThanOrEqualTo(1),
          reason: 'the trailing action is disabled while submitting');
    });

    testWidgets(
        'JustCreatedByMe: static chip where the button was; Undo lives on '
        'the status line, not under the same finger', (tester) async {
      var undo = 0;
      var quick = 0;
      await tester.pumpWidget(host(ChildLogRow(
        student: student(),
        state: RowJustCreatedByMe(log: log()),
        onOpenDetail: () {},
        onQuickLog: () => quick++,
        onUndo: () => undo++,
      )));

      // The trailing slot is now a NON-interactive summary chip.
      expect(find.text('15 min logged'), findsOneWidget);
      await tester.tap(find.text('15 min logged'), warnIfMissed: false);
      expect(quick, 0, reason: 'a rapid second tap on the old spot is inert');

      // Undo is a separate control elsewhere in the row.
      final undoFinder = find.text('Undo my quick log');
      expect(undoFinder, findsOneWidget);
      final undoRect = tester.getRect(undoFinder);
      final chipRect = tester.getRect(find.text('15 min logged'));
      expect(undoRect.overlaps(chipRect), isFalse,
          reason: 'undo must not occupy the former button rect');

      await tester.tap(undoFinder);
      expect(undo, 1);
    });

    testWidgets('logging one child never moves or resizes siblings',
        (tester) async {
      Widget threeRows(ChildLogRowState middle) => host(Column(
            children: [
              ChildLogRow(
                key: const ValueKey('c1'),
                student: student(id: 'c1'),
                state: const RowReady(
                    bookTitles: ['Zog'], usualMinutes: 15),
                onOpenDetail: () {},
              ),
              ChildLogRow(
                key: const ValueKey('c2'),
                student: student(id: 'c2'),
                state: middle,
                onOpenDetail: () {},
              ),
              ChildLogRow(
                key: const ValueKey('c3'),
                student: student(id: 'c3'),
                state: const RowReady(
                    bookTitles: ['Dog Man'], usualMinutes: 20),
                onOpenDetail: () {},
              ),
            ],
          ));

      await tester.pumpWidget(threeRows(
          const RowReady(bookTitles: ['The Bad Guys'], usualMinutes: 15)));
      final beforeTop = tester.getRect(find.byKey(const ValueKey('c1')));
      final beforeBottom = tester.getRect(find.byKey(const ValueKey('c3')));

      // The middle child logs — its row swaps to the logged state.
      await tester.pumpWidget(threeRows(RowJustCreatedByMe(log: log())));
      await tester.pump();

      expect(tester.getRect(find.byKey(const ValueKey('c1'))), beforeTop,
          reason: 'untouched rows must not move or resize');
      expect(tester.getRect(find.byKey(const ValueKey('c3'))), beforeBottom,
          reason: 'untouched rows must not move or resize');
    });

    testWidgets('operable at 2.0 text scale — nothing hidden, no overflow',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(
        ChildLogRow(
          student: student(),
          state: const RowReady(
              bookTitles: ['The Bad Guys'], usualMinutes: 15),
          onOpenDetail: () {},
          onQuickLog: () => tapped++,
        ),
        textScale: 2.0,
      ));

      expect(tester.takeException(), isNull, reason: 'no overflow errors');
      expect(find.text('Lincoln'), findsOneWidget);
      expect(find.text('Log 15 min'), findsOneWidget);
      await tester.tap(find.text('Log 15 min'));
      expect(tapped, 1);
    });

    testWidgets('VoiceOver: separate row and action semantics with full '
        'labels', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ChildLogRow(
        student: student(),
        state: const RowReady(
            bookTitles: ['The Bad Guys'], usualMinutes: 15),
        onOpenDetail: () {},
        onQuickLog: () {},
      )));

      expect(
        find.bySemanticsLabel(
            'Quick log 15 minutes for Lincoln, The Bad Guys.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('access unavailable: neutral text, no button, inert body',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(host(ChildLogRow(
        student: student(activeAccess: false),
        state: const RowAccessUnavailable(),
        onOpenDetail: () => opened++,
        onQuickLog: () {},
      )));

      expect(
        find.text('Logging is paused — contact your school office'),
        findsOneWidget,
      );
      expect(find.text('Log 15 min'), findsNothing);
      await tester.tap(find.text('Lincoln'), warnIfMissed: false);
      expect(opened, 0);
    });

    testWidgets('minimum 44pt target on the trailing action', (tester) async {
      await tester.pumpWidget(host(ChildLogRow(
        student: student(),
        state: const RowReady(
            bookTitles: ['The Bad Guys'], usualMinutes: 15),
        onOpenDetail: () {},
        onQuickLog: () {},
      )));

      final size = tester.getSize(
        find
            .ancestor(
              of: find.text('Log 15 min'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });
  });
}
