import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../data/models/student_link_code_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';
import '../core/exceptions/linking_exceptions.dart';
import '../core/services/assert_writable.dart';
import '../core/services/functions_instance.dart';
import 'offline_service.dart';

/// Invokes a Cloud Function and returns its `result.data` payload.
///
/// Pulled out as an injectable seam so tests can stub the callable without
/// having to mock the FirebaseFunctions class — whose [httpsCallable] is
/// concrete and reaches into the FlutterPluginPlatform, which isn't set up
/// in unit tests.
typedef HttpsCallableInvoker = Future<Object?> Function(
  String name,
  Map<String, dynamic> args,
);

Future<Object?> _defaultCallableInvoker(
  String name,
  Map<String, dynamic> args,
) async {
  final callable = lumiFunctions.httpsCallable(
    name,
    options: HttpsCallableOptions(limitedUseAppCheckToken: true),
  );
  final result = await callable.call<Object?>(args);
  return result.data;
}

class ParentLinkingService {
  final FirebaseFirestore _firestore;
  final HttpsCallableInvoker _invoke;

  ParentLinkingService({
    FirebaseFirestore? firestore,
    HttpsCallableInvoker? callableInvoker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _invoke = callableInvoker ?? _defaultCallableInvoker;

  // Generate unique 8-character code
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude similar chars
    final random = Random.secure();
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

  // Create linking code for a student.
  //
  // [intendedFor] scopes the one-active-code supersede policy: a new code only
  // revokes existing active codes with the SAME intent. This lets a staff code
  // and a guardian's co-parent invite coexist without clobbering each other.
  Future<StudentLinkCodeModel> createLinkCode({
    required String studentId,
    required String schoolId,
    required String createdBy,
    int validityDays = 30,
    String intendedFor = LinkCodeIntent.staffIssued,
    String? note,
  }) async {
    assertWritable(
      opLabel: 'parentLinking.createLinkCode',
      collection: 'studentLinkCodes',
      operation: 'create',
    );
    if (validityDays < 1 || validityDays > 30) {
      throw ArgumentError.value(validityDays, 'validityDays', 'must be 1–30');
    }
    final code = await _generateUniqueCode();

    // Fetch student info to store in metadata
    // This allows parents to see student name without needing read access to students collection
    final studentDoc = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId)
        .get();

    // Refuse to issue a code for a non-existent student. Without this check
    // an orphan code can outlive the student doc, and parents who later try
    // to use it hit "student-missing" from linkParentToStudent with no
    // recovery path.
    if (!studentDoc.exists) {
      throw StateError(
          'createLinkCode: student $schoolId/$studentId does not exist');
    }

    final studentData = studentDoc.data()!;
    final Map<String, dynamic> metadata = {
      'studentFirstName': studentData['firstName'],
      'studentLastName': studentData['lastName'],
      'studentFullName':
          '${studentData['firstName']} ${studentData['lastName']}',
    };

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
      intendedFor: intendedFor,
      note: note,
    );

    // Enforce one-active-code-per-(student, intent) lifecycle policy. Only
    // codes sharing this code's intent are superseded — a pending co-parent
    // invite survives a staff regeneration and vice versa. Filtered in-code
    // (not via a where clause) to avoid needing a new composite index.
    //
    // The .limit(10) is required so a guardian creating a co-parent invite
    // matches the bounded-list rule on studentLinkCodes — the broader list
    // rule for parents only matches docs already keyed to them via usedBy,
    // which never holds for the active codes we're trying to supersede. 10
    // is comfortably above the steady-state cap of one active code per
    // (student, intent).
    final activeCodesQuery = await _firestore
        .collection('studentLinkCodes')
        .where('studentId', isEqualTo: studentId)
        .where('status', isEqualTo: 'active')
        .limit(10)
        .get();

    final batch = _firestore.batch();
    for (final codeDoc in activeCodesQuery.docs) {
      final existing = StudentLinkCodeModel.fromFirestore(codeDoc);
      if (existing.intendedFor != intendedFor) continue;
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

  // Create a co-parent invite code that an already-linked guardian can share
  // with another guardian (e.g. a separated parent).
  //
  // Generation runs SERVER-side (createCoParentInvite callable): the server
  // verifies the caller is a parent linked to [studentId], generates a unique
  // code, supersedes any prior active co-parent invite, and writes the
  // studentLinkCodes doc via the Admin SDK. The client no longer reads/writes
  // studentLinkCodes here, so the unauthenticated `list` rule and the parent
  // client-create rule can be removed. [parentUserId] is accepted for source
  // compatibility but ignored — the server derives identity from auth.
  Future<StudentLinkCodeModel> createCoParentInviteCode({
    required String studentId,
    required String schoolId,
    required String parentUserId,
    int validityDays = 7,
    String? note,
  }) async {
    assertWritable(
      opLabel: 'parentLinking.createCoParentInvite',
      collection: 'studentLinkCodes',
      operation: 'create',
    );
    final raw = await _invokeWithRetry(
      'createCoParentInvite',
      <String, dynamic>{
        'schoolId': schoolId,
        'studentId': studentId,
        'validityDays': validityDays,
        if (note != null) 'note': note,
      },
    );
    if (raw is! Map) {
      throw TransactionFailedException('Could not create co-parent invite.');
    }
    return StudentLinkCodeModel.fromVerifyPayload(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    ).copyWith(intendedFor: LinkCodeIntent.coParentInvite);
  }

  // Generate codes for multiple students
  Future<Map<String, StudentLinkCodeModel>> generateBulkCodes({
    required List<String> studentIds,
    required String schoolId,
    required String createdBy,
    int validityDays = 30,
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

  // Verify and retrieve a link code via the server-side callable.
  //
  // Looks the code up by EXACT value server-side (verifyStudentLinkCode) rather
  // than running a client `where('code','==',x)` query. That client query
  // required an unauthenticated `list` rule on studentLinkCodes, which let
  // anyone paginate and harvest every child-link code. The callable returns
  // only the single matching record (no enumeration) and throws the same typed
  // errors the collection path did — mapped by [_mapHttpsError]:
  //   invalid-code → InvalidCodeException, code-used → CodeAlreadyUsedException,
  //   code-revoked → CodeRevokedException, code-expired → CodeExpiredException.
  // Transient `unavailable` surfaces as NetworkUnavailableException (retry).
  Future<StudentLinkCodeModel> verifyCode(String code) async {
    final normalizedCode = code.toUpperCase().trim();
    final raw = await _invokeWithRetry(
      'verifyStudentLinkCode',
      <String, dynamic>{'code': normalizedCode},
    );
    if (raw is! Map) {
      throw InvalidCodeException();
    }
    return StudentLinkCodeModel.fromVerifyPayload(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  // Link parent to student using a code.
  //
  // Atomicity (parents.linkedChildren + students.parentIds + the code's used
  // flag) is enforced server-side by the `linkParentToStudent` callable —
  // firestore.rules forbids client-side writes to parents.linkedChildren and
  // students.parentIds, so this hop is mandatory. Callable bypasses rules via
  // Admin SDK and performs the same transaction the rules wouldn't let us run
  // from the client.
  //
  // `parentEmail` is accepted for source compatibility but ignored — the
  // server derives parent identity from the auth context.
  Future<bool> linkParentToStudent({
    required String code,
    required String parentUserId,
    String? parentEmail,
  }) async {
    assertWritable(
      opLabel: 'parentLinking.linkParentToStudent',
      collection: 'students',
      operation: 'update',
    );
    final normalizedCode = code.toUpperCase().trim();
    await _invokeWithRetry(
      'linkParentToStudent',
      <String, dynamic>{
        'code': normalizedCode,
        'clientInfo': _clientInfo(),
      },
    );
    return true;
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
    assertWritable(
      opLabel: 'parentLinking.revokeCode',
      collection: 'studentLinkCodes',
      docId: codeId,
      operation: 'update',
    );
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

  // Unlink parent from student. Routed through a Cloud Function for the same
  // reason as [linkParentToStudent] — Admin SDK is the only writer permitted
  // to touch parents.linkedChildren and students.parentIds.
  //
  // [unlinkedBy] is accepted for source compatibility but not transmitted;
  // the server derives the caller from auth and authorizes self-unlink or
  // teacher/admin-in-school unlink.
  Future<void> unlinkParentFromStudent({
    required String schoolId,
    required String studentId,
    required String parentUserId,
    String? unlinkedBy,
    String? reason,
  }) async {
    assertWritable(
      opLabel: 'parentLinking.unlinkParentFromStudent',
      collection: 'students',
      docId: studentId,
      operation: 'update',
    );
    await _invokeWithRetry(
      'unlinkParentFromStudent',
      <String, dynamic>{
        'schoolId': schoolId,
        'studentId': studentId,
        'parentUserId': parentUserId,
        if (reason != null) 'reason': reason,
      },
    );
    // Child-scoped cache hygiene (§7.4): after the relationship ends, this
    // device must not retain the child's logs, drafts or queued writes
    // (which the rules would now reject anyway).
    await OfflineService.instance.purgeChildData(studentId);
  }

  // ── Callable plumbing ──

  Map<String, dynamic> _clientInfo() => <String, dynamic>{
        'platform': defaultTargetPlatform.name,
        'appVersion': null,
      };

  /// Invokes [name] once; on `unavailable` waits 1s and retries once before
  /// surfacing [NetworkUnavailableException]. All other FirebaseFunctions
  /// failures route through [_mapHttpsError].
  Future<Object?> _invokeWithRetry(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      return await _invoke(name, args);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable') {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          return await _invoke(name, args);
        } on FirebaseFunctionsException catch (e2) {
          if (e2.code == 'unavailable') {
            throw NetworkUnavailableException();
          }
          throw _mapHttpsError(e2);
        }
      }
      throw _mapHttpsError(e);
    }
  }

  /// Translates the server's structured HttpsError payloads (code +
  /// details.kind) into the local [LinkingException] hierarchy used by the
  /// existing UI. See functions/src/parent_linking.ts for the source of these
  /// kinds.
  LinkingException _mapHttpsError(FirebaseFunctionsException e) {
    final details = e.details;
    String? kind;
    String? reason;
    if (details is Map) {
      final asMap = details.cast<Object?, Object?>();
      final rawKind = asMap['kind'];
      if (rawKind is String) kind = rawKind;
      final rawReason = asMap['reason'];
      if (rawReason is String) reason = rawReason;
    }

    switch (e.code) {
      case 'failed-precondition':
        switch (kind) {
          case 'invalid-code':
            return InvalidCodeException();
          case 'code-used':
            return CodeAlreadyUsedException();
          case 'code-revoked':
            return CodeRevokedException(reason: reason);
          case 'code-expired':
            return CodeExpiredException();
          case 'parent-doc-missing':
            return ParentDocumentNotFoundException();
          case 'not-linked':
            return TransactionFailedException(
                e.message ?? 'Parent is not linked to this student.');
        }
        return TransactionFailedException(e.message ?? 'failed-precondition');
      case 'already-exists':
        if (kind == 'already-linked') return AlreadyLinkedException();
        return TransactionFailedException(e.message ?? 'already-exists');
      case 'not-found':
        if (kind == 'student-missing') return StudentNotFoundException();
        return TransactionFailedException(e.message ?? 'not-found');
      case 'resource-exhausted':
        return TransactionFailedException(
            e.message ?? 'Link rate limit reached.');
      case 'unauthenticated':
      case 'permission-denied':
        return TransactionFailedException(e.message ?? e.code);
      default:
        return TransactionFailedException('${e.code}: ${e.message ?? ''}');
    }
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
