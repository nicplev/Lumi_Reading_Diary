import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/data/repositories/user_repository.dart';

// Mock FirebaseAuth
final mockFirebaseAuth = MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(
    isAnonymous: false,
    uid: 'some_uid',
    email: 'test@example.com',
    displayName: 'Test User',
  ),
);

// Mock GoogleSignIn
final mockGoogleSignIn = MockGoogleSignIn();

// Mock Firestore
final fakeFirestore = FakeFirebaseFirestore();

final mockUser = UserModel(
  id: 'some_uid',
  email: 'test@example.com',
  fullName: 'Test User',
  role: UserRole.parent,
  createdAt: DateTime.now(),
);

class MockUserRepository implements UserRepository {
  @override
  Future<UserModel?> getUser(String uid) async {
    if (uid == 'some_uid') {
      return mockUser;
    }
    return null;
  }

  @override
  FirebaseFirestore get _firestore => fakeFirestore;
}
