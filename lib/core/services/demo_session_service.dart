import 'package:firebase_auth/firebase_auth.dart';

/// Reads only the server-issued demo capability. Client UI may use this to
/// choose a school-local path, but Firestore/Storage Rules remain the authority.
class DemoSessionService {
  const DemoSessionService._();

  static Future<bool> isDemoAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult();
      return token.claims?['demoAccount'] == true;
    } catch (_) {
      // Fail closed: callers will attempt the ordinary path and Rules will
      // still deny any forbidden global write.
      return false;
    }
  }
}
