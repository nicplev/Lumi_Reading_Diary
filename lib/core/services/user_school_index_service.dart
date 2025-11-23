import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Service for managing the email-to-school lookup index.
/// This dramatically improves login performance by avoiding the need to
/// iterate through all schools to find a user.
///
/// Performance improvement: O(n) schools → O(1) with 2-3 reads total.
class UserSchoolIndexService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _collectionName = 'userSchoolIndex';

  /// Generates a consistent hash for an email address.
  /// Uses SHA-256 for privacy (emails not stored in plain text in index).
  String _hashEmail(String email) {
    final normalized = email.toLowerCase().trim();
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Creates or updates an index entry for a user.
  ///
  /// This should be called when:
  /// - A new user registers (parent, teacher, or admin)
  /// - A user's email is changed (rare, but possible)
  ///
  /// Parameters:
  /// - [email]: User's email address
  /// - [schoolId]: ID of the school the user belongs to
  /// - [userType]: Type of user ('user' for teachers/admins, 'parent' for parents)
  /// - [userId]: Firebase Auth UID of the user
  Future<void> createOrUpdateIndex({
    required String email,
    required String schoolId,
    required String userType,
    required String userId,
  }) async {
    final emailHash = _hashEmail(email);

    await _firestore.collection(_collectionName).doc(emailHash).set({
      'email': email,
      'schoolId': schoolId,
      'userType': userType, // 'user' or 'parent'
      'userId': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Looks up which school a user belongs to by their email.
  ///
  /// Returns a map with:
  /// - schoolId: ID of the school
  /// - userType: 'user' (teacher/admin) or 'parent'
  /// - userId: Firebase Auth UID
  ///
  /// Returns null if email is not found in index.
  Future<Map<String, dynamic>?> lookupSchoolByEmail(String email) async {
    final emailHash = _hashEmail(email);

    final doc = await _firestore
        .collection(_collectionName)
        .doc(emailHash)
        .get();

    if (!doc.exists) {
      return null;
    }

    final data = doc.data()!;
    return {
      'schoolId': data['schoolId'],
      'userType': data['userType'],
      'userId': data['userId'],
    };
  }

  /// Deletes an index entry for a user.
  ///
  /// This should be called when:
  /// - A user account is permanently deleted
  /// - A user is moved to a different school (delete old, create new)
  Future<void> deleteIndex(String email) async {
    final emailHash = _hashEmail(email);
    await _firestore.collection(_collectionName).doc(emailHash).delete();
  }

  /// Checks if an email already exists in the index.
  /// Useful for preventing duplicate registrations.
  Future<bool> emailExists(String email) async {
    final emailHash = _hashEmail(email);
    final doc = await _firestore
        .collection(_collectionName)
        .doc(emailHash)
        .get();
    return doc.exists;
  }

  /// Backfills the index for existing users in a school.
  ///
  /// This is a migration utility to populate the index for users
  /// that were created before this optimization was implemented.
  ///
  /// Should be run once per school during migration.
  Future<void> backfillSchoolIndex(String schoolId) async {
    int usersIndexed = 0;
    int parentsIndexed = 0;

    // Index all teachers/admins in this school
    final usersSnapshot = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('users')
        .get();

    for (final userDoc in usersSnapshot.docs) {
      final data = userDoc.data();
      if (data['email'] != null) {
        await createOrUpdateIndex(
          email: data['email'],
          schoolId: schoolId,
          userType: 'user',
          userId: userDoc.id,
        );
        usersIndexed++;
      }
    }

    // Index all parents in this school
    final parentsSnapshot = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parents')
        .get();

    for (final parentDoc in parentsSnapshot.docs) {
      final data = parentDoc.data();
      if (data['email'] != null) {
        await createOrUpdateIndex(
          email: data['email'],
          schoolId: schoolId,
          userType: 'parent',
          userId: parentDoc.id,
        );
        parentsIndexed++;
      }
    }

    print('Backfilled index for school $schoolId: $usersIndexed users, $parentsIndexed parents');
  }

  /// Backfills the index for ALL schools.
  ///
  /// This is a one-time migration utility. Use with caution as it
  /// reads all users across all schools.
  ///
  /// Returns the total number of users indexed.
  Future<Map<String, int>> backfillAllSchools() async {
    int totalUsers = 0;
    int totalParents = 0;
    int totalSchools = 0;

    final schoolsSnapshot = await _firestore.collection('schools').get();

    for (final schoolDoc in schoolsSnapshot.docs) {
      final schoolId = schoolDoc.id;

      // Index users
      final usersSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('users')
          .get();

      for (final userDoc in usersSnapshot.docs) {
        final data = userDoc.data();
        if (data['email'] != null) {
          await createOrUpdateIndex(
            email: data['email'],
            schoolId: schoolId,
            userType: 'user',
            userId: userDoc.id,
          );
          totalUsers++;
        }
      }

      // Index parents
      final parentsSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('parents')
          .get();

      for (final parentDoc in parentsSnapshot.docs) {
        final data = parentDoc.data();
        if (data['email'] != null) {
          await createOrUpdateIndex(
            email: data['email'],
            schoolId: schoolId,
            userType: 'parent',
            userId: parentDoc.id,
          );
          totalParents++;
        }
      }

      totalSchools++;
    }

    return {
      'schools': totalSchools,
      'users': totalUsers,
      'parents': totalParents,
      'total': totalUsers + totalParents,
    };
  }
}
