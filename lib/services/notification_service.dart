import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

/// Smart notification service for Lumi Reading Diary
/// Handles push notifications, local notifications, and scheduled reminders
class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance => _instance ??= NotificationService._();

  NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _messaging;
  bool _initialized = false;

  // Notification channels
  static const String _readingReminderChannel = 'reading_reminders';
  static const String _achievementChannel = 'achievements';
  static const String _generalChannel = 'general';

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

    // Request permission (iOS)
    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('Notification permission: ${settings.authorizationStatus}');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // Check for message that opened the app
    final initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageTap(initialMessage);
    }
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

  /// Handle notification tap (Firebase)
  void _handleMessageTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');

    final type = message.data['type'];
    final studentId = message.data['studentId'];

    // Navigate based on type
    // This would integrate with go_router or navigation service
    // For now, just log
    debugPrint('Navigate to: $type for student $studentId');
  }

  /// Handle notification tap (local)
  void _handleNotificationTap(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');
    // Handle navigation based on payload
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

  /// Schedule daily reading reminder
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String studentName,
  }) async {
    if (!_initialized) {
      debugPrint('Notification service not initialized');
      return;
    }

    // Cancel existing reminder
    await cancelDailyReminder();

    // Schedule new reminder
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);

    // If time has passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
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
      0, // ID for daily reminder
      'Time to read with Lumi! 📚',
      "Don't forget to log $studentName's reading today!",
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
    );

    // Save preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_hour', hour);
    await prefs.setInt('reminder_minute', minute);
    await prefs.setBool('reminders_enabled', true);

    debugPrint('Daily reminder scheduled for $hour:$minute');
  }

  /// Cancel daily reminder
  Future<void> cancelDailyReminder() async {
    await _localNotifications.cancel(0);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminders_enabled', false);

    debugPrint('Daily reminder cancelled');
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

  /// Test notification (for debugging)
  Future<void> testNotification() async {
    await _showLocalNotification(
      title: 'Test Notification',
      body: 'This is a test notification from Lumi!',
      channelId: _generalChannel,
    );
  }
}
