import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'offline_service.dart';
import 'notification_service.dart';

class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();

  FirebaseService._();

  // Firebase instances
  late final FirebaseAuth _auth;
  late final FirebaseFirestore _firestore;
  late final FirebaseStorage _storage;

  // Getters
  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;
  FirebaseStorage get storage => _storage;

  // Current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // Initialize Firebase
  Future<void> initialize() async {
    try {
      // Initialize Firebase services
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      _storage = FirebaseStorage.instance;

      // Configure Firestore settings
      // Note: cacheSizeBytes is not supported on web and can cause write failures
      if (kIsWeb) {
        // Web uses default settings (persistence enabled by default via IndexedDB)
        _firestore.settings = const Settings(
          persistenceEnabled: true,
        );
      } else {
        // Mobile supports full persistence configuration
        _firestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      }

      debugPrint('Firebase services initialized successfully');
    } catch (e) {
      debugPrint('Error initializing Firebase services: $e');
      rethrow;
    }
  }

  // Get reading logs for a student within a date range
  Future<List<dynamic>> getReadingLogsForStudent(
    String studentId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore
          .collection('readingLogs')
          .where('studentId', isEqualTo: studentId);

      if (startDate != null) {
        query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }

      if (endDate != null) {
        query = query.where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      final snapshot = await query.orderBy('date', descending: true).get();

      // Return documents as dynamic to allow conversion in calling code
      return snapshot.docs;
    } catch (e) {
      debugPrint('Error fetching reading logs for student: $e');
      rethrow;
    }
  }

  // Get all students in a class
  Future<List<dynamic>> getStudentsInClass(String classId) async {
    try {
      final snapshot = await _firestore
          .collection('students')
          .where('classId', isEqualTo: classId)
          .where('isActive', isEqualTo: true)
          .get();

      // Return documents as dynamic to allow conversion in calling code
      return snapshot.docs;
    } catch (e) {
      debugPrint('Error fetching students in class: $e');
      rethrow;
    }
  }

  // Clear FCM token from Firestore on logout
  // Delegates to NotificationService which knows the correct Firestore path
  Future<void> _clearFCMToken() async {
    try {
      await NotificationService.instance.clearTokenForUser();
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }
  }

  // Send email verification to current user
  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        debugPrint('Verification email sent');
      }
    } catch (e) {
      debugPrint('Error sending verification email: $e');
    }
  }

  // Check if current user's email is verified
  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // Sign out and clear local caches
  Future<void> signOut() async {
    try {
      // Clear FCM token from Firestore before signing out
      await _clearFCMToken();
      // Clear offline caches
      await OfflineService.instance.clearAllCaches();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
      rethrow;
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Delete user data from Firestore
        await _firestore.collection('users').doc(user.uid).delete();

        // Delete user account
        await user.delete();
      }
    } catch (e) {
      debugPrint('Error deleting account: $e');
      rethrow;
    }
  }
}

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService.instance;
});

