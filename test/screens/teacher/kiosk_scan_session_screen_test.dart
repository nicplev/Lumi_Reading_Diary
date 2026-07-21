import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/class_model.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/screens/teacher/kiosk/kiosk_scan_session_screen.dart';
import 'package:lumi_reading_tracker/services/bluetooth_settings_service.dart';
import 'package:lumi_reading_tracker/services/hid_scanner_connection_service.dart';
import 'package:lumi_reading_tracker/services/isbn_assignment_service.dart';

void main() {
  const firstIsbn = '9780143127741';
  const secondIsbn = '9780061120084';

  test('camera scan window is a centered 260×160 rectangle', () {
    expect(
      kioskCameraScanWindowFor(const Size(400, 700)),
      const Rect.fromLTWH(70, 270, 260, 160),
    );
  });

  testWidgets('rapid wedge scans queue and show the waiting count',
      (tester) async {
    final service = _QueueTestIsbnService(gateFirstLookup: true);
    final hid = _FakeHidScannerConnectionService(true);
    addTearDown(hid.dispose);
    await _pumpScreen(tester, service: service, hid: hid);

    await _scanWithWedge(tester, firstIsbn);
    await tester.pump();
    await _scanWithWedge(tester, secondIsbn);
    await tester.pump();

    expect(service.lookupCodes, <String>[firstIsbn]);
    expect(find.text('1 more waiting'), findsOneWidget);
    expect(find.text('Saving books…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Saving books…'),
          )
          .onPressed,
      isNull,
    );

    service.releaseFirstLookup();
    await tester.pumpAndSettle();

    expect(service.lookupCodes, <String>[firstIsbn, secondIsbn]);
    expect(service.assignedIsbns, <String>[firstIsbn, secondIsbn]);
    expect(find.text('Book $firstIsbn'), findsOneWidget);
    expect(find.text('Book $secondIsbn'), findsOneWidget);
    expect(find.text('1 more waiting'), findsNothing);
    expect(find.text("I'm done!"), findsOneWidget);
  });

  testWidgets('duplicate arriving during lookup is rejected once',
      (tester) async {
    final service = _QueueTestIsbnService(gateFirstLookup: true);
    final hid = _FakeHidScannerConnectionService(true);
    addTearDown(hid.dispose);
    await _pumpScreen(tester, service: service, hid: hid);

    await _scanWithWedge(tester, firstIsbn);
    await tester.pump();
    await _scanWithWedge(tester, firstIsbn);
    await tester.pump();

    expect(find.text('Already scanned just now.'), findsOneWidget);
    expect(service.lookupCodes, <String>[firstIsbn]);

    service.releaseFirstLookup();
    await tester.pumpAndSettle();

    expect(service.assignedIsbns, <String>[firstIsbn]);
    expect(find.text('Book $firstIsbn'), findsOneWidget);
  });

  testWidgets('idle timeout does not pop while the queue is pending',
      (tester) async {
    final service = _QueueTestIsbnService(gateFirstLookup: true);
    final hid = _FakeHidScannerConnectionService(true);
    addTearDown(hid.dispose);
    await _pumpScreen(tester, service: service, hid: hid);

    await _scanWithWedge(tester, firstIsbn);
    await _scanWithWedge(tester, secondIsbn);
    await tester.pump(const Duration(seconds: 31));

    expect(find.text('Hi Ava! Scan your books'), findsOneWidget);
    expect(find.text('1 more waiting'), findsOneWidget);

    service.releaseFirstLookup();
    await tester.pumpAndSettle();
    expect(service.assignedIsbns, <String>[firstIsbn, secondIsbn]);
  });

  testWidgets('native HID state hides and re-shows connection help',
      (tester) async {
    final service = _QueueTestIsbnService(gateFirstLookup: false);
    final hid = _FakeHidScannerConnectionService(true);
    addTearDown(hid.dispose);
    await _pumpScreen(tester, service: service, hid: hid);

    expect(find.text('Connect your scanner'), findsNothing);
    expect(find.text('Scan book barcodes'), findsOneWidget);

    await _scanWithWedge(tester, firstIsbn);
    await tester.pumpAndSettle();
    expect(find.text('Book $firstIsbn'), findsOneWidget);

    hid.emit(false);
    await tester.pump();
    expect(find.text('Connect your scanner'), findsOneWidget);
    expect(find.text('Book $firstIsbn'), findsOneWidget);

    hid.emit(true);
    await tester.pumpAndSettle();
    expect(find.text('Connect your scanner'), findsNothing);
    expect(find.text('Scan book barcodes'), findsOneWidget);
  });

  testWidgets('unknown HID state retains the original empty-session heuristic',
      (tester) async {
    final service = _QueueTestIsbnService(gateFirstLookup: false);
    final hid = _FakeHidScannerConnectionService(null);
    addTearDown(hid.dispose);
    await _pumpScreen(tester, service: service, hid: hid);

    expect(find.text('Connect your scanner'), findsOneWidget);
  });

  testWidgets('Android opens the native Bluetooth device settings directly',
      (tester) async {
    final service = _QueueTestIsbnService(gateFirstLookup: false);
    final hid = _FakeHidScannerConnectionService(false);
    final bluetooth = _FakeBluetoothSettingsController();
    addTearDown(hid.dispose);
    await _pumpScreen(
      tester,
      service: service,
      hid: hid,
      bluetooth: bluetooth,
      platform: TargetPlatform.android,
    );

    await tester.tap(find.text('Open Bluetooth settings'));
    await tester.pumpAndSettle();

    expect(bluetooth.openCalls, 1);
    expect(find.text('Open Bluetooth on this device'), findsNothing);
  });

  testWidgets('iOS explains the final Bluetooth tap before opening Settings',
      (tester) async {
    final service = _QueueTestIsbnService(gateFirstLookup: false);
    final hid = _FakeHidScannerConnectionService(false);
    final bluetooth = _FakeBluetoothSettingsController(
      destination: BluetoothSettingsDestination.systemSettings,
    );
    addTearDown(hid.dispose);
    await _pumpScreen(
      tester,
      service: service,
      hid: hid,
      bluetooth: bluetooth,
      platform: TargetPlatform.iOS,
    );

    await tester.tap(find.text('Open Bluetooth settings'));
    await tester.pumpAndSettle();

    expect(find.text('Open Bluetooth on this device'), findsOneWidget);
    expect(find.textContaining('tap Bluetooth'), findsOneWidget);
    expect(bluetooth.openCalls, 0);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(bluetooth.openCalls, 1);
    expect(find.text('Open Bluetooth on this device'), findsNothing);
  });
}

class _QueueTestIsbnService extends IsbnAssignmentService {
  _QueueTestIsbnService({required this.gateFirstLookup})
      : super(firestore: FakeFirebaseFirestore());

  final bool gateFirstLookup;
  final Completer<void> _firstLookupGate = Completer<void>();
  final List<String> lookupCodes = <String>[];
  final List<String> assignedIsbns = <String>[];

  void releaseFirstLookup() {
    if (!_firstLookupGate.isCompleted) _firstLookupGate.complete();
  }

  @override
  Future<IsbnResolutionResult> resolveIsbn({
    required String rawCode,
    required String schoolId,
    required String teacherId,
  }) async {
    lookupCodes.add(rawCode);
    if (gateFirstLookup && lookupCodes.length == 1) {
      await _firstLookupGate.future;
    }
    return IsbnResolved(
      ScannedIsbnBook(
        isbn: rawCode,
        title: 'Book $rawCode',
        bookId: 'isbn_$rawCode',
        resolvedFromCatalog: true,
      ),
    );
  }

  @override
  Future<ScanClassificationResult> classifyScan({
    required String schoolId,
    required String studentId,
    required String isbn,
    String? bookId,
    DateTime? referenceDate,
  }) async {
    return const ScanClassificationResult(
      classification: ScanClassification.newBook,
    );
  }

  @override
  Future<IsbnAssignmentResult> assignResolvedBooks({
    required String schoolId,
    required String classId,
    required String studentId,
    required String teacherId,
    required List<ScannedIsbnBook> books,
    int targetMinutes = 20,
    String? sessionId,
    DateTime? targetDate,
    Set<String> renewedIsbns = const <String>{},
  }) async {
    assignedIsbns.addAll(books.map((book) => book.isbn));
    return IsbnAssignmentResult(
      allocationId: 'allocation_1',
      processedBooks: books,
      newlyAssignedBooks: books,
      duplicateIsbns: const <String>[],
      invalidCodes: const <String>[],
      totalAssignedBooks: assignedIsbns.length,
    );
  }
}

class _FakeHidScannerConnectionService extends HidScannerConnectionService {
  _FakeHidScannerConnectionService(this.initialState);

  final bool? initialState;
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast(sync: true);

  @override
  Future<bool?> isConnected() async => initialState;

  @override
  Stream<bool> connectionChanges() => _controller.stream;

  void emit(bool connected) => _controller.add(connected);

  Future<void> dispose() => _controller.close();
}

class _FakeBluetoothSettingsController implements BluetoothSettingsController {
  _FakeBluetoothSettingsController({
    this.destination = BluetoothSettingsDestination.bluetooth,
  });

  final BluetoothSettingsDestination destination;
  int openCalls = 0;

  @override
  Future<BluetoothSettingsDestination> openBluetoothSettings() async {
    openCalls += 1;
    return destination;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required IsbnAssignmentService service,
  required HidScannerConnectionService hid,
  BluetoothSettingsController? bluetooth,
  TargetPlatform? platform,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final teacher = UserModel(
    id: 'teacher_1',
    email: 'teacher@example.com',
    fullName: 'Ms Lumi',
    role: UserRole.teacher,
    schoolId: 'school_1',
    createdAt: DateTime(2026, 1, 1),
  );
  final classModel = ClassModel(
    id: 'class_1',
    schoolId: 'school_1',
    name: 'Class 3B',
    teacherId: teacher.id,
    studentIds: const <String>['student_1'],
    createdAt: DateTime(2026, 1, 1),
    createdBy: teacher.id,
  );
  final student = StudentModel(
    id: 'student_1',
    firstName: 'Ava',
    lastName: 'Patel',
    schoolId: 'school_1',
    classId: 'class_1',
    createdAt: DateTime(2026, 1, 1),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: platform == null ? null : ThemeData(platform: platform),
      home: KioskScanSessionScreen(
        teacher: teacher,
        classModel: classModel,
        student: student,
        isbnAssignmentService: service,
        hidScannerConnectionService: hid,
        bluetoothSettingsController: bluetooth,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _scanWithWedge(WidgetTester tester, String code) async {
  expect(IsbnAssignmentService.normalizeIsbn(code), code);
  const keys = <String, LogicalKeyboardKey>{
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };
  for (final character in code.split('')) {
    final key = keys[character]!;
    await tester.sendKeyDownEvent(key, character: character);
    await tester.sendKeyUpEvent(key);
  }
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
}
