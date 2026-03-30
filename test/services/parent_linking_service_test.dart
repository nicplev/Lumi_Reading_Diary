import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/exceptions/linking_exceptions.dart';
import 'package:lumi_reading_tracker/services/parent_linking_service.dart';

void main() {
  group('ParentLinkingService', () {
    late FakeFirebaseFirestore firestore;
    late ParentLinkingService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ParentLinkingService(firestore: firestore);
    });

    Future<void> seedStudent({
      String schoolId = 'school_1',
      String studentId = 'student_1',
      String firstName = 'Sam',
      String lastName = 'Booker',
      List<String> parentIds = const [],
    }) async {
      await firestore
          .collection('schools')
          .doc(schoolId)
          .set({'name': 'Lumi'});
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

      test('handles student without existing document gracefully', () async {
        // School exists but student does not
        await firestore
            .collection('schools')
            .doc('school_1')
            .set({'name': 'Lumi'});

        final code = await service.createLinkCode(
          studentId: 'nonexistent_student',
          schoolId: 'school_1',
          createdBy: 'admin_1',
        );

        expect(code.code, hasLength(8));
        expect(code.metadata, isNull);
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
      test('returns valid active code', () async {
        await seedLinkCode();

        final verified = await service.verifyCode('QWER5678');
        expect(verified.code, 'QWER5678');
        expect(verified.status.name, 'active');
      });

      test('verifies code case-insensitively', () async {
        await seedLinkCode(code: 'ABCD1234');

        final verified = await service.verifyCode('abcd1234');
        expect(verified.code, 'ABCD1234');
      });

      test('throws InvalidCodeException for nonexistent code', () async {
        await expectLater(
          () => service.verifyCode('DOESNTEXIST'),
          throwsA(isA<InvalidCodeException>()),
        );
      });

      test('throws CodeAlreadyUsedException for used code', () async {
        await seedLinkCode(
          code: 'USED0001',
          status: 'used',
          usedBy: 'parent_1',
        );

        await expectLater(
          () => service.verifyCode('USED0001'),
          throwsA(isA<CodeAlreadyUsedException>()),
        );
      });

      test('throws CodeRevokedException for revoked code', () async {
        await firestore.collection('studentLinkCodes').doc('revoked_1').set({
          'studentId': 'student_1',
          'schoolId': 'school_1',
          'code': 'REVK0001',
          'status': 'revoked',
          'createdBy': 'admin_1',
          'createdAt': Timestamp.now(),
          'expiresAt':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          'revokedBy': 'admin_1',
          'revokeReason': 'Student transferred',
        });

        await expectLater(
          () => service.verifyCode('REVK0001'),
          throwsA(isA<CodeRevokedException>()),
        );
      });

      test('throws CodeExpiredException for expired code', () async {
        await firestore.collection('studentLinkCodes').doc('expired_1').set({
          'studentId': 'student_1',
          'schoolId': 'school_1',
          'code': 'EXPD0001',
          'status': 'expired',
          'createdBy': 'admin_1',
          'createdAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 400))),
          'expiresAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 35))),
        });

        await expectLater(
          () => service.verifyCode('EXPD0001'),
          throwsA(isA<CodeExpiredException>()),
        );
      });

      test('prefers active record when legacy duplicates exist', () async {
        final now = DateTime.now();

        await firestore.collection('studentLinkCodes').doc('legacy_used').set({
          'studentId': 'student_1',
          'schoolId': 'school_1',
          'code': 'ABCD2345',
          'status': 'used',
          'createdBy': 'admin_1',
          'createdAt':
              Timestamp.fromDate(now.subtract(const Duration(days: 5))),
          'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 30))),
          'usedBy': 'parent_old',
          'usedAt': Timestamp.fromDate(now.subtract(const Duration(days: 4))),
        });

        await firestore
            .collection('studentLinkCodes')
            .doc('active_latest')
            .set({
          'studentId': 'student_1',
          'schoolId': 'school_1',
          'code': 'ABCD2345',
          'status': 'active',
          'createdBy': 'admin_1',
          'createdAt':
              Timestamp.fromDate(now.subtract(const Duration(days: 1))),
          'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 30))),
        });

        final verified = await service.verifyCode('ABCD2345');
        expect(verified.id, equals('active_latest'));
        expect(verified.status.name, equals('active'));
      });
    });

    // ── linkParentToStudent ──

    group('linkParentToStudent', () {
      test('marks code used and updates both sides', () async {
        await seedStudent();
        await seedLinkCode();

        final linked = await service.linkParentToStudent(
          code: 'QWER5678',
          parentUserId: 'parent_1',
          parentEmail: 'parent@school.test',
        );

        expect(linked, isTrue);

        // Student should have parent linked
        final studentDoc = await firestore
            .collection('schools')
            .doc('school_1')
            .collection('students')
            .doc('student_1')
            .get();
        expect(
          List<String>.from(studentDoc.data()!['parentIds']),
          contains('parent_1'),
        );

        // Parent document should be created/updated
        final parentDoc = await firestore
            .collection('schools')
            .doc('school_1')
            .collection('parents')
            .doc('parent_1')
            .get();
        expect(
          List<String>.from(parentDoc.data()!['linkedChildren']),
          contains('student_1'),
        );
        expect(parentDoc.data()!['schoolId'], 'school_1');

        // Code should be marked used
        final codeDoc =
            await firestore.collection('studentLinkCodes').doc('code_1').get();
        expect(codeDoc.data()!['status'], equals('used'));
        expect(codeDoc.data()!['usedBy'], equals('parent_1'));
      });

      test('handles case insensitive and trimmed code input', () async {
        await seedStudent();
        await seedLinkCode(code: 'TRIM1234');

        final linked = await service.linkParentToStudent(
          code: '  trim1234  ',
          parentUserId: 'parent_1',
          parentEmail: 'parent@test.com',
        );

        expect(linked, isTrue);
      });

      test('throws AlreadyLinkedException when parent already linked',
          () async {
        await seedStudent(parentIds: ['parent_1']);
        await seedLinkCode();

        await expectLater(
          () => service.linkParentToStudent(
            code: 'QWER5678',
            parentUserId: 'parent_1',
            parentEmail: 'parent@test.com',
          ),
          throwsA(isA<AlreadyLinkedException>()),
        );
      });

      test('throws StudentNotFoundException when student missing', () async {
        // Only create school but not the student
        await firestore
            .collection('schools')
            .doc('school_1')
            .set({'name': 'Test'});
        await seedLinkCode();

        await expectLater(
          () => service.linkParentToStudent(
            code: 'QWER5678',
            parentUserId: 'parent_1',
            parentEmail: 'parent@test.com',
          ),
          throwsA(isA<StudentNotFoundException>()),
        );
      });

      test('does not create legacy top-level notifications after successful link', () async {
        await seedStudent();
        await seedLinkCode();

        await service.linkParentToStudent(
          code: 'QWER5678',
          parentUserId: 'parent_1',
          parentEmail: 'parent@school.test',
        );

        final notifications =
            await firestore.collection('notifications').get();
        expect(notifications.docs, isEmpty);
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

    group('unlinkParentFromStudent', () {
      test('removes link from both student and parent documents', () async {
        // Set up linked state
        await firestore
            .collection('schools')
            .doc('school_1')
            .set({'name': 'Test'});
        await firestore
            .collection('schools')
            .doc('school_1')
            .collection('students')
            .doc('student_1')
            .set({
          'firstName': 'Sam',
          'lastName': 'Booker',
          'studentId': 'S-100',
          'classId': 'class_1',
          'schoolId': 'school_1',
          'parentIds': ['parent_1'],
          'createdAt': Timestamp.now(),
        });
        await firestore
            .collection('schools')
            .doc('school_1')
            .collection('parents')
            .doc('parent_1')
            .set({
          'linkedChildren': ['student_1'],
          'schoolId': 'school_1',
        });

        await service.unlinkParentFromStudent(
          schoolId: 'school_1',
          studentId: 'student_1',
          parentUserId: 'parent_1',
          reason: 'Parent requested',
        );

        final studentDoc = await firestore
            .collection('schools')
            .doc('school_1')
            .collection('students')
            .doc('student_1')
            .get();
        expect(
          List<String>.from(studentDoc.data()!['parentIds']),
          isNot(contains('parent_1')),
        );

        final parentDoc = await firestore
            .collection('schools')
            .doc('school_1')
            .collection('parents')
            .doc('parent_1')
            .get();
        expect(
          List<String>.from(parentDoc.data()!['linkedChildren']),
          isNot(contains('student_1')),
        );
      });

      test('throws when student does not exist', () async {
        await firestore
            .collection('schools')
            .doc('school_1')
            .set({'name': 'Test'});
        await firestore
            .collection('schools')
            .doc('school_1')
            .collection('parents')
            .doc('parent_1')
            .set({
          'linkedChildren': ['student_1'],
          'schoolId': 'school_1',
        });

        await expectLater(
          () => service.unlinkParentFromStudent(
            schoolId: 'school_1',
            studentId: 'nonexistent',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('throws when parent is not linked to student', () async {
        await firestore
            .collection('schools')
            .doc('school_1')
            .set({'name': 'Test'});
        await firestore
            .collection('schools')
            .doc('school_1')
            .collection('students')
            .doc('student_1')
            .set({
          'firstName': 'Sam',
          'lastName': 'Booker',
          'studentId': 'S-100',
          'classId': 'class_1',
          'schoolId': 'school_1',
          'parentIds': [],
          'createdAt': Timestamp.now(),
        });
        await firestore
            .collection('schools')
            .doc('school_1')
            .collection('parents')
            .doc('parent_1')
            .set({
          'linkedChildren': [],
          'schoolId': 'school_1',
        });

        await expectLater(
          () => service.unlinkParentFromStudent(
            schoolId: 'school_1',
            studentId: 'student_1',
            parentUserId: 'parent_1',
          ),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not linked'),
          )),
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
