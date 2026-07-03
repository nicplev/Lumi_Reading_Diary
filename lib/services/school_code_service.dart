import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/services/assert_writable.dart';
import '../core/services/functions_instance.dart';
import '../data/models/school_code_model.dart';

/// Exception thrown when school code validation fails
class SchoolCodeException implements Exception {
  final String message;
  final String code;

  SchoolCodeException(this.message, this.code);

  @override
  String toString() => message;
}

/// Service for validating and managing school registration codes
class SchoolCodeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _collectionName = 'schoolCodes';

  /// Validates a school code and returns the associated school details
  ///
  /// Throws [SchoolCodeException] if:
  /// - Code doesn't exist
  /// - Code is inactive
  /// - Code has expired
  /// - Code has reached maximum usages
  ///
  /// Returns a map with:
  /// - schoolId: The ID of the school
  /// - schoolName: The name of the school
  /// - codeId: The ID of the code document (for tracking usage)
  Future<Map<String, String>> validateSchoolCode(String code) async {
    // Normalize code (uppercase, trim whitespace)
    final normalizedCode = code.toUpperCase().trim();

    if (normalizedCode.isEmpty) {
      throw SchoolCodeException(
        'School code cannot be empty',
        'empty_code',
      );
    }

    if (normalizedCode.length < 6) {
      throw SchoolCodeException(
        'School code must be at least 6 characters',
        'code_too_short',
      );
    }

    // Verify server-side by EXACT code (verifySchoolCode callable). Replaces
    // the client `where('code','==',x)` query, which required an unauthenticated
    // `list` rule on schoolCodes that let anyone paginate and harvest every
    // active join code. The callable mirrors SchoolCodeModel.isValid /
    // invalidReason and returns only the single matching school.
    try {
      final callable = lumiFunctions.httpsCallable('verifySchoolCode');
      final result =
          await callable.call<Object?>(<String, dynamic>{'code': normalizedCode});
      final data = result.data;
      if (data is! Map) {
        throw SchoolCodeException(
          'This school code is no longer valid',
          'code_invalid',
        );
      }
      final map = data.map((key, value) => MapEntry(key.toString(), value));
      return {
        'schoolId': (map['schoolId'] as String?) ?? '',
        'schoolName': (map['schoolName'] as String?) ?? '',
        'codeId': (map['codeId'] as String?) ?? '',
      };
    } on FirebaseFunctionsException catch (e) {
      // Transient network: let the caller's FirebaseException handler surface
      // the offline message (FirebaseFunctionsException is a FirebaseException).
      if (e.code == 'unavailable') rethrow;
      final details = e.details;
      String? kind;
      if (details is Map) {
        final rawKind = details['kind'];
        if (rawKind is String) kind = rawKind;
      }
      // The callable's HttpsError message is already the friendly, user-facing
      // text (mirrors invalidReason / the not-found copy).
      throw SchoolCodeException(
        e.message ?? 'This school code is no longer valid',
        kind ?? 'code_invalid',
      );
    }
  }

  /// Increments the usage count for a school code
  ///
  /// This should be called after successfully creating a teacher account
  /// to track how many times a code has been used.
  Future<void> incrementCodeUsage(String codeId) async {
    await _firestore
        .collection(_collectionName)
        .doc(codeId)
        .update({
      'usageCount': FieldValue.increment(1),
    });
  }

  /// Creates a new school code
  ///
  /// This is typically called by school admins to generate codes for their teachers.
  ///
  /// Parameters:
  /// - [code]: The code string (will be converted to uppercase)
  /// - [schoolId]: The ID of the school
  /// - [schoolName]: The name of the school
  /// - [createdBy]: The UID of the admin creating the code
  /// - [expiresAt]: Optional expiration date
  /// - [maxUsages]: Optional maximum number of times code can be used
  Future<String> createSchoolCode({
    required String code,
    required String schoolId,
    required String schoolName,
    required String createdBy,
    DateTime? expiresAt,
    int? maxUsages,
  }) async {
    assertWritable(
      opLabel: 'schoolCode.createSchoolCode',
      collection: 'schoolCodes',
      operation: 'create',
    );
    final normalizedCode = code.toUpperCase().trim();

    // Check if code already exists
    final existing = await _firestore
        .collection(_collectionName)
        .where('code', isEqualTo: normalizedCode)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw SchoolCodeException(
        'This code already exists. Please use a different code.',
        'code_exists',
      );
    }

    final schoolCode = SchoolCodeModel(
      id: '', // Will be set by Firestore
      code: normalizedCode,
      schoolId: schoolId,
      schoolName: schoolName,
      isActive: true,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      createdBy: createdBy,
      usageCount: 0,
      maxUsages: maxUsages,
    );

    final docRef = await _firestore
        .collection(_collectionName)
        .add(schoolCode.toFirestore());

    return docRef.id;
  }

  /// Deactivates a school code
  ///
  /// This prevents the code from being used for new registrations
  /// but doesn't affect teachers who already registered with it.
  Future<void> deactivateCode(String codeId) async {
    assertWritable(
      opLabel: 'schoolCode.deactivateCode',
      collection: 'schoolCodes',
      docId: codeId,
      operation: 'update',
    );
    await _firestore
        .collection(_collectionName)
        .doc(codeId)
        .update({'isActive': false});
  }

  /// Reactivates a previously deactivated code
  Future<void> reactivateCode(String codeId) async {
    assertWritable(
      opLabel: 'schoolCode.reactivateCode',
      collection: 'schoolCodes',
      docId: codeId,
      operation: 'update',
    );
    await _firestore
        .collection(_collectionName)
        .doc(codeId)
        .update({'isActive': true});
  }

  /// Gets all school codes for a specific school
  ///
  /// Useful for school admins to view their codes
  Future<List<SchoolCodeModel>> getSchoolCodes(String schoolId) async {
    final querySnapshot = await _firestore
        .collection(_collectionName)
        .where('schoolId', isEqualTo: schoolId)
        .orderBy('createdAt', descending: true)
        .get();

    return querySnapshot.docs
        .map((doc) => SchoolCodeModel.fromFirestore(doc))
        .toList();
  }
}
