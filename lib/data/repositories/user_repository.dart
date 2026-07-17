import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../../core/services/user_school_index_service.dart';
import '../../core/exceptions/session_exceptions.dart';

class UserRepository {
  final FirebaseFirestore _firestore;

  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Gets a user by UID, checking school subcollections via the email index
  /// (or phone index for phone-only accounts), then falling back to the
  /// top-level users collection.
  Future<UserModel?> getUser(String uid) async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final indexService = UserSchoolIndexService();

      Map<String, dynamic>? indexResult;
      if (firebaseUser?.email != null) {
        indexResult =
            await indexService.lookupSchoolByEmail(firebaseUser!.email!);
      }
      // Phone-only fallback: parents who registered without an email don't
      // have an email-hash record, but they do have a phone-hash record.
      if (indexResult == null && firebaseUser?.phoneNumber != null) {
        indexResult =
            await indexService.lookupSchoolByPhone(firebaseUser!.phoneNumber!);
      }

      if (indexResult != null) {
        final schoolId = indexResult['schoolId'] as String;
        final userType = indexResult['userType'] as String;
        final collection = userType == 'parent' ? 'parents' : 'users';

        final doc = await _firestore
            .collection('schools')
            .doc(schoolId)
            .collection(collection)
            .doc(uid)
            .get();

        if (doc.exists) {
          return UserModel.fromFirestore(doc);
        }
      }

      // Fallback: top-level users collection (legacy)
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
    } on FirebaseException catch (e) {
      if (isInvalidOwnProfileSessionError(e)) {
        throw const InvalidUserSessionException();
      }
      // Preserve the difference between "no profile" and "could not check".
      // Callers keep the current screen and offer retry for transient service
      // failures instead of dumping a valid user onto the login route.
      rethrow;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Direct lookup bypassing the email/school index — reads exactly
  /// `schools/{schoolId}/users/{uid}`. Used by the developer impersonation
  /// flow where the caller already knows the target school and user and the
  /// index lookup (which keys on the signed-in user's email) would miss.
  Future<UserModel?> getUserInSchool(String schoolId, String uid) async {
    try {
      final doc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists) return UserModel.fromFirestore(doc);
    } catch (_) {
      // Swallow: caller treats null as "not found / no access".
    }
    return null;
  }
}
