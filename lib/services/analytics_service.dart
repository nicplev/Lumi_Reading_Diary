import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../core/services/impersonation_service.dart';

/// Analytics service for Lumi Reading Diary.
/// Tracks key user actions to understand app usage patterns.
class AnalyticsService {
  static AnalyticsService? _instance;
  static AnalyticsService get instance => _instance ??= AnalyticsService._();

  AnalyticsService._();

  late final FirebaseAnalytics _analytics;
  bool _initialized = false;
  bool _collectionEnabled = false;

  /// Global gate: skip all analytics when uninitialised OR while a developer
  /// impersonation session is active (avoids polluting a real school's
  /// analytics with dev-driven events).
  bool get _shouldSuppress =>
      !_initialized ||
      !_collectionEnabled ||
      ImpersonationService.instance.isActive;

  Future<void> initialize({bool collectionEnabled = false}) async {
    try {
      _analytics = FirebaseAnalytics.instance;
      _initialized = true;
      await setCollectionEnabled(collectionEnabled);
      debugPrint('Analytics initialized (enabled: $_collectionEnabled)');
    } catch (e) {
      debugPrint('Warning: Analytics init failed or timed out: $e');
      _analytics = FirebaseAnalytics.instance;
      _initialized = true;
      _collectionEnabled = false;
    }
  }

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// Applies the adult's optional analytics choice. Debug builds remain off.
  /// Disabling also removes any legacy UID/property and rotates the local
  /// Analytics app-instance identifier left by older Lumi releases.
  Future<void> setCollectionEnabled(bool enabled) async {
    if (!_initialized) return;
    final effectiveEnabled = enabled && !kDebugMode;
    try {
      // Analytics consent is independent from advertising consent. Lumi never
      // enables ad storage, ad-user-data or personalisation signals.
      await _analytics
          .setConsent(
            analyticsStorageConsentGranted: effectiveEnabled,
            adStorageConsentGranted: false,
            adUserDataConsentGranted: false,
            adPersonalizationSignalsConsentGranted: false,
          )
          .timeout(const Duration(seconds: 5));
      // This native call has hung on some iOS versions, so it must never block
      // startup or the settings screen indefinitely.
      await _analytics
          .setAnalyticsCollectionEnabled(effectiveEnabled)
          .timeout(const Duration(seconds: 5));
      _collectionEnabled = effectiveEnabled;
      if (!effectiveEnabled) {
        await _analytics.setUserId(id: null);
        await _analytics.setUserProperty(name: 'user_role', value: null);
        await _analytics.resetAnalyticsData();
      }
    } catch (e) {
      _collectionEnabled = false;
      debugPrint('Error applying analytics privacy choice: $e');
    }
  }

  // ─── Key Action Events ─────────────────────────────────

  /// Logged when a parent completes a reading log entry
  Future<void> logReadingLogged({
    required String feeling,
    required int bookCount,
    required int minutesRead,
  }) async {
    if (_shouldSuppress) return;
    try {
      // Never attach child feelings, reading volume or duration.
      await _analytics.logEvent(name: 'reading_logged');
    } catch (e) {
      debugPrint('Error logging reading_logged event: $e');
    }
  }

  /// Logged when a student earns a new badge
  Future<void> logBadgeEarned({required String badgeType}) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'badge_earned');
    } catch (e) {
      debugPrint('Error logging badge_earned event: $e');
    }
  }

  /// Logged when a student reaches a streak milestone
  Future<void> logStreakMilestone({required int streakCount}) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'streak_milestone');
    } catch (e) {
      debugPrint('Error logging streak_milestone event: $e');
    }
  }

  /// Logged when the app is opened
  Future<void> logAppOpened({required String role}) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'app_opened');
    } catch (e) {
      debugPrint('Error logging app_opened event: $e');
    }
  }

  /// Logged when feedback is submitted
  Future<void> logFeedbackSubmitted({required String category}) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'feedback_submitted');
    } catch (e) {
      debugPrint('Error logging feedback_submitted event: $e');
    }
  }

  /// Logged when a parent links a child
  Future<void> logChildLinked() async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'child_linked');
    } catch (e) {
      debugPrint('Error logging child_linked event: $e');
    }
  }

  /// Logged when a teacher creates an allocation
  Future<void> logAllocationCreated({required String type}) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'allocation_created');
    } catch (e) {
      debugPrint('Error logging allocation_created event: $e');
    }
  }

  /// Logged when a school onboarding step is completed
  Future<void> logOnboardingStepCompleted({
    required String step,
  }) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'onboarding_step_completed');
    } catch (e) {
      debugPrint('Error logging onboarding_step_completed event: $e');
    }
  }

  /// Logged when onboarding fails for a specific step
  Future<void> logOnboardingFailed({
    required String step,
    required String reason,
  }) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'onboarding_failed');
    } catch (e) {
      debugPrint('Error logging onboarding_failed event: $e');
    }
  }

  /// Logged when a parent verifies a link code successfully
  Future<void> logParentCodeVerified() async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'parent_code_verified');
    } catch (e) {
      debugPrint('Error logging parent_code_verified event: $e');
    }
  }

  /// Logged when parent linking completes successfully
  Future<void> logParentLinkingCompleted() async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'parent_linking_completed');
    } catch (e) {
      debugPrint('Error logging parent_linking_completed event: $e');
    }
  }

  /// Logged when parent linking fails
  Future<void> logParentLinkingFailed({required String reason}) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'parent_linking_failed');
    } catch (e) {
      debugPrint('Error logging parent_linking_failed event: $e');
    }
  }

  /// Logged when staff export parent link codes
  Future<void> logParentCodesExported({required int rowCount}) async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'parent_codes_exported');
    } catch (e) {
      debugPrint('Error logging parent_codes_exported event: $e');
    }
  }

  /// Logged when staff revoke a parent link code
  Future<void> logParentCodeRevoked() async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'parent_code_revoked');
    } catch (e) {
      debugPrint('Error logging parent_code_revoked event: $e');
    }
  }

  /// Logged when staff unlink a parent from a student
  Future<void> logParentUnlinked() async {
    if (_shouldSuppress) return;
    try {
      await _analytics.logEvent(name: 'parent_unlinked');
    } catch (e) {
      debugPrint('Error logging parent_unlinked event: $e');
    }
  }
}
