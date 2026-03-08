import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Analytics service for Lumi Reading Diary.
/// Tracks key user actions to understand app usage patterns.
class AnalyticsService {
  static AnalyticsService? _instance;
  static AnalyticsService get instance => _instance ??= AnalyticsService._();

  AnalyticsService._();

  late final FirebaseAnalytics _analytics;
  bool _initialized = false;

  Future<void> initialize() async {
    try {
      _analytics = FirebaseAnalytics.instance;
      await _analytics.setAnalyticsCollectionEnabled(!kDebugMode);
      _initialized = true;
      debugPrint('Analytics initialized (enabled: ${!kDebugMode})');
    } catch (e) {
      debugPrint('Error initializing analytics: $e');
      _initialized = false;
    }
  }

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// Set the current user for analytics tracking
  Future<void> setUserId(String userId) async {
    if (!_initialized) return;
    try {
      await _analytics.setUserId(id: userId);
    } catch (e) {
      debugPrint('Error setting analytics user ID: $e');
    }
  }

  /// Set user role property (parent, teacher, schoolAdmin)
  Future<void> setUserRole(String role) async {
    if (!_initialized) return;
    try {
      await _analytics.setUserProperty(name: 'user_role', value: role);
    } catch (e) {
      debugPrint('Error setting user role: $e');
    }
  }

  // ─── Key Action Events ─────────────────────────────────

  /// Logged when a parent completes a reading log entry
  Future<void> logReadingLogged({
    required String feeling,
    required int bookCount,
    required int minutesRead,
  }) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'reading_logged',
        parameters: {
          'feeling': feeling,
          'book_count': bookCount,
          'minutes_read': minutesRead,
        },
      );
    } catch (e) {
      debugPrint('Error logging reading_logged event: $e');
    }
  }

  /// Logged when a student earns a new badge
  Future<void> logBadgeEarned({required String badgeType}) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'badge_earned',
        parameters: {'badge_type': badgeType},
      );
    } catch (e) {
      debugPrint('Error logging badge_earned event: $e');
    }
  }

  /// Logged when a student reaches a streak milestone
  Future<void> logStreakMilestone({required int streakCount}) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'streak_milestone',
        parameters: {'streak_count': streakCount},
      );
    } catch (e) {
      debugPrint('Error logging streak_milestone event: $e');
    }
  }

  /// Logged when the app is opened
  Future<void> logAppOpened({required String role}) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'app_opened',
        parameters: {'role': role},
      );
    } catch (e) {
      debugPrint('Error logging app_opened event: $e');
    }
  }

  /// Logged when feedback is submitted
  Future<void> logFeedbackSubmitted({required String category}) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'feedback_submitted',
        parameters: {'category': category},
      );
    } catch (e) {
      debugPrint('Error logging feedback_submitted event: $e');
    }
  }

  /// Logged when a parent links a child
  Future<void> logChildLinked() async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(name: 'child_linked');
    } catch (e) {
      debugPrint('Error logging child_linked event: $e');
    }
  }

  /// Logged when a teacher creates an allocation
  Future<void> logAllocationCreated({required String type}) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'allocation_created',
        parameters: {'type': type},
      );
    } catch (e) {
      debugPrint('Error logging allocation_created event: $e');
    }
  }

  /// Logged when a school onboarding step is completed
  Future<void> logOnboardingStepCompleted({
    required String step,
  }) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'onboarding_step_completed',
        parameters: {'step': step},
      );
    } catch (e) {
      debugPrint('Error logging onboarding_step_completed event: $e');
    }
  }

  /// Logged when onboarding fails for a specific step
  Future<void> logOnboardingFailed({
    required String step,
    required String reason,
  }) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'onboarding_failed',
        parameters: {
          'step': step,
          'reason': reason,
        },
      );
    } catch (e) {
      debugPrint('Error logging onboarding_failed event: $e');
    }
  }

  /// Logged when a parent verifies a link code successfully
  Future<void> logParentCodeVerified() async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(name: 'parent_code_verified');
    } catch (e) {
      debugPrint('Error logging parent_code_verified event: $e');
    }
  }

  /// Logged when parent linking completes successfully
  Future<void> logParentLinkingCompleted() async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(name: 'parent_linking_completed');
    } catch (e) {
      debugPrint('Error logging parent_linking_completed event: $e');
    }
  }

  /// Logged when parent linking fails
  Future<void> logParentLinkingFailed({required String reason}) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'parent_linking_failed',
        parameters: {'reason': reason},
      );
    } catch (e) {
      debugPrint('Error logging parent_linking_failed event: $e');
    }
  }

  /// Logged when staff export parent link codes
  Future<void> logParentCodesExported({required int rowCount}) async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(
        name: 'parent_codes_exported',
        parameters: {'row_count': rowCount},
      );
    } catch (e) {
      debugPrint('Error logging parent_codes_exported event: $e');
    }
  }

  /// Logged when staff revoke a parent link code
  Future<void> logParentCodeRevoked() async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(name: 'parent_code_revoked');
    } catch (e) {
      debugPrint('Error logging parent_code_revoked event: $e');
    }
  }

  /// Logged when staff unlink a parent from a student
  Future<void> logParentUnlinked() async {
    if (!_initialized) return;
    try {
      await _analytics.logEvent(name: 'parent_unlinked');
    } catch (e) {
      debugPrint('Error logging parent_unlinked event: $e');
    }
  }
}
