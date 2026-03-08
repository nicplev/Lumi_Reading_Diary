import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/exceptions/linking_exceptions.dart';
import 'package:lumi_reading_tracker/services/parent_linking_service.dart';

void main() {
  group('ParentLinkingService', () {
    test('createLinkCode revokes previous active code for student', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ParentLinkingService(firestore: firestore);

      await firestore
          .collection('schools')
          .doc('school_1')
          .set({'name': 'Lumi'});
      await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .set({
        'firstName': 'Alex',
        'lastName': 'Reader',
      });

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

    test('verifyCode prefers active record when legacy duplicates exist',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = ParentLinkingService(firestore: firestore);
      final now = DateTime.now();

      await firestore.collection('studentLinkCodes').doc('legacy_used').set({
        'studentId': 'student_1',
        'schoolId': 'school_1',
        'code': 'ABCD2345',
        'status': 'used',
        'createdBy': 'admin_1',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 5))),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 30))),
        'usedBy': 'parent_old',
        'usedAt': Timestamp.fromDate(now.subtract(const Duration(days: 4))),
      });

      await firestore.collection('studentLinkCodes').doc('active_latest').set({
        'studentId': 'student_1',
        'schoolId': 'school_1',
        'code': 'ABCD2345',
        'status': 'active',
        'createdBy': 'admin_1',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 30))),
      });

      final verified = await service.verifyCode('ABCD2345');
      expect(verified.id, equals('active_latest'));
      expect(verified.status.name, equals('active'));
    });

    test('linkParentToStudent marks code used and updates both sides',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = ParentLinkingService(firestore: firestore);

      final expiresAt = DateTime.now().add(const Duration(days: 30));

      await firestore
          .collection('schools')
          .doc('school_1')
          .set({'name': 'Lumi'});
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
        'parentIds': <String>[],
        'createdAt': Timestamp.now(),
      });

      await firestore.collection('studentLinkCodes').doc('code_1').set({
        'studentId': 'student_1',
        'schoolId': 'school_1',
        'code': 'QWER5678',
        'status': 'active',
        'createdBy': 'admin_1',
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });

      final linked = await service.linkParentToStudent(
        code: 'QWER5678',
        parentUserId: 'parent_1',
        parentEmail: 'parent@school.test',
      );

      expect(linked, isTrue);

      final studentDoc = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('students')
          .doc('student_1')
          .get();
      expect(
        List<String>.from(studentDoc.data()!['parentIds'] as List<dynamic>),
        contains('parent_1'),
      );

      final parentDoc = await firestore
          .collection('schools')
          .doc('school_1')
          .collection('parents')
          .doc('parent_1')
          .get();
      expect(
        List<String>.from(parentDoc.data()!['linkedChildren'] as List<dynamic>),
        contains('student_1'),
      );

      final codeDoc =
          await firestore.collection('studentLinkCodes').doc('code_1').get();
      expect(codeDoc.data()!['status'], equals('used'));
      expect(codeDoc.data()!['usedBy'], equals('parent_1'));
    });

    test('verifyCode throws CodeAlreadyUsedException for used-only matches',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = ParentLinkingService(firestore: firestore);

      await firestore.collection('studentLinkCodes').doc('used_1').set({
        'studentId': 'student_1',
        'schoolId': 'school_1',
        'code': 'USED0001',
        'status': 'used',
        'createdBy': 'admin_1',
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30)),
        ),
        'usedBy': 'parent_1',
        'usedAt': Timestamp.now(),
      });

      await expectLater(
        () => service.verifyCode('USED0001'),
        throwsA(isA<CodeAlreadyUsedException>()),
      );
    });
  });
}
