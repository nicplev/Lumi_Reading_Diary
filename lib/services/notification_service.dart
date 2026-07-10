import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/functions_instance.dart';
import '../core/services/impersonation_service.dart';
import '../data/models/user_model.dart';
import '../data/providers/active_child_provider.dart';
import '../firebase_options.dart';

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Handling a background message: ${message.messageId}');
}

/// Smart notification service for Lumi Reading Diary
/// Single owner of all notification/FCM logic (push + local + scheduled)
class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();

  NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _messaging;
  bool _initialized = false;

  // Stored so token refresh can persist to the correct parent document
  String? _currentSchoolId;
  String? _currentUserId;

  // Token that refreshed before user context was available — flushed on next saveTokenForUser call
  String? _pendingToken;

  // Router reference for in-app navigation on notification tap
  GoRouter? _router;
  // Route buffered when a notification tap arrives before the router is ready (cold-start)
  String? _pendingRoute;

  // Notification channels
  static const String _readingReminderChannel = 'reading_reminders';
  static const String _achievementChannel = 'achievements';
  static const String _generalChannel = 'general';

  /// Wire in the GoRouter instance so notification taps can navigate.
  /// Called from routerProvider after the router is built.
  void setRouter(GoRouter router) {
    _router = router;
    if (_pendingRoute != null) {
      final route = _pendingRoute!;
      _pendingRoute = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _router?.go(route);
      });
    }
  }

  void _navigateTo(String route) {
    if (_router != null) {
      _router!.go(route);
    } else {
      // Router not ready yet (cold-start race) — flush in setRouter()
      _pendingRoute = route;
    }
  }

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize timezone data for scheduled notifications
      tz.initializeTimeZones();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Sweep any reminders left over from the old client-side scheduler.
      // Cheap no-op for users on a fresh install or who already upgraded.
      await cancelAllReminders();

      // Initialize Firebase Messaging (mobile only)
      if (!kIsWeb) {
        await _initializeFirebaseMessaging();
      }

      _initialized = true;
      debugPrint('Notification service initialized');
    } catch (e) {
      debugPrint('Error initializing notification service: $e');
      _initialized = false;
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      // iOS 14+ ignores the legacy alert flag; banner/list are what actually
      // make a foreground local notification visible (e.g. the "push
      // unavailable" preview fallback).
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Create notification channels (Android)
    if (!kIsWeb && Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  /// Create Android notification channels
  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // Reading reminder channel
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _readingReminderChannel,
        'Reading Reminders',
        description: 'Daily reminders to log reading',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Achievement channel
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _achievementChannel,
        'Achievements',
        description: 'Achievement unlock notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      ),
    );

    // General channel
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _generalChannel,
        'General',
        description: 'General app notifications',
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// Initialize Firebase Messaging
  Future<void> _initializeFirebaseMessaging() async {
    _messaging = FirebaseMessaging.instance;

    // Register background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission (iOS + Android 13+)
    try {
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('Notification permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }

    // iOS suppresses system banners for pushes arriving while the app is in
    // the foreground unless we opt in. Let the OS present the original FCM
    // notification natively (banner + Notification Centre + sound); Android
    // gets no system banner for foreground FCM, so it keeps the local
    // re-show in _handleForegroundMessage instead.
    if (!kIsWeb && Platform.isIOS) {
      try {
        await _messaging!.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (e) {
        debugPrint('Error setting foreground presentation options: $e');
      }
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // Check for message that opened the app (can hang on iOS 26)
    try {
      final initialMessage = await _messaging!
          .getInitialMessage()
          .timeout(const Duration(seconds: 3));
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }
    } catch (e) {
      debugPrint('getInitialMessage timed out or failed: $e');
    }

    // Listen for token refresh and persist to the correct parent document.
    // If user context isn't set yet, buffer the token and flush it in saveTokenForUser.
    _messaging!.onTokenRefresh.listen((token) {
      if (_currentSchoolId != null && _currentUserId != null) {
        _persistToken(token, _currentSchoolId!, _currentUserId!);
      } else {
        _pendingToken = token;
      }
    });
  }

  /// Handle foreground Firebase messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Foreground message: ${message.notification?.title}');

    // iOS presents the FCM notification natively in the foreground (see
    // setForegroundNotificationPresentationOptions in init) — re-showing it
    // locally here would produce a duplicate banner. Tap routing for the
    // native banner flows through onMessageOpenedApp → _handleMessageTap.
    if (!kIsWeb && Platform.isIOS) return;

    // Determine channel based on message type
    String channelId = _generalChannel;
    if (message.data['type'] == 'reading_reminder') {
      channelId = _readingReminderChannel;
    } else if (message.data['type'] == 'achievement_earned') {
      channelId = _achievementChannel;
    }

    // Show local notification
    await _showLocalNotification(
      title: message.notification?.title ?? 'Lumi',
      body: message.notification?.body ?? '',
      channelId: channelId,
      // JSON-encoded so the local tap handler can parse it the same way
      // _handleMessageTap does the FCM `data` map.
      payload: jsonEncode(message.data),
    );
  }

  /// Handle notification tap (Firebase — background/cold-start)
  void _handleMessageTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    final type = message.data['type'];
    if (type == 'staff_message') {
      _navigateTo('/parent/notifications?fromPush=true');
      return;
    }
    if (type == 'reading_reminder') {
      _routeReadingReminderTap(message.data);
      return;
    }
    if (type == 'comment_reply') {
      // Land on parent home; the unread dot in reading history guides the
      // parent into the specific log's thread. (Deep-linking straight to the
      // thread needs the StudentModel the reading-history route requires —
      // tracked as a follow-up.)
      _navigateTo('/parent/home');
      return;
    }
  }

  /// Handle notification tap (local notifications shown via _showLocalNotification).
  ///
  /// In foreground, FCM messages are re-shown locally — so this also routes
  /// reading_reminder taps via the same helper as the background path.
  void _handleNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      try {
        final data = jsonDecode(payload);
        if (data is Map<String, dynamic>) {
          if (data['type'] == 'staff_message') {
            _navigateTo('/parent/notifications?fromPush=true');
            return;
          }
          if (data['type'] == 'reading_reminder') {
            _routeReadingReminderTap(data);
            return;
          }
        }
      } catch (_) {
        // Payload wasn't JSON; fall through to the default home navigation.
      }
    }
    _navigateTo('/parent/home');
  }

  /// SharedPreferences key for the first child id from a tapped reading
  /// reminder. ParentHomeScreen consumes (and clears) this on init/resume to
  /// pre-select the child the parent was prompted about, so logging that
  /// child's reading is one tap away after the deep link.
  static const String pendingLogChildIdKey = 'pending_log_child_id';

  /// SharedPreferences key for the FULL list of un-logged child ids from a
  /// tapped reading reminder. ParentHomeScreen seeds the reminder queue from
  /// this so a multi-child parent is walked through logging each child, not
  /// just the first. Stored alongside [pendingLogChildIdKey].
  static const String pendingLogChildIdsKey = 'pending_log_child_ids';

  /// Persist the studentIds from a tapped reading reminder and route the user
  /// to the parent home. The first id seeds the active-child selection; the
  /// full list seeds the reminder queue so every un-logged child can be logged
  /// in turn. ParentHomeScreen owns the actual selection/queue handoff.
  Future<void> _routeReadingReminderTap(Map<String, dynamic> data) async {
    final rawIds = data['studentIds'];
    final ids = rawIds is String
        ? rawIds
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    if (ids.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(pendingLogChildIdKey, ids.first);
        await prefs.setStringList(pendingLogChildIdsKey, ids);
      } catch (e) {
        debugPrint('Could not persist pending log child ids: $e');
      }
    }
    _navigateTo('/parent/home');
  }

  /// Show a local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? channelId,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId ?? _generalChannel,
      channelId == _readingReminderChannel
          ? 'Reading Reminders'
          : channelId == _achievementChannel
              ? 'Achievements'
              : 'General',
      importance:
          channelId == _achievementChannel ? Importance.max : Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      enableLights: channelId == _achievementChannel,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // presentAlert is ignored on iOS 14+ — banner/list control visibility.
      presentBanner: true,
      presentList: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // Legacy SharedPreferences keys from the old client-side reminder scheduler.
  // Reminders are now sent by the `sendReadingReminders` Cloud Function; these
  // keys exist only so `cancelAllReminders` can sweep state from users upgrading
  // from an older build.
  static const String _legacyScheduledIdsKey = 'scheduled_notification_ids';
  static const String _legacyScheduledChildOrderKey = 'scheduled_child_order';
  static const List<String> _legacyReminderPrefKeys = [
    'reminder_hour',
    'reminder_minute',
    'reminders_enabled',
    'reminder_days',
  ];

  /// Cancel any OS-scheduled reminders from the old local pipeline and wipe
  /// their SharedPreferences. Called once per session from [initialize] as a
  /// migration sweep, and again from [clearUserScopedPrefs] on sign-out so a
  /// stale reminder for a previously linked child can't fire under a different
  /// account.
  Future<void> cancelAllReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final idStrings = prefs.getStringList(_legacyScheduledIdsKey) ?? [];

    for (final idStr in idStrings) {
      final id = int.tryParse(idStr);
      if (id != null) {
        await _localNotifications.cancel(id);
      }
    }

    await prefs.remove(_legacyScheduledIdsKey);
    await prefs.remove(_legacyScheduledChildOrderKey);
    for (final key in _legacyReminderPrefKeys) {
      await prefs.remove(key);
    }

    if (idStrings.isNotEmpty) {
      debugPrint('Cancelled ${idStrings.length} legacy local reminders');
    }
  }

  /// Clear every SharedPreferences key scoped to the previously signed-in
  /// parent. Called from [FirebaseService.signOut] so account switching can't
  /// leak the prior user's reminders, active child, or other local state.
  Future<void> clearUserScopedPrefs() async {
    await cancelAllReminders();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ActiveChildController.prefsKey);
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    if (_messaging == null) {
      await _initializeFirebaseMessaging();
    }

    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Get FCM token
  Future<String?> getToken() async {
    if (_messaging == null || kIsWeb) return null;

    try {
      return await _messaging!.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Show achievement notification
  Future<void> showAchievementNotification({
    required String achievementName,
    required String achievementIcon,
  }) async {
    await _showLocalNotification(
      title: '🎉 Achievement Unlocked! 🎉',
      body: '$achievementIcon $achievementName',
      channelId: _achievementChannel,
      payload: 'achievement:$achievementName',
    );
  }

  /// Single entry point that every successful parent auth flow (manual login,
  /// auto-login on app start, future sign-up) must call so the FCM token lands
  /// on the right parent document and the push pipeline stays addressable.
  ///
  /// Centralised so adding a new auth path can't quietly forget to register
  /// the device — a class of bug that previously left parents with stale or
  /// missing tokens.
  Future<void> onParentAuthenticated(UserModel user) async {
    if (user.role != UserRole.parent) return;
    final schoolId = user.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;
    await saveTokenForUser(schoolId, user.id);
  }

  /// Save FCM token to the correct parent document in Firestore.
  /// Prefer [onParentAuthenticated] from auth flows; this is the lower-level
  /// primitive that token-refresh and the helper both ultimately call.
  Future<void> saveTokenForUser(String schoolId, String userId) async {
    // Never overwrite a real parent's FCM token with the dev's device token
    // during an impersonation session. The dev's phone should not become the
    // push target for that school's notifications.
    if (ImpersonationService.instance.isActive) return;

    _currentSchoolId = schoolId;
    _currentUserId = userId;

    // Flush any token that refreshed before user context was available
    if (_pendingToken != null) {
      await _persistToken(_pendingToken!, schoolId, userId);
      _pendingToken = null;
      return;
    }

    if (_messaging == null || kIsWeb) return;

    try {
      final token = await _messaging!.getToken();
      if (token != null) {
        await _persistToken(token, schoolId, userId);
        if (kDebugMode) {
          debugPrint('FCM token saved for parent $userId in school $schoolId');
        }
      }
    } catch (e) {
      // APNS token not available on iOS Simulator - expected
      if (e.toString().contains('apns-token-not-set')) {
        debugPrint(
            'APNS not available (iOS Simulator) - notifications will work on physical devices');
      } else {
        debugPrint('Error saving FCM token: $e');
      }
    }
  }

  /// Persist token to the parent's Firestore document
  Future<void> _persistToken(
      String token, String schoolId, String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('parents')
          .doc(userId)
          .update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        // Dot-notation merges this single key without touching other preference fields
        'preferences.pushNotificationsEnabled': true,
      });
    } catch (e) {
      debugPrint('Error persisting FCM token: $e');
    }
  }

  /// Clear FCM token from Firestore on logout
  Future<void> clearTokenForUser() async {
    if (_currentSchoolId != null && _currentUserId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(_currentSchoolId!)
            .collection('parents')
            .doc(_currentUserId!)
            .update({
          'fcmToken': FieldValue.delete(),
          'fcmTokenUpdatedAt': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint('Error clearing FCM token: $e');
      }
    }
    _currentSchoolId = null;
    _currentUserId = null;
  }

  /// Test notification (for debugging)
  Future<void> testNotification() async {
    await _showLocalNotification(
      title: 'Test Notification',
      body: 'This is a test notification from Lumi!',
      channelId: _generalChannel,
    );
  }

  /// Send a test reading reminder. Tries a REAL FCM push to this device first
  /// (so it exercises the token + server delivery + the reading_reminder tap
  /// routing, including the multi-child flow), then falls back to an instant
  /// local notification if the push can't be sent (no token / offline / error).
  ///
  /// [schoolId] scopes the parent doc the server reads for the device token;
  /// [localBody] and [studentIds] build the local fallback (and its tap payload,
  /// so a fallback tap still routes through the multi-child reminder flow).
  /// Returns true if a real push was dispatched, false if it fell back local.
  Future<bool> sendReadingReminderTest({
    required String schoolId,
    required String localBody,
    required List<String> studentIds,
  }) async {
    if (schoolId.isNotEmpty) {
      try {
        final res = await lumiFunctions
            .httpsCallable('sendTestReadingReminder')
            .call({'schoolId': schoolId});
        final data = res.data;
        if (data is Map && data['sent'] == true) return true;
      } catch (e) {
        debugPrint('Test push failed, falling back to local preview: $e');
      }
    }
    await _showLocalNotification(
      title: 'Time to read with Lumi! 📚',
      body: localBody,
      channelId: _readingReminderChannel,
      payload: jsonEncode({
        'type': 'reading_reminder',
        'studentIds': studentIds.join(','),
      }),
    );
    return false;
  }
}
