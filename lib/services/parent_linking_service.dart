import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/student_link_code_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';

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
  Future<StudentLinkCodeModel?> verifyCode(String code) async {
    final query = await _firestore
        .collection('studentLinkCodes')
        .where('code', isEqualTo: code.toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    final linkCode = StudentLinkCodeModel.fromFirestore(query.docs.first);

    // Check if code is usable
    if (!linkCode.isUsable) {
      return null;
    }

    return linkCode;
  }

  // Link parent to student using code
  Future<bool> linkParentToStudent({
    required String code,
    required String parentUserId,
    required String parentEmail,
  }) async {
    try {
      // 1. Verify code
      final linkCode = await verifyCode(code);
      if (linkCode == null) {
        throw Exception('Invalid or expired code');
      }

      // 2. Get student
      final studentDoc = await _firestore
          .collection('schools')
          .doc(linkCode.schoolId)
          .collection('students')
          .doc(linkCode.studentId)
          .get();

      if (!studentDoc.exists) {
        throw Exception('Student not found');
      }

      final student = StudentModel.fromFirestore(studentDoc);

      // 3. Check if parent already linked
      if (student.parentIds.contains(parentUserId)) {
        throw Exception('Parent already linked to this student');
      }

      // 4. Update student with parent ID
      await _firestore
          .collection('schools')
          .doc(linkCode.schoolId)
          .collection('students')
          .doc(linkCode.studentId)
          .update({
        'parentIds': FieldValue.arrayUnion([parentUserId]),
      });

      // 5. Update parent user with linked child
      await _firestore
          .collection('schools')
          .doc(linkCode.schoolId)
          .collection('parents')
          .doc(parentUserId)
          .update({
        'linkedChildren': FieldValue.arrayUnion([linkCode.studentId]),
        'schoolId': linkCode.schoolId,
      });

      // 6. Mark code as used
      await _firestore
          .collection('studentLinkCodes')
          .doc(linkCode.id)
          .update({
        'status': LinkCodeStatus.used.toString().split('.').last,
        'usedBy': parentUserId,
        'usedAt': FieldValue.serverTimestamp(),
      });

      // 7. Create notification for teacher
      await _createLinkNotification(
        schoolId: linkCode.schoolId,
        studentId: linkCode.studentId,
        parentUserId: parentUserId,
        parentEmail: parentEmail,
      );

      return true;
    } catch (e) {
      throw Exception('Failed to link parent: $e');
    }
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
