import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/exceptions/linking_exceptions.dart';
import 'package:lumi_reading_tracker/core/services/impersonation_service.dart';
import 'package:lumi_reading_tracker/services/parent_linking_service.dart';
import 'package:mockito/mockito.dart';

/// No-op stand-in for [ImpersonationService] so [assertWritable] short-
/// circuits in unit tests. The production `ImpersonationService.instance`
/// getter eagerly accesses `FirebaseAuth.instance`, which throws "no Firebase
/// app" when Firebase isn't initialized in a unit-test isolate.
class _NoopImpersonationService extends Mock implements ImpersonationService {
  @override
  bool get isActive => false;

  @override
  void dispose() {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Captures every invocation made through the injected
/// [HttpsCallableInvoker] so tests can assert call args, and replays a
/// queue of canned responses (data or exceptions) one per call. This is the
/// substitute for mocking FirebaseFunctions/HttpsCallable, both of which
/// have concrete bodies that fight with mockito.
class _RecordingInvoker {
  final Map<String, List<Map<String, dynamic>>> calls = {};
  final Map<String, List<Object>> _responses = {};

  void queueSuccess(String name, Object? data) {
    _responses.putIfAbsent(name, () => <Object>[]).add(_Success(data));
  }

  void queueFailure(String name, FirebaseFunctionsException error) {
    _responses.putIfAbsent(name, () => <Object>[]).add(error);
  }

  HttpsCallableInvoker get invoker => (name, args) async {
        calls.putIfAbsent(name, () => []).add(args);
        final queue = _responses[name];
        if (queue == null || queue.isEmpty) {
          throw StateError('No queued response for callable "$name" (call '
              '#${calls[name]!.length}).');
        }
        final next = queue.removeAt(0);
        if (next is FirebaseFunctionsException) throw next;
        return (next as _Success).data;
      };
}

class _Success {
  _Success(this.data);
  final Object? data;
}

void main() {
  setUpAll(() {
    ImpersonationService.debugSetInstance(_NoopImpersonationService());
  });

  group('ParentLinkingService', () {
    late FakeFirebaseFirestore firestore;
    late _RecordingInvoker invoker;
    late ParentLinkingService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      invoker = _RecordingInvoker();
      service = ParentLinkingService(
        firestore: firestore,
        callableInvoker: invoker.invoker,
      );
    });

    void stubLinkSuccess({
      String studentId = 'student_1',
      String schoolId = 'school_1',
      List<String> linkedChildren = const ['student_1'],
    }) {
      invoker.queueSuccess('linkParentToStudent', <String, dynamic>{
        'studentId': studentId,
        'schoolId': schoolId,
        'linkedChildren': linkedChildren,
      });
    }

    void stubLinkFailure({
      required String code,
      String? kind,
      String? reason,
      String message = 'simulated',
    }) {
      invoker.queueFailure(
        'linkParentToStudent',
        FirebaseFunctionsException(
          code: code,
          message: message,
          details: <String, Object?>{
            if (kind != null) 'kind': kind,
            if (reason != null) 'reason': reason,
          },
        ),
      );
    }

    void stubUnlinkSuccess({
      String studentId = 'student_1',
      String schoolId = 'school_1',
      String parentUserId = 'parent_1',
    }) {
      invoker.queueSuccess('unlinkParentFromStudent', <String, dynamic>{
        'studentId': studentId,
        'schoolId': schoolId,
        'removedParentUid': parentUserId,
      });
    }

    void stubUnlinkFailure({
      required String code,
      String? kind,
      String message = 'simulated',
    }) {
      invoker.queueFailure(
        'unlinkParentFromStudent',
        FirebaseFunctionsException(
          code: code,
          message: message,
          details: <String, Object?>{
            if (kind != null) 'kind': kind,
          },
        ),
      );
    }

    Future<void> seedStudent({
      String schoolId = 'school_1',
      String studentId = 'student_1',
      String firstName = 'Sam',
      String lastName = 'Booker',
      List<String> parentIds = const [],
    }) async {
      await firestore.collection('schools').doc(schoolId).set({'name': 'Lumi'});
      await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(studentId)
          .set({
        'firstName': firstName,
        'lastName': lastName,
        'studentId': 'S-100',
        'classId': 'class_1',
        'schoolId': schoolId,
        'parentIds': parentIds,
        'createdAt': Timestamp.now(),
      });
    }

    Future<void> seedLinkCode({
      String docId = 'code_1',
      String code = 'QWER5678',
      String status = 'active',
      String studentId = 'student_1',
      String schoolId = 'school_1',
      Duration expiresIn = const Duration(days: 30),
      String? usedBy,
    }) async {
      await firestore.collection('studentLinkCodes').doc(docId).set({
        'studentId': studentId,
        'schoolId': schoolId,
        'code': code,
        'status': status,
        'createdBy': 'admin_1',
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(expiresIn)),
        if (usedBy != null) 'usedBy': usedBy,
        if (usedBy != null) 'usedAt': Timestamp.now(),
      });
    }

    // ── createLinkCode ──

    group('createLinkCode', () {
      test('creates an active code with student metadata', () async {
        await seedStudent();

        final code = await service.createLinkCode(
          studentId: 'student_1',
          schoolId: 'school_1',
          createdBy: 'admin_1',
        );

        expect(code.code, hasLength(8));
        expect(code.status.name, 'active');
        expect(code.studentId, 'student_1');
        expect(code.schoolId, 'school_1');
        expect(code.metadata?['studentFirstName'], 'Sam');
        expect(code.metadata?['studentLastName'], 'Booker');
        expect(code.metadata?['studentFullName'], 'Sam Booker');
      });

      test('revokes previous active code for student', () async {
        await seedStudent();

        final first = await service.createLinkCode(
          studentId: 'student_1',
          schoolId: 'school_1',
          createdBy: 'admin_1',
        );

        final second = await service.createLinkCode(
          studentId: 'student_1',
          schoolId: 'school_1',
          createdBy: 'admin_1',
        );

        final firstDoc =
            await firestore.collection('studentLinkCodes').doc(first.id).get();
        final secondDoc =
            await firestore.collection('studentLinkCodes').doc(second.id).get();

        expect(firstDoc.data()!['status'], equals('revoked'));
        expect(secondDoc.data()!['status'], equals('active'));
      });

      test('uses custom validity days', () async {
        await seedStudent();

        final code = await service.createLinkCode(
          studentId: 'student_1',
          schoolId: 'school_1',
          createdBy: 'admin_1',
          validityDays: 7,
        );

        // Expires within ~7 days
        final diff = code.expiresAt.difference(DateTime.now()).inDays;
        expect(diff, inInclusiveRange(6, 7));
      });

      test('refuses to issue a code for a nonexistent student', () async {
        // School exists but student does not. createLinkCode must refuse —
        // an orphan code would strand a parent at "student-missing" inside
        // linkParentToStudent with no recovery path.
        await firestore
            .collection('schools')
            .doc('school_1')
            .set({'name': 'Lumi'});

        await expectLater(
          () => service.createLinkCode(
            studentId: 'nonexistent_student',
            schoolId: 'school_1',
            createdBy: 'admin_1',
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    // ── generateBulkCodes ──

    group('generateBulkCodes', () {
      test('creates codes for multiple students', () async {
        await seedStudent(studentId: 'student_1');
        await firestore
            .collection('schools')
            .doc('school_1')
            .collection('students')
            .doc('student_2')
            .set({
          'firstName': 'Alex',
          'lastName': 'Reader',
          'studentId': 'S-101',
          'classId': 'class_1',
          'schoolId': 'school_1',
          'parentIds': [],
          'createdAt': Timestamp.now(),
        });

        final codes = await service.generateBulkCodes(
          studentIds: ['student_1', 'student_2'],
          schoolId: 'school_1',
          createdBy: 'admin_1',
        );

        expect(codes.length, 2);
        expect(codes['student_1'], isNotNull);
        expect(codes['student_2'], isNotNull);
        expect(codes['student_1']!.code, isNot(codes['student_2']!.code));
      });

      test('deduplicates student IDs', () async {
        await seedStudent();

        final codes = await service.generateBulkCodes(
          studentIds: ['student_1', 'student_1', 'student_1'],
          schoolId: 'school_1',
          createdBy: 'admin_1',
        );

        expect(codes.length, 1);
        expect(codes['student_1'], isNotNull);
      });
    });

    // ── verifyCode ──

    group('verifyCode', () {
      // verifyCode now forwards to the verifyStudentLinkCode callable (exact
      // code lookup) rather than querying studentLinkCodes directly. These
      // tests cover the client wrapper: it upper-cases the code, forwards it,
      // builds the model from the payload, and maps the server's typed errors.
      Map<String, dynamic> verifyPayload({
        String id = 'code_1',
        String code = 'QWER5678',
        String studentId = 'student_1',
        String schoolId = 'school_1',
        Map<String, dynamic>? metadata,
      }) =>
          <String, dynamic>{
            'ok': true,
            'id': id,
            'code': code,
            'studentId': studentId,
            'schoolId': schoolId,
            'expiresAt':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'metadata':
                metadata ?? <String, dynamic>{'studentFullName': 'Sam Booker'},
          };

      void stubVerifyFailure(
          {required String code, String? kind, String? reason}) {
        invoker.queueFailure(
          'verifyStudentLinkCode',
          FirebaseFunctionsException(
            code: code,
            message: 'simulated',
            details: <String, Object?>{
              if (kind != null) 'kind': kind,
              if (reason != null) 'reason': reason,
            },
          ),
        );
      }

      test('returns valid active code from the callable', () async {
        invoker.queueSuccess('verifyStudentLinkCode', verifyPayload());

        final verified = await service.verifyCode('QWER5678');
        expect(verified.code, 'QWER5678');
        expect(verified.status.name, 'active');
        expect(verified.studentId, 'student_1');
      });

      test('upper-cases the code before forwarding', () async {
        invoker.queueSuccess(
            'verifyStudentLinkCode', verifyPayload(code: 'ABCD1234'));

        await service.verifyCode('abcd1234');
        expect(
            invoker.calls['verifyStudentLinkCode']!.single['code'], 'ABCD1234');
      });

      test('maps failed-precondition/invalid-code to InvalidCodeException',
          () async {
        stubVerifyFailure(code: 'failed-precondition', kind: 'invalid-code');
        await expectLater(
          () => service.verifyCode('DOESNTEXIST'),
          throwsA(isA<InvalidCodeException>()),
        );
      });

      test('maps failed-precondition/code-used to CodeAlreadyUsedException',
          () async {
        stubVerifyFailure(code: 'failed-precondition', kind: 'code-used');
        await expectLater(
          () => service.verifyCode('USED0001'),
          throwsA(isA<CodeAlreadyUsedException>()),
        );
      });

      test('maps failed-precondition/code-revoked to CodeRevokedException',
          () async {
        stubVerifyFailure(
            code: 'failed-precondition',
            kind: 'code-revoked',
            reason: 'Student transferred');
        await expectLater(
          () => service.verifyCode('REVK0001'),
          throwsA(isA<CodeRevokedException>()),
        );
      });

      test('maps failed-precondition/code-expired to CodeExpiredException',
          () async {
        stubVerifyFailure(code: 'failed-precondition', kind: 'code-expired');
        await expectLater(
          () => service.verifyCode('EXPD0001'),
          throwsA(isA<CodeExpiredException>()),
        );
      });

      test('returns the id carried in the callable payload', () async {
        invoker.queueSuccess('verifyStudentLinkCode',
            verifyPayload(id: 'active_latest', code: 'ABCD2345'));

        final verified = await service.verifyCode('ABCD2345');
        expect(verified.id, equals('active_latest'));
        expect(verified.status.name, equals('active'));
      });
    });

    // ── createCoParentInviteCode ──

    group('createCoParentInviteCode', () {
      test('forwards schoolId/studentId/validityDays to the callable',
          () async {
        invoker.queueSuccess('createCoParentInvite', <String, dynamic>{
          'ok': true,
          'id': 'invite_1',
          'code': 'CPAR5678',
          'studentId': 'student_1',
          'schoolId': 'school_1',
          'expiresAt':
              DateTime.now().add(const Duration(days: 365)).toIso8601String(),
          'metadata': <String, dynamic>{'studentFullName': 'Sam Booker'},
          'intendedFor': 'co_parent_invite',
        });

        final code = await service.createCoParentInviteCode(
          studentId: 'student_1',
          schoolId: 'school_1',
          parentUserId: 'parent_1',
        );

        expect(code.code, 'CPAR5678');
        expect(code.isCoParentInvite, isTrue);
        final sent = invoker.calls['createCoParentInvite']!.single;
        expect(sent['schoolId'], 'school_1');
        expect(sent['studentId'], 'student_1');
        expect(sent['validityDays'], 7);
      });

      test('maps permission-denied to TransactionFailedException', () async {
        invoker.queueFailure(
          'createCoParentInvite',
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'You are not linked to this student.',
          ),
        );

        await expectLater(
          () => service.createCoParentInviteCode(
            studentId: 'student_1',
            schoolId: 'school_1',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<TransactionFailedException>()),
        );
      });
    });

    // ── linkParentToStudent ──
    //
    // Behaviour now lives in the linkParentToStudent Cloud Function (see
    // functions/src/parent_linking.ts). These tests cover the client wrapper:
    // it normalises the code, forwards through httpsCallable, and maps the
    // server's HttpsError taxonomy back to the local LinkingException types
    // the UI catches.

    group('linkParentToStudent', () {
      test('forwards uppercased, trimmed code and clientInfo to the callable',
          () async {
        stubLinkSuccess();

        final linked = await service.linkParentToStudent(
          code: '  qwer5678  ',
          parentUserId: 'parent_1',
          parentEmail: 'parent@school.test',
        );

        expect(linked, isTrue);
        final captured = invoker.calls['linkParentToStudent']!.single;
        expect(captured['code'], 'QWER5678');
        expect(captured['clientInfo'], isA<Map<String, dynamic>>());
      });

      test('returns true on a successful callable response', () async {
        stubLinkSuccess();
        final linked = await service.linkParentToStudent(
          code: 'QWER5678',
          parentUserId: 'parent_1',
          parentEmail: null,
        );
        expect(linked, isTrue);
      });

      test('maps failed-precondition/invalid-code to InvalidCodeException',
          () async {
        stubLinkFailure(code: 'failed-precondition', kind: 'invalid-code');
        await expectLater(
          () => service.linkParentToStudent(
            code: 'NOPE0000',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<InvalidCodeException>()),
        );
      });

      test('maps failed-precondition/code-used to CodeAlreadyUsedException',
          () async {
        stubLinkFailure(code: 'failed-precondition', kind: 'code-used');
        await expectLater(
          () => service.linkParentToStudent(
            code: 'USED0000',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<CodeAlreadyUsedException>()),
        );
      });

      test(
          'maps failed-precondition/code-revoked to CodeRevokedException '
          'with reason carried through', () async {
        stubLinkFailure(
          code: 'failed-precondition',
          kind: 'code-revoked',
          reason: 'Student transferred',
        );
        try {
          await service.linkParentToStudent(
            code: 'REVK0000',
            parentUserId: 'parent_1',
          );
          fail('expected CodeRevokedException');
        } on CodeRevokedException catch (e) {
          expect(e.userMessage, contains('Student transferred'));
        }
      });

      test('maps failed-precondition/code-expired to CodeExpiredException',
          () async {
        stubLinkFailure(code: 'failed-precondition', kind: 'code-expired');
        await expectLater(
          () => service.linkParentToStudent(
            code: 'EXPD0000',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<CodeExpiredException>()),
        );
      });

      test(
          'maps failed-precondition/parent-doc-missing to '
          'ParentDocumentNotFoundException', () async {
        stubLinkFailure(
            code: 'failed-precondition', kind: 'parent-doc-missing');
        await expectLater(
          () => service.linkParentToStudent(
            code: 'QWER5678',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<ParentDocumentNotFoundException>()),
        );
      });

      test('maps already-exists/already-linked to AlreadyLinkedException',
          () async {
        stubLinkFailure(code: 'already-exists', kind: 'already-linked');
        await expectLater(
          () => service.linkParentToStudent(
            code: 'QWER5678',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<AlreadyLinkedException>()),
        );
      });

      test('maps not-found/student-missing to StudentNotFoundException',
          () async {
        stubLinkFailure(code: 'not-found', kind: 'student-missing');
        await expectLater(
          () => service.linkParentToStudent(
            code: 'QWER5678',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<StudentNotFoundException>()),
        );
      });

      test('maps resource-exhausted to TransactionFailedException', () async {
        stubLinkFailure(code: 'resource-exhausted');
        await expectLater(
          () => service.linkParentToStudent(
            code: 'QWER5678',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<TransactionFailedException>()),
        );
      });

      test('retries once on unavailable, then succeeds', () async {
        // First call: unavailable. Second call: success.
        stubLinkFailure(code: 'unavailable');
        stubLinkSuccess();

        final linked = await service.linkParentToStudent(
          code: 'QWER5678',
          parentUserId: 'parent_1',
        );

        expect(linked, isTrue);
        expect(invoker.calls['linkParentToStudent']!.length, 2);
      });

      test(
          'surfaces NetworkUnavailableException after retry also fails with '
          'unavailable', () async {
        stubLinkFailure(code: 'unavailable');
        stubLinkFailure(code: 'unavailable');

        await expectLater(
          () => service.linkParentToStudent(
            code: 'QWER5678',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<NetworkUnavailableException>()),
        );
      });
    });

    // ── revokeCode ──

    group('revokeCode', () {
      test('marks code as revoked with reason', () async {
        await seedLinkCode(docId: 'code_to_revoke');

        await service.revokeCode(
          codeId: 'code_to_revoke',
          revokedBy: 'admin_1',
          reason: 'Student left school',
        );

        final doc = await firestore
            .collection('studentLinkCodes')
            .doc('code_to_revoke')
            .get();
        expect(doc.data()!['status'], 'revoked');
        expect(doc.data()!['revokedBy'], 'admin_1');
        expect(doc.data()!['revokeReason'], 'Student left school');
      });
    });

    // ── getActiveCodeForStudent ──

    group('getActiveCodeForStudent', () {
      test('returns active code when one exists', () async {
        await seedLinkCode(studentId: 'student_1');

        final code = await service.getActiveCodeForStudent('student_1');
        expect(code, isNotNull);
        expect(code!.studentId, 'student_1');
        expect(code.status.name, 'active');
      });

      test('returns null when no active code exists', () async {
        final code = await service.getActiveCodeForStudent('no_codes_student');
        expect(code, isNull);
      });

      test('ignores used codes', () async {
        await seedLinkCode(
          studentId: 'student_2',
          status: 'used',
          usedBy: 'parent_1',
        );

        final code = await service.getActiveCodeForStudent('student_2');
        expect(code, isNull);
      });
    });

    // ── getCodesForStudents ──

    group('getCodesForStudents', () {
      test('returns map of active codes for multiple students', () async {
        await seedLinkCode(
          docId: 'code_s1',
          code: 'CODE0001',
          studentId: 'student_1',
        );
        await seedLinkCode(
          docId: 'code_s2',
          code: 'CODE0002',
          studentId: 'student_2',
        );

        final codes =
            await service.getCodesForStudents(['student_1', 'student_2']);
        expect(codes['student_1'], isNotNull);
        expect(codes['student_2'], isNotNull);
      });

      test('returns null for students without active codes', () async {
        final codes = await service.getCodesForStudents(['no_code_student']);
        expect(codes['no_code_student'], isNull);
      });

      test('returns empty map for empty input', () async {
        final codes = await service.getCodesForStudents([]);
        expect(codes, isEmpty);
      });
    });

    // ── unlinkParentFromStudent ──
    //
    // Same shape as the link tests — the wrapper forwards args to the
    // callable and translates HttpsError codes back to LinkingException
    // types.

    group('unlinkParentFromStudent', () {
      test('forwards schoolId/studentId/parentUserId/reason to the callable',
          () async {
        stubUnlinkSuccess();

        await service.unlinkParentFromStudent(
          schoolId: 'school_1',
          studentId: 'student_1',
          parentUserId: 'parent_1',
          reason: 'Parent requested',
        );

        final captured = invoker.calls['unlinkParentFromStudent']!.single;
        expect(captured['schoolId'], 'school_1');
        expect(captured['studentId'], 'student_1');
        expect(captured['parentUserId'], 'parent_1');
        expect(captured['reason'], 'Parent requested');
      });

      test('omits reason when not provided', () async {
        stubUnlinkSuccess();

        await service.unlinkParentFromStudent(
          schoolId: 'school_1',
          studentId: 'student_1',
          parentUserId: 'parent_1',
        );

        final captured = invoker.calls['unlinkParentFromStudent']!.single;
        expect(captured.containsKey('reason'), isFalse);
      });

      test('maps not-found/student-missing to StudentNotFoundException',
          () async {
        stubUnlinkFailure(code: 'not-found', kind: 'student-missing');
        await expectLater(
          () => service.unlinkParentFromStudent(
            schoolId: 'school_1',
            studentId: 'nonexistent',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<StudentNotFoundException>()),
        );
      });

      test(
          'maps failed-precondition/parent-doc-missing to '
          'ParentDocumentNotFoundException', () async {
        stubUnlinkFailure(
            code: 'failed-precondition', kind: 'parent-doc-missing');
        await expectLater(
          () => service.unlinkParentFromStudent(
            schoolId: 'school_1',
            studentId: 'student_1',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<ParentDocumentNotFoundException>()),
        );
      });

      test('maps failed-precondition/not-linked to TransactionFailedException',
          () async {
        stubUnlinkFailure(code: 'failed-precondition', kind: 'not-linked');
        await expectLater(
          () => service.unlinkParentFromStudent(
            schoolId: 'school_1',
            studentId: 'student_1',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<TransactionFailedException>()),
        );
      });

      test('maps permission-denied to TransactionFailedException', () async {
        stubUnlinkFailure(code: 'permission-denied');
        await expectLater(
          () => service.unlinkParentFromStudent(
            schoolId: 'school_1',
            studentId: 'student_1',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<TransactionFailedException>()),
        );
      });
    });

    // ── Linking exception messages ──

    group('LinkingException user messages', () {
      test('InvalidCodeException has helpful user message', () {
        final e = InvalidCodeException();
        expect(e.userMessage, contains('invalid'));
        expect(e.userMessage, contains('teacher'));
      });

      test('CodeAlreadyUsedException has helpful user message', () {
        final e = CodeAlreadyUsedException();
        expect(e.userMessage, contains('already been used'));
      });

      test('AlreadyLinkedException has helpful user message', () {
        final e = AlreadyLinkedException();
        expect(e.userMessage, contains('already linked'));
      });

      test('CodeRevokedException includes reason when provided', () {
        final e = CodeRevokedException(reason: 'Student transferred');
        expect(e.userMessage, contains('Student transferred'));
      });

      test('CodeRevokedException works without reason', () {
        final e = CodeRevokedException();
        expect(e.userMessage, contains('revoked'));
      });

      test('CodeExpiredException has helpful user message', () {
        final e = CodeExpiredException();
        expect(e.userMessage, contains('expired'));
      });
    });
  });
}
