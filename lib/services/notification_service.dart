import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/impersonation_service.dart';
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
  static NotificationService get instance => _instance ??= NotificationService._();

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
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
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
      payload: message.data.toString(),
    );
  }

  /// Handle notification tap (Firebase — background/cold-start)
  void _handleMessageTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    final type = message.data['type'];
    if (type == 'staff_message') {
      _navigateTo('/parent/notifications');
    }
  }

  /// Handle notification tap (local — reading reminders)
  void _handleNotificationTap(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');
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
      importance: channelId == _achievementChannel
          ? Importance.max
          : Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      enableLights: channelId == _achievementChannel,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
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

  // Notification ID scheme: childIndex * 10 + slot
  // slot 0 = daily (all days), slots 1-7 = specific weekday (Mon=1 .. Sun=7)
  static const String _scheduledIdsKey = 'scheduled_notification_ids';

  static int _notificationId(int childIndex, int slot) => childIndex * 10 + slot;

  /// Schedule reading reminders for one or more children.
  ///
  /// [childNames] — list of linked children's first names.
  /// [hour], [minute] — time of day for the reminder.
  /// [days] — weekdays to remind on (1=Mon .. 7=Sun). Empty/null = every day.
  Future<void> scheduleReminders({
    required List<String> childNames,
    required int hour,
    required int minute,
    List<int>? days,
  }) async {
    if (!_initialized) {
      debugPrint('Notification service not initialized');
      return;
    }

    // Cancel only previously-scheduled IDs (not a blind 200-iteration loop)
    await cancelAllReminders();

    final effectiveDays = (days == null || days.isEmpty) ? <int>[] : days;
    final isDaily = effectiveDays.isEmpty;
    final scheduledIds = <int>[];

    for (int childIdx = 0; childIdx < childNames.length; childIdx++) {
      final name = childNames[childIdx];
      final body = "Don't forget to log $name's reading today!";

      if (isDaily) {
        final id = _notificationId(childIdx, 0);
        await _scheduleOne(
          id: id,
          body: body,
          hour: hour,
          minute: minute,
          matchComponents: DateTimeComponents.time,
        );
        scheduledIds.add(id);
      } else {
        for (final day in effectiveDays) {
          final id = _notificationId(childIdx, day);
          await _scheduleOne(
            id: id,
            body: body,
            hour: hour,
            minute: minute,
            weekday: day,
            matchComponents: DateTimeComponents.dayOfWeekAndTime,
          );
          scheduledIds.add(id);
        }
      }
    }

    // Persist scheduled IDs + preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _scheduledIdsKey,
      scheduledIds.map((id) => id.toString()).toList(),
    );
    await prefs.setInt('reminder_hour', hour);
    await prefs.setInt('reminder_minute', minute);
    await prefs.setBool('reminders_enabled', true);
    await prefs.setStringList(
      'reminder_days',
      effectiveDays.map((d) => d.toString()).toList(),
    );

    debugPrint(
      'Reminders scheduled: ${scheduledIds.length} notifications for '
      '${childNames.length} child(ren) at '
      '$hour:${minute.toString().padLeft(2, '0')} on '
      '${isDaily ? "every day" : "days $effectiveDays"}',
    );
  }

  /// Internal: schedule a single local notification.
  Future<void> _scheduleOne({
    required int id,
    required String body,
    required int hour,
    required int minute,
    int? weekday,
    required DateTimeComponents matchComponents,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (weekday != null) {
      // Advance to the next occurrence of this weekday
      while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    } else if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final androidDetails = AndroidNotificationDetails(
      _readingReminderChannel,
      'Reading Reminders',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.zonedSchedule(
      id,
      'Time to read with Lumi! 📚',
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: matchComponents,
    );
  }

  /// Cancel only the notification IDs we previously scheduled.
  Future<void> cancelAllReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final idStrings = prefs.getStringList(_scheduledIdsKey) ?? [];

    // Cancel only the IDs we actually scheduled
    for (final idStr in idStrings) {
      final id = int.tryParse(idStr);
      if (id != null) {
        await _localNotifications.cancel(id);
      }
    }

    await prefs.remove(_scheduledIdsKey);
    await prefs.setBool('reminders_enabled', false);
    await prefs.remove('reminder_days');

    debugPrint('Cancelled ${idStrings.length} scheduled reminders');
  }

  /// Backward-compatible wrappers ------------------------------------------------

  /// Schedule a daily reminder for a single child (legacy callers).
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String studentName,
  }) async {
    await scheduleReminders(
      childNames: [studentName],
      hour: hour,
      minute: minute,
    );
  }

  /// Cancel all reminders (legacy callers).
  Future<void> cancelDailyReminder() async {
    await cancelAllReminders();
  }

  /// Check if reminders are enabled
  Future<bool> areRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('reminders_enabled') ?? false;
  }

  /// Get reminder time
  Future<Map<String, int>?> getReminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('reminders_enabled') ?? false;

    if (!enabled) return null;

    final hour = prefs.getInt('reminder_hour') ?? 18;
    final minute = prefs.getInt('reminder_minute') ?? 0;

    return {'hour': hour, 'minute': minute};
  }

  /// Get reminder days (empty = every day)
  Future<List<int>> getReminderDays() async {
    final prefs = await SharedPreferences.getInstance();
    final dayStrings = prefs.getStringList('reminder_days') ?? [];
    return dayStrings.map((s) => int.tryParse(s) ?? 0).where((d) => d >= 1 && d <= 7).toList();
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

  /// Save FCM token to the correct parent document in Firestore
  /// Called after login/auto-login once the user's schoolId and userId are known
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
        debugPrint('FCM token saved for parent $userId in school $schoolId');
      }
    } catch (e) {
      // APNS token not available on iOS Simulator - expected
      if (e.toString().contains('apns-token-not-set')) {
        debugPrint('APNS not available (iOS Simulator) - notifications will work on physical devices');
      } else {
        debugPrint('Error saving FCM token: $e');
      }
    }
  }

  /// Persist token to the parent's Firestore document
  Future<void> _persistToken(String token, String schoolId, String userId) async {
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
}
