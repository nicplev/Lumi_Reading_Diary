import 'package:firebase_auth/firebase_auth.dart';

class DemoSessionContext {
  const DemoSessionContext({
    required this.schoolId,
    required this.generationId,
  });

  final String schoolId;
  final String generationId;
}

/// Reads only the server-issued demo capability. Client UI may use this to
/// choose a school-local path, but Firestore/Storage Rules remain the authority.
class DemoSessionService {
  const DemoSessionService._();

  static Future<DemoSessionContext?> currentContext({
    bool forceRefresh = false,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final token = await user.getIdTokenResult(forceRefresh);
      final claims = token.claims;
      final schoolId = claims?['demoSchoolId'];
      final generationId = claims?['demoGenerationId'];
      if (claims?['demoAccount'] == true &&
          schoolId is String &&
          schoolId.isNotEmpty &&
          generationId is String &&
          generationId.isNotEmpty) {
        return DemoSessionContext(
          schoolId: schoolId,
          generationId: generationId,
        );
      }
    } catch (_) {
      // Fail closed. Rules independently verify the same generation claim.
    }
    return null;
  }

  static Future<bool> isDemoAccount() async {
    return await currentContext() != null;
  }
}
