import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/student_link_code_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';
import '../core/exceptions/linking_exceptions.dart';

class ParentLinkingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Generate unique 8-character code
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude similar chars
    final random = Random();
    return List.generate(8, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  // Create linking code for a student
  Future<StudentLinkCodeModel> createLinkCode({
    required String studentId,
    required String schoolId,
    required String createdBy,
    int validityDays = 365, // Code valid for 1 year by default
  }) async {
    String code;
    bool isUnique = false;

    // Generate unique code
    do {
      code = _generateCode();
      final existing = await _firestore
          .collection('studentLinkCodes')
          .where('code', isEqualTo: code)
          .where('status', isEqualTo: 'active')
          .get();
      isUnique = existing.docs.isEmpty;
    } while (!isUnique);

    // Fetch student info to store in metadata
    // This allows parents to see student name without needing read access to students collection
    final studentDoc = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId)
        .get();

    Map<String, dynamic>? metadata;
    if (studentDoc.exists) {
      final studentData = studentDoc.data()!;
      metadata = {
        'studentFirstName': studentData['firstName'],
        'studentLastName': studentData['lastName'],
        'studentFullName': '${studentData['firstName']} ${studentData['lastName']}',
      };
    }

    final linkCode = StudentLinkCodeModel(
      id: '',
      studentId: studentId,
      schoolId: schoolId,
      code: code,
      status: LinkCodeStatus.active,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(days: validityDays)),
      createdBy: createdBy,
      metadata: metadata,
    );

    final docRef = await _firestore
        .collection('studentLinkCodes')
        .add(linkCode.toFirestore());

    return linkCode.copyWith(id: docRef.id);
  }

  // Generate codes for multiple students
  Future<Map<String, StudentLinkCodeModel>> generateBulkCodes({
    required List<String> studentIds,
    required String schoolId,
    required String createdBy,
    int validityDays = 365,
  }) async {
    final Map<String, StudentLinkCodeModel> codes = {};

    for (final studentId in studentIds) {
      final code = await createLinkCode(
        studentId: studentId,
        schoolId: schoolId,
        createdBy: createdBy,
        validityDays: validityDays,
      );
      codes[studentId] = code;
    }

    return codes;
  }

  // Verify and retrieve link code
  Future<StudentLinkCodeModel> verifyCode(String code) async {
    final query = await _firestore
        .collection('studentLinkCodes')
        .where('code', isEqualTo: code.toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw InvalidCodeException();
    }

    final linkCode = StudentLinkCodeModel.fromFirestore(query.docs.first);

    // Check if code is usable and throw specific exceptions
    if (linkCode.status == LinkCodeStatus.used) {
      throw CodeAlreadyUsedException();
    }

    if (linkCode.status == LinkCodeStatus.revoked) {
      throw CodeRevokedException(reason: linkCode.revokeReason);
    }

    if (linkCode.status == LinkCodeStatus.expired ||
        DateTime.now().isAfter(linkCode.expiresAt)) {
      throw CodeExpiredException();
    }

    if (!linkCode.isUsable) {
      throw InvalidCodeException();
    }

    return linkCode;
  }

  // Link parent to student using code
  // Uses Firestore transaction to ensure atomicity and prevent race conditions
  Future<bool> linkParentToStudent({
    required String code,
    required String parentUserId,
    required String parentEmail,
  }) async {
    return await _firestore.runTransaction<bool>((transaction) async {
      try {
        // 1. Verify code and get link code document
        final codeQuery = await _firestore
            .collection('studentLinkCodes')
            .where('code', isEqualTo: code.toUpperCase())
            .limit(1)
            .get();

        if (codeQuery.docs.isEmpty) {
          throw InvalidCodeException();
        }

        final codeDoc = codeQuery.docs.first;
        final linkCode = StudentLinkCodeModel.fromFirestore(codeDoc);

        // Check if code is usable (active and not expired)
        if (linkCode.status == LinkCodeStatus.used) {
          throw CodeAlreadyUsedException();
        }

        if (linkCode.status == LinkCodeStatus.revoked) {
          throw CodeRevokedException(reason: linkCode.revokeReason);
        }

        if (linkCode.status == LinkCodeStatus.expired ||
            DateTime.now().isAfter(linkCode.expiresAt)) {
          throw CodeExpiredException();
        }

        if (!linkCode.isUsable) {
          throw InvalidCodeException();
        }

        // 2. Get student document reference and read within transaction
        final studentRef = _firestore
            .collection('schools')
            .doc(linkCode.schoolId)
            .collection('students')
            .doc(linkCode.studentId);

        final studentSnapshot = await transaction.get(studentRef);

        if (!studentSnapshot.exists) {
          throw StudentNotFoundException();
        }

        final student = StudentModel.fromFirestore(studentSnapshot);

        // 3. Check if parent already linked
        if (student.parentIds.contains(parentUserId)) {
          throw AlreadyLinkedException();
        }

        // 4. Get parent document reference
        final parentRef = _firestore
            .collection('schools')
            .doc(linkCode.schoolId)
            .collection('parents')
            .doc(parentUserId);

        // 5. Get code document reference
        final linkCodeRef = _firestore
            .collection('studentLinkCodes')
            .doc(linkCode.id);

        // Re-check code status within transaction to prevent race condition
        // This ensures another parent hasn't used the code between our initial check and now
        final freshCodeSnapshot = await transaction.get(linkCodeRef);
        if (!freshCodeSnapshot.exists) {
          throw InvalidCodeException();
        }

        final freshCodeData = freshCodeSnapshot.data()!;

        if (freshCodeData['status'] != 'active') {
          throw CodeAlreadyUsedException();
        }

        // 6. ATOMIC UPDATES - All operations succeed or all fail

        // Update student with parent ID
        transaction.update(studentRef, {
          'parentIds': FieldValue.arrayUnion([parentUserId]),
        });

        // Update parent with linked child
        transaction.update(parentRef, {
          'linkedChildren': FieldValue.arrayUnion([linkCode.studentId]),
          'schoolId': linkCode.schoolId,
        });

        // Mark code as used
        transaction.update(linkCodeRef, {
          'status': LinkCodeStatus.used.toString().split('.').last,
          'usedBy': parentUserId,
          'usedAt': FieldValue.serverTimestamp(),
        });

        // 7. Create notification for teacher (outside transaction)
        // Notifications are non-critical and can be done after transaction commits
        // Using Future.delayed to ensure it runs after transaction completes
        Future.delayed(Duration.zero, () {
          _createLinkNotification(
            schoolId: linkCode.schoolId,
            studentId: linkCode.studentId,
            parentUserId: parentUserId,
            parentEmail: parentEmail,
          ).catchError((error) {
            // Log error but don't fail the linking operation
            print('Warning: Failed to create link notification: $error');
          });
        });

        return true;
      } on LinkingException {
        // Re-throw custom linking exceptions
        rethrow;
      } catch (e) {
        // Wrap any other errors in a TransactionFailedException
        throw TransactionFailedException(e.toString());
      }
    });
  }

  // Create notification for teacher when parent links
  Future<void> _createLinkNotification({
    required String schoolId,
    required String studentId,
    required String parentUserId,
    required String parentEmail,
  }) async {
    final notification = {
      'type': 'parent_linked',
      'schoolId': schoolId,
      'studentId': studentId,
      'parentUserId': parentUserId,
      'parentEmail': parentEmail,
      'message': 'A parent has linked to a student',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    };

    await _firestore.collection('notifications').add(notification);
  }

  // Get active code for a student
  Future<StudentLinkCodeModel?> getActiveCodeForStudent(
    String studentId,
  ) async {
    final query = await _firestore
        .collection('studentLinkCodes')
        .where('studentId', isEqualTo: studentId)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    return StudentLinkCodeModel.fromFirestore(query.docs.first);
  }

  // Revoke a linking code
  Future<void> revokeCode({
    required String codeId,
    required String revokedBy,
    String? reason,
  }) async {
    await _firestore.collection('studentLinkCodes').doc(codeId).update({
      'status': LinkCodeStatus.revoked.toString().split('.').last,
      'revokedBy': revokedBy,
      'revokedAt': FieldValue.serverTimestamp(),
      'revokeReason': reason,
    });
  }

  // Get all codes for a school
  Stream<List<StudentLinkCodeModel>> getSchoolCodes(String schoolId) {
    return _firestore
        .collection('studentLinkCodes')
        .where('schoolId', isEqualTo: schoolId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StudentLinkCodeModel.fromFirestore(doc))
            .toList());
  }

  // Get codes for specific students
  Future<Map<String, StudentLinkCodeModel?>> getCodesForStudents(
    List<String> studentIds,
  ) async {
    final Map<String, StudentLinkCodeModel?> codes = {};

    for (final studentId in studentIds) {
      final code = await getActiveCodeForStudent(studentId);
      codes[studentId] = code;
    }

    return codes;
  }

  // Unlink parent from student
  Future<void> unlinkParentFromStudent({
    required String schoolId,
    required String studentId,
    required String parentUserId,
  }) async {
    // Remove from student's parentIds
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId)
        .update({
      'parentIds': FieldValue.arrayRemove([parentUserId]),
    });

    // Remove from parent's linkedChildren
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parents')
        .doc(parentUserId)
        .update({
      'linkedChildren': FieldValue.arrayRemove([studentId]),
    });
  }

  // Get parent's linked students
  Future<List<StudentModel>> getLinkedStudents({
    required String schoolId,
    required String parentUserId,
  }) async {
    final parentDoc = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parents')
        .doc(parentUserId)
        .get();

    if (!parentDoc.exists) {
      return [];
    }

    final parent = UserModel.fromFirestore(parentDoc);
    final students = <StudentModel>[];

    for (final studentId in parent.linkedChildren) {
      final studentDoc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(studentId)
          .get();

      if (studentDoc.exists) {
        students.add(StudentModel.fromFirestore(studentDoc));
      }
    }

    return students;
  }
}
