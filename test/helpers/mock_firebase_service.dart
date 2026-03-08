import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:lumi_reading_tracker/services/firebase_service.dart';
import 'package:mockito/mockito.dart';

class MockFirebaseService extends Mock implements FirebaseService {
  final MockFirebaseAuth _mockAuth;

  MockFirebaseService({MockFirebaseAuth? mockAuth})
      : _mockAuth = mockAuth ?? MockFirebaseAuth();

  @override
  Future<void> initialize() async {
    // No-op for mock
  }

  @override
  Stream<User?> get authStateChanges => _mockAuth.authStateChanges();

  @override
  FirebaseAuth get auth => _mockAuth;
}

