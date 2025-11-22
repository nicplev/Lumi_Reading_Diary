import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

/// Crash Reporting Service for Lumi Reading Diary
/// Handles error tracking, crash reporting, and analytics
class CrashReportingService {
  static CrashReportingService? _instance;
  static CrashReportingService get instance => _instance ??= CrashReportingService._();

  CrashReportingService._();

  late FirebaseCrashlytics _crashlytics;
  bool _initialized = false;

  /// Initialize crash reporting
  Future<void> initialize() async {
    try {
      _crashlytics = FirebaseCrashlytics.instance;

      // Enable crash collection in production only
      await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Pass all uncaught errors from the framework to Crashlytics
      FlutterError.onError = (FlutterErrorDetails details) {
        _crashlytics.recordFlutterError(details);
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
      };

      // Catch errors that occur outside of Flutter framework
      PlatformDispatcher.instance.onError = (error, stack) {
        _crashlytics.recordError(error, stack, fatal: true);
        return true;
      };

      _initialized = true;
      debugPrint('Crash reporting initialized (enabled: ${!kDebugMode})');
    } catch (e) {
      debugPrint('Error initializing crash reporting: $e');
      _initialized = false;
    }
  }

  /// Set user identifier for crash reports
  Future<void> setUserId(String userId) async {
    if (!_initialized) return;

    try {
      await _crashlytics.setUserIdentifier(userId);
      debugPrint('Crash reporting user ID set: $userId');
    } catch (e) {
      debugPrint('Error setting user ID for crash reporting: $e');
    }
  }

  /// Set custom key-value pairs for additional context
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_initialized) return;

    try {
      if (value is String) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is int) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is double) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is bool) {
        await _crashlytics.setCustomKey(key, value);
      } else {
        await _crashlytics.setCustomKey(key, value.toString());
      }
      debugPrint('Crash reporting custom key set: $key = $value');
    } catch (e) {
      debugPrint('Error setting custom key for crash reporting: $e');
    }
  }

  /// Log a message to Crashlytics
  Future<void> log(String message) async {
    if (!_initialized) return;

    try {
      await _crashlytics.log(message);
      debugPrint('Crash reporting log: $message');
    } catch (e) {
      debugPrint('Error logging to crash reporting: $e');
    }
  }

  /// Record a non-fatal error
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    dynamic reason,
    bool fatal = false,
    Iterable<Object> information = const [],
  }) async {
    if (!_initialized) return;

    try {
      await _crashlytics.recordError(
        exception,
        stackTrace,
        reason: reason,
        fatal: fatal,
        information: information,
      );
      debugPrint('Crash reporting error recorded: $exception');
    } catch (e) {
      debugPrint('Error recording to crash reporting: $e');
    }
  }

  /// Record Flutter framework error
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    if (!_initialized) return;

    try {
      await _crashlytics.recordFlutterError(details);
      debugPrint('Crash reporting Flutter error recorded');
    } catch (e) {
      debugPrint('Error recording Flutter error to crash reporting: $e');
    }
  }

  /// Force a crash (for testing purposes only)
  Future<void> forceCrash() async {
    if (!_initialized) return;
    if (kDebugMode) {
      debugPrint('Forcing crash (debug mode only)');
      throw Exception('Test crash from CrashReportingService');
    }
  }

  /// Check if crash reporting is enabled
  Future<bool> isCrashlyticsCollectionEnabled() async {
    if (!_initialized) return false;

    try {
      return _crashlytics.isCrashlyticsCollectionEnabled;
    } catch (e) {
      debugPrint('Error checking crashlytics status: $e');
      return false;
    }
  }

  /// Send unsent reports
  Future<void> sendUnsentReports() async {
    if (!_initialized) return;

    try {
      await _crashlytics.sendUnsentReports();
      debugPrint('Unsent crash reports sent');
    } catch (e) {
      debugPrint('Error sending unsent reports: $e');
    }
  }

  /// Delete unsent reports
  Future<void> deleteUnsentReports() async {
    if (!_initialized) return;

    try {
      await _crashlytics.deleteUnsentReports();
      debugPrint('Unsent crash reports deleted');
    } catch (e) {
      debugPrint('Error deleting unsent reports: $e');
    }
  }

  /// Check for unsent reports
  Future<bool> checkForUnsentReports() async {
    if (!_initialized) return false;

    try {
      return await _crashlytics.checkForUnsentReports();
    } catch (e) {
      debugPrint('Error checking for unsent reports: $e');
      return false;
    }
  }

  /// Set whether automatic data collection is enabled
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    if (!_initialized) return;

    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
      debugPrint('Crashlytics collection enabled: $enabled');
    } catch (e) {
      debugPrint('Error setting crashlytics collection: $e');
    }
  }

  /// Wrapper for running app with zone error handling
  static Future<void> runAppWithZoneGuard(
    Future<void> Function() body, {
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    await runZonedGuarded<Future<void>>(
      body,
      (error, stack) {
        CrashReportingService.instance.recordError(error, stack, fatal: true);
        onError?.call(error, stack);
      },
    );
  }
}

/// Extension to easily record errors within try-catch blocks
extension ErrorRecording on Object {
  Future<void> reportToCrashlytics({
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
  }) async {
    await CrashReportingService.instance.recordError(
      this,
      stackTrace ?? StackTrace.current,
      reason: reason,
      fatal: fatal,
    );
  }
}

/// Mixin for easy crash reporting in classes
mixin CrashReportingMixin {
  Future<void> reportError(
    dynamic error,
    StackTrace stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    await CrashReportingService.instance.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  Future<void> logMessage(String message) async {
    await CrashReportingService.instance.log(message);
  }
}
