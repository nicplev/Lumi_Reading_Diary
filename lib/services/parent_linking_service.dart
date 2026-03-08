import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/student_link_code_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';
import '../core/exceptions/linking_exceptions.dart';

class ParentLinkingService {
  final FirebaseFirestore _firestore;

  ParentLinkingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Generate unique 8-character code
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude similar chars
    final random = Random();
    return List.generate(8, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  Future<bool> _isCodeUnique(String candidateCode) async {
    final existing = await _firestore
        .collection('studentLinkCodes')
        .where('code', isEqualTo: candidateCode)
        .limit(1)
        .get();
    return existing.docs.isEmpty;
  }

  Future<String> _generateUniqueCode() async {
    const maxAttempts = 40;
    for (var i = 0; i < maxAttempts; i++) {
      final code = _generateCode();
      final isUnique = await _isCodeUnique(code);
      if (isUnique) return code;
    }
    throw Exception('Unable to generate unique link code after max attempts');
  }

  // Create linking code for a student
  Future<StudentLinkCodeModel> createLinkCode({
    required String studentId,
    required String schoolId,
    required String createdBy,
    int validityDays = 365, // Code valid for 1 year by default
  }) async {
    final code = await _generateUniqueCode();

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
        'studentFullName':
            '${studentData['firstName']} ${studentData['lastName']}',
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

    // Enforce one-active-code-per-student lifecycle policy.
    final activeCodesQuery = await _firestore
        .collection('studentLinkCodes')
        .where('studentId', isEqualTo: studentId)
        .where('status', isEqualTo: 'active')
        .get();

    final batch = _firestore.batch();
    for (final codeDoc in activeCodesQuery.docs) {
      batch.update(codeDoc.reference, {
        'status': LinkCodeStatus.revoked.toString().split('.').last,
        'revokedBy': createdBy,
        'revokedAt': FieldValue.serverTimestamp(),
        'revokeReason': 'Superseded by newly generated link code',
      });
    }

    final docRef = _firestore.collection('studentLinkCodes').doc();
    batch.set(docRef, linkCode.toFirestore());
    await batch.commit();

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
    final dedupedStudentIds = studentIds.toSet().toList(growable: false);
    const chunkSize = 25;

    for (var i = 0; i < dedupedStudentIds.length; i += chunkSize) {
      final chunk = dedupedStudentIds.skip(i).take(chunkSize).toList();
      final generatedChunk = await Future.wait(
        chunk.map((studentId) async {
          final code = await createLinkCode(
            studentId: studentId,
            schoolId: schoolId,
            createdBy: createdBy,
            validityDays: validityDays,
          );
          return MapEntry(studentId, code);
        }),
      );

      for (final entry in generatedChunk) {
        codes[entry.key] = entry.value;
      }
    }

    return codes;
  }

  // Verify and retrieve link code
  Future<StudentLinkCodeModel> verifyCode(String code) async {
    final query = await _firestore
        .collection('studentLinkCodes')
        .where('code', isEqualTo: code.toUpperCase())
        .limit(10)
        .get();

    if (query.docs.isEmpty) {
      throw InvalidCodeException();
    }

    final parsedCodes =
        query.docs.map(StudentLinkCodeModel.fromFirestore).toList()
          ..sort((a, b) {
            final aPriority = _priorityForCode(a);
            final bPriority = _priorityForCode(b);
            if (aPriority != bPriority) return aPriority.compareTo(bPriority);
            return b.createdAt.compareTo(a.createdAt);
          });

    final bestCode = parsedCodes.first;

    if (bestCode.status == LinkCodeStatus.active && !bestCode.isExpired) {
      return bestCode;
    }

    if (bestCode.status == LinkCodeStatus.used) {
      throw CodeAlreadyUsedException();
    }

    if (bestCode.status == LinkCodeStatus.revoked) {
      throw CodeRevokedException(reason: bestCode.revokeReason);
    }

    if (bestCode.status == LinkCodeStatus.expired || bestCode.isExpired) {
      throw CodeExpiredException();
    }

    throw InvalidCodeException();
  }

  int _priorityForCode(StudentLinkCodeModel code) {
    if (code.status == LinkCodeStatus.active && !code.isExpired) return 0;
    if (code.status == LinkCodeStatus.used) return 1;
    if (code.status == LinkCodeStatus.revoked) return 2;
    if (code.status == LinkCodeStatus.expired || code.isExpired) return 3;
    return 4;
  }

  // Link parent to student using code
  // Uses Firestore transaction to ensure atomicity and prevent race conditions
  Future<bool> linkParentToStudent({
    required String code,
    required String parentUserId,
    required String parentEmail,
  }) async {
    final normalizedCode = code.toUpperCase().trim();
    final verifiedCode = await verifyCode(normalizedCode);

    return await _firestore.runTransaction<bool>((transaction) async {
      try {
        // 1. Re-read verified code inside transaction to prevent race conditions.
        final linkCodeRef =
            _firestore.collection('studentLinkCodes').doc(verifiedCode.id);
        final freshCodeSnapshot = await transaction.get(linkCodeRef);
        if (!freshCodeSnapshot.exists) {
          throw InvalidCodeException();
        }

        final freshCodeData = freshCodeSnapshot.data()!;
        final freshStatus = freshCodeData['status'] as String? ?? '';
        final freshCodeValue =
            (freshCodeData['code'] as String? ?? '').toUpperCase();
        if (freshCodeValue != normalizedCode) {
          throw InvalidCodeException();
        }

        final dynamic expiresAtRaw =
            freshCodeData['expiresAt'] ?? freshCodeData['expiryDate'];
        DateTime? expiresAt;
        if (expiresAtRaw is Timestamp) {
          expiresAt = expiresAtRaw.toDate();
        } else if (expiresAtRaw is DateTime) {
          expiresAt = expiresAtRaw;
        } else if (expiresAtRaw is String) {
          expiresAt = DateTime.tryParse(expiresAtRaw);
        }
        if (expiresAt == null) {
          throw InvalidCodeException();
        }

        if (freshStatus == 'used') {
          throw CodeAlreadyUsedException();
        }
        if (freshStatus == 'revoked') {
          throw CodeRevokedException(
            reason: freshCodeData['revokeReason'] as String?,
          );
        }
        if (freshStatus == 'expired' || DateTime.now().isAfter(expiresAt)) {
          throw CodeExpiredException();
        }
        if (freshStatus != 'active') {
          throw InvalidCodeException();
        }

        final schoolId = freshCodeData['schoolId'] as String? ?? '';
        final studentId = freshCodeData['studentId'] as String? ?? '';
        if (schoolId.isEmpty || studentId.isEmpty) {
          throw InvalidCodeException();
        }

        // 2. Get student document reference and read within transaction.
        final studentRef = _firestore
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(studentId);

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
            .doc(schoolId)
            .collection('parents')
            .doc(parentUserId);

        // 6. ATOMIC UPDATES - All operations succeed or all fail

        // Update student with parent ID
        transaction.update(studentRef, {
          'parentIds': FieldValue.arrayUnion([parentUserId]),
        });

        // Update parent with linked child (upsert for recovery-safe retries).
        transaction.set(
            parentRef,
            {
              'linkedChildren': FieldValue.arrayUnion([studentId]),
              'schoolId': schoolId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));

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
            schoolId: schoolId,
            studentId: studentId,
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
    final dedupedStudentIds = studentIds.toSet().toList(growable: false);

    if (dedupedStudentIds.isEmpty) {
      return codes;
    }

    for (var i = 0; i < dedupedStudentIds.length; i += 30) {
      final chunk = dedupedStudentIds.skip(i).take(30).toList();
      final query = await _firestore
          .collection('studentLinkCodes')
          .where('studentId', whereIn: chunk)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .get();

      for (final doc in query.docs) {
        final model = StudentLinkCodeModel.fromFirestore(doc);
        codes.putIfAbsent(model.studentId, () => model);
      }
    }

    for (final studentId in dedupedStudentIds) {
      codes.putIfAbsent(studentId, () => null);
    }

    return codes;
  }

  // Unlink parent from student
  Future<void> unlinkParentFromStudent({
    required String schoolId,
    required String studentId,
    required String parentUserId,
    String? unlinkedBy,
    String? reason,
  }) async {
    // Use transaction to ensure atomic updates (both succeed or both fail)
    await _firestore.runTransaction((transaction) async {
      final studentRef = _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(studentId);

      final parentRef = _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('parents')
          .doc(parentUserId);

      // Read student and parent documents to verify they exist
      final studentSnapshot = await transaction.get(studentRef);
      final parentSnapshot = await transaction.get(parentRef);

      if (!studentSnapshot.exists) {
        throw Exception('Student not found');
      }

      if (!parentSnapshot.exists) {
        throw Exception('Parent not found');
      }

      // Verify the link exists before unlinking
      final studentData = studentSnapshot.data()!;
      final parentIds = List<String>.from(studentData['parentIds'] ?? []);

      if (!parentIds.contains(parentUserId)) {
        throw Exception('Parent is not linked to this student');
      }

      // Atomic updates: Remove from both sides
      transaction.update(studentRef, {
        'parentIds': FieldValue.arrayRemove([parentUserId]),
      });

      transaction.update(parentRef, {
        'linkedChildren': FieldValue.arrayRemove([studentId]),
      });

      // Find and revoke any active link codes for this student
      final linkCodesSnapshot = await _firestore
          .collection('studentLinkCodes')
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'active')
          .get();

      for (final codeDoc in linkCodesSnapshot.docs) {
        transaction.update(codeDoc.reference, {
          'status': 'revoked',
          'revokedBy': unlinkedBy ?? parentUserId,
          'revokedAt': FieldValue.serverTimestamp(),
          'revokeReason': reason ?? 'Parent unlinked from student',
        });
      }
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
