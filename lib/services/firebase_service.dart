import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();

  FirebaseService._();

  // Firebase instances
  late final FirebaseAuth _auth;
  late final FirebaseFirestore _firestore;
  late final FirebaseStorage _storage;
  late final FirebaseMessaging? _messaging;

  // Getters
  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;
  FirebaseStorage get storage => _storage;
  FirebaseMessaging? get messaging => _messaging;

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

      // Firebase Messaging is not fully supported on web
      if (!kIsWeb) {
        _messaging = FirebaseMessaging.instance;
      }

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

      // Request notification permissions (mobile only)
      if (!kIsWeb) {
        await _requestNotificationPermissions();
        await _setupMessageHandlers();
      }

      debugPrint('Firebase services initialized successfully');
    } catch (e) {
      debugPrint('Error initializing Firebase services: $e');
      rethrow;
    }
  }

  // Request notification permissions
  Future<void> _requestNotificationPermissions() async {
    if (_messaging == null) return;

    try {
      final settings = await _messaging!.requestPermission(
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

        // Get FCM token (skip on iOS Simulator as APNS is not available)
        try {
          final token = await _messaging!.getToken();
          if (token != null) {
            debugPrint('FCM Token: $token');
            // Save token to user profile
            await _saveFCMToken(token);
          }

          // Listen to token refresh
          _messaging!.onTokenRefresh.listen(_saveFCMToken);
        } catch (tokenError) {
          // APNS token not available on iOS Simulator - this is expected
          if (tokenError.toString().contains('apns-token-not-set')) {
            debugPrint('APNS not available (iOS Simulator) - notifications will work on physical devices');
          } else {
            debugPrint('Error getting FCM token: $tokenError');
          }
        }
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
    if (_messaging == null) return;

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
        // Handle notification display
        _handleForegroundNotification(message);
      }
    });

    // Handle notification taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      // Handle navigation based on message data
      _handleNotificationTap(message);
    });

    // Check if app was opened from a notification
    final initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from notification');
      _handleNotificationTap(initialMessage);
    }
  }

  // Save FCM token to user profile
  Future<void> _saveFCMToken(String token) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  // Handle foreground notification
  void _handleForegroundNotification(RemoteMessage message) {
    // Implement local notification display
    // This will be handled by the notification service
  }

  // Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    // Navigate based on message data
    final data = message.data;
    if (data['type'] == 'reading_reminder') {
      // Navigate to reading log screen
    } else if (data['type'] == 'teacher_message') {
      // Navigate to messages screen
    }
    // Add more navigation logic as needed
  }

  // Sign out
  Future<void> signOut() async {
    try {
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

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Handling a background message: ${message.messageId}');
  // Handle background message
}