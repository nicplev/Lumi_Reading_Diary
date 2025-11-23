import 'package:cloud_firestore/cloud_firestore.dart';
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

    // Query for the code
    final querySnapshot = await _firestore
        .collection(_collectionName)
        .where('code', isEqualTo: normalizedCode)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw SchoolCodeException(
        'Invalid school code. Please check the code and try again.',
        'code_not_found',
      );
    }

    final codeDoc = querySnapshot.docs.first;
    final schoolCode = SchoolCodeModel.fromFirestore(codeDoc);

    // Check if code is valid
    if (!schoolCode.isValid) {
      throw SchoolCodeException(
        schoolCode.invalidReason ?? 'This school code is no longer valid',
        'code_invalid',
      );
    }

    return {
      'schoolId': schoolCode.schoolId,
      'schoolName': schoolCode.schoolName,
      'codeId': schoolCode.id,
    };
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
    await _firestore
        .collection(_collectionName)
        .doc(codeId)
        .update({'isActive': false});
  }

  /// Reactivates a previously deactivated code
  Future<void> reactivateCode(String codeId) async {
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
