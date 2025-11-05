import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Updated Firebase Service with nested school-based structure
///
/// NEW STRUCTURE:
/// /schools/{schoolId}/
///   - info (document with school details)
///   - /users/{userId} (staff, admin, teachers)
///   - /students/{studentId}
///   - /classes/{classId}
///   - /parents/{parentId}
///   - /readingLogs/{logId}
class FirebaseServiceV2 {
  static FirebaseServiceV2? _instance;
  static FirebaseServiceV2 get instance => _instance ??= FirebaseServiceV2._();

  FirebaseServiceV2._();

  // Firebase instances
  late final FirebaseAuth _auth;
  late final FirebaseFirestore _firestore;
  late final FirebaseStorage _storage;
  late final FirebaseMessaging _messaging;

  // Getters
  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;
  FirebaseStorage get storage => _storage;
  FirebaseMessaging get messaging => _messaging;

  // Current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // Track if we're using new structure
  bool _useNestedStructure = true;
  bool get useNestedStructure => _useNestedStructure;
  set useNestedStructure(bool value) => _useNestedStructure = value;

  // Initialize Firebase
  Future<void> initialize() async {
    try {
      // Initialize Firebase services
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      _storage = FirebaseStorage.instance;
      _messaging = FirebaseMessaging.instance;

      // Configure Firestore settings
      _firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // Request notification permissions
      await _requestNotificationPermissions();

      // Setup message handlers
      await _setupMessageHandlers();

      debugPrint('Firebase services V2 initialized successfully');
    } catch (e) {
      debugPrint('Error initializing Firebase services: $e');
      rethrow;
    }
  }

  // === COLLECTION REFERENCES ===

  /// Get reference to schools collection
  CollectionReference<Map<String, dynamic>> get schoolsCollection =>
      _firestore.collection('schools');

  /// Get reference to a specific school
  DocumentReference<Map<String, dynamic>> schoolDoc(String schoolId) =>
      schoolsCollection.doc(schoolId);

  /// Get users collection (nested or flat based on configuration)
  CollectionReference<Map<String, dynamic>> usersCollection({String? schoolId}) {
    if (_useNestedStructure && schoolId != null) {
      return schoolDoc(schoolId).collection('users');
    }
    return _firestore.collection('users');
  }

  /// Get students collection (nested or flat)
  CollectionReference<Map<String, dynamic>> studentsCollection({String? schoolId}) {
    if (_useNestedStructure && schoolId != null) {
      return schoolDoc(schoolId).collection('students');
    }
    return _firestore.collection('students');
  }

  /// Get classes collection (nested or flat)
  CollectionReference<Map<String, dynamic>> classesCollection({String? schoolId}) {
    if (_useNestedStructure && schoolId != null) {
      return schoolDoc(schoolId).collection('classes');
    }
    return _firestore.collection('classes');
  }

  /// Get parents collection (nested or flat)
  CollectionReference<Map<String, dynamic>> parentsCollection({String? schoolId}) {
    if (_useNestedStructure && schoolId != null) {
      return schoolDoc(schoolId).collection('parents');
    }
    // Parents are stored in users collection in old structure
    return _firestore.collection('users');
  }

  /// Get reading logs collection (nested or flat)
  CollectionReference<Map<String, dynamic>> readingLogsCollection({String? schoolId}) {
    if (_useNestedStructure && schoolId != null) {
      return schoolDoc(schoolId).collection('readingLogs');
    }
    return _firestore.collection('readingLogs');
  }

  // === USER OPERATIONS ===

  /// Get user by ID
  Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String userId, {String? schoolId}) async {
    if (_useNestedStructure && schoolId != null) {
      // Try users collection first
      final userDoc = await usersCollection(schoolId: schoolId).doc(userId).get();
      if (userDoc.exists) return userDoc;

      // Try parents collection if not found in users
      final parentDoc = await parentsCollection(schoolId: schoolId).doc(userId).get();
      if (parentDoc.exists) return parentDoc;

      throw Exception('User not found');
    }

    // Flat structure
    return await _firestore.collection('users').doc(userId).get();
  }

  /// Get user stream by ID
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserStream(String userId, {String? schoolId}) {
    if (_useNestedStructure && schoolId != null) {
      // For nested structure, we need to check both users and parents collections
      // This is a limitation - we'll return users collection by default
      // In production, you should know the user's role beforehand
      return usersCollection(schoolId: schoolId).doc(userId).snapshots();
    }

    return _firestore.collection('users').doc(userId).snapshots();
  }

  /// Get all users for a school
  Stream<QuerySnapshot<Map<String, dynamic>>> getUsersForSchool(String schoolId, {String? role}) {
    Query<Map<String, dynamic>> query;

    if (_useNestedStructure) {
      query = usersCollection(schoolId: schoolId);
    } else {
      query = _firestore.collection('users').where('schoolId', isEqualTo: schoolId);
    }

    if (role != null) {
      query = query.where('role', isEqualTo: role);
    }

    return query.snapshots();
  }

  // === STUDENT OPERATIONS ===

  /// Get all students for a school
  Stream<QuerySnapshot<Map<String, dynamic>>> getStudentsForSchool(String schoolId) {
    if (_useNestedStructure) {
      return studentsCollection(schoolId: schoolId).snapshots();
    }

    return _firestore
        .collection('students')
        .where('schoolId', isEqualTo: schoolId)
        .snapshots();
  }

  /// Get student by ID
  Future<DocumentSnapshot<Map<String, dynamic>>> getStudent(String studentId, String schoolId) async {
    return await studentsCollection(schoolId: schoolId).doc(studentId).get();
  }

  // === CLASS OPERATIONS ===

  /// Get all classes for a school
  Stream<QuerySnapshot<Map<String, dynamic>>> getClassesForSchool(String schoolId) {
    if (_useNestedStructure) {
      return classesCollection(schoolId: schoolId).snapshots();
    }

    return _firestore
        .collection('classes')
        .where('schoolId', isEqualTo: schoolId)
        .snapshots();
  }

  /// Get class by ID
  Future<DocumentSnapshot<Map<String, dynamic>>> getClass(String classId, String schoolId) async {
    return await classesCollection(schoolId: schoolId).doc(classId).get();
  }

  /// Create a new class
  Future<DocumentReference<Map<String, dynamic>>> createClass(
    Map<String, dynamic> classData,
    String schoolId,
  ) async {
    // Remove schoolId from data if using nested structure
    if (_useNestedStructure) {
      classData.remove('schoolId');
    } else {
      classData['schoolId'] = schoolId;
    }

    classData['createdAt'] = FieldValue.serverTimestamp();
    classData['updatedAt'] = FieldValue.serverTimestamp();

    return await classesCollection(schoolId: schoolId).add(classData);
  }

  /// Update a class
  Future<void> updateClass(String classId, Map<String, dynamic> data, String schoolId) async {
    data['updatedAt'] = FieldValue.serverTimestamp();

    if (_useNestedStructure) {
      data.remove('schoolId');
    }

    await classesCollection(schoolId: schoolId).doc(classId).update(data);
  }

  /// Delete a class
  Future<void> deleteClass(String classId, String schoolId) async {
    await classesCollection(schoolId: schoolId).doc(classId).delete();
  }

  // === READING LOG OPERATIONS ===

  /// Get reading logs for a student
  Stream<QuerySnapshot<Map<String, dynamic>>> getReadingLogsForStudent(
    String studentId,
    String schoolId,
  ) {
    if (_useNestedStructure) {
      return readingLogsCollection(schoolId: schoolId)
          .where('studentId', isEqualTo: studentId)
          .orderBy('date', descending: true)
          .snapshots();
    }

    return _firestore
        .collection('readingLogs')
        .where('studentId', isEqualTo: studentId)
        .orderBy('date', descending: true)
        .snapshots();
  }

  /// Create a reading log
  Future<DocumentReference<Map<String, dynamic>>> createReadingLog(
    Map<String, dynamic> logData,
    String schoolId,
  ) async {
    logData['createdAt'] = FieldValue.serverTimestamp();

    return await readingLogsCollection(schoolId: schoolId).add(logData);
  }

  // === AUTHENTICATION ===

  /// Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Create user with email and password
  Future<UserCredential> createUserWithEmailAndPassword(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Reset password
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // === HELPER METHODS ===

  /// Get user's school ID from their profile
  Future<String?> getUserSchoolId(String userId) async {
    try {
      // First check if we can find them in any school's users collection
      if (_useNestedStructure) {
        // This is inefficient - in production, you should cache this info
        final schools = await schoolsCollection.get();
        for (final school in schools.docs) {
          final userDoc = await usersCollection(schoolId: school.id)
              .doc(userId)
              .get();
          if (userDoc.exists) return school.id;

          final parentDoc = await parentsCollection(schoolId: school.id)
              .doc(userId)
              .get();
          if (parentDoc.exists) return school.id;
        }
      } else {
        // Flat structure
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          return userDoc.data()?['schoolId'];
        }
      }
    } catch (e) {
      debugPrint('Error getting user school ID: $e');
    }
    return null;
  }

  /// Save FCM token
  Future<void> _saveFCMToken(String token) async {
    final user = _auth.currentUser;
    if (user != null) {
      final schoolId = await getUserSchoolId(user.uid);
      if (schoolId != null) {
        await getUser(user.uid, schoolId: schoolId).then((doc) async {
          if (doc.exists) {
            final isParent = doc.data()?['role'] == 'parent';
            final collection = isParent
                ? parentsCollection(schoolId: schoolId)
                : usersCollection(schoolId: schoolId);

            await collection.doc(user.uid).update({
              'fcmToken': token,
              'lastTokenUpdate': FieldValue.serverTimestamp(),
            });
          }
        });
      }
    }
  }

  // Request notification permissions
  Future<void> _requestNotificationPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted permission for notifications');

        // Get FCM token
        final token = await _messaging.getToken();
        if (token != null) {
          debugPrint('FCM Token: $token');
          // Save token to user profile
          await _saveFCMToken(token);
        }

        // Listen to token refresh
        _messaging.onTokenRefresh.listen(_saveFCMToken);
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('User granted provisional permission');
      } else {
        debugPrint('User declined or has not accepted permission');
      }
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
    }
  }

  // Setup message handlers
  Future<void> _setupMessageHandlers() async {
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
      }
    });
  }
}

// Background message handler - must be top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Handling a background message: ${message.messageId}');
}