import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';
import 'crash_reporting_service.dart';

/// The adult account holder's optional diagnostics choices.
///
/// Both values deliberately default to false. They are stored on the device,
/// not in the child or school record, and therefore cannot be used as another
/// cross-device user identifier.
class DiagnosticsPreferences {
  const DiagnosticsPreferences({
    required this.analyticsEnabled,
    required this.crashReportsEnabled,
  });

  final bool analyticsEnabled;
  final bool crashReportsEnabled;
}

abstract class DiagnosticsSettingsController {
  Future<DiagnosticsPreferences> load();
  Future<void> setAnalyticsEnabled(bool enabled);
  Future<void> setCrashReportsEnabled(bool enabled);
}

/// Persists privacy choices and immediately applies them to the running SDKs.
class DiagnosticsPreferencesService implements DiagnosticsSettingsController {
  DiagnosticsPreferencesService({
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<void> Function(bool enabled)? analyticsCollectionSetter,
    Future<void> Function(bool enabled)? crashCollectionSetter,
  })  : _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance,
        _analyticsCollectionSetter = analyticsCollectionSetter ??
            AnalyticsService.instance.setCollectionEnabled,
        _crashCollectionSetter = crashCollectionSetter ??
            CrashReportingService.instance.setCrashlyticsCollectionEnabled;

  static final DiagnosticsPreferencesService instance =
      DiagnosticsPreferencesService();

  static const analyticsEnabledKey = 'privacy.optional_analytics_enabled_v1';
  static const crashReportsEnabledKey =
      'privacy.optional_crash_reports_enabled_v1';

  final Future<SharedPreferences> Function() _preferencesProvider;
  final Future<void> Function(bool enabled) _analyticsCollectionSetter;
  final Future<void> Function(bool enabled) _crashCollectionSetter;

  @override
  Future<DiagnosticsPreferences> load() async {
    final preferences = await _preferencesProvider();
    return DiagnosticsPreferences(
      analyticsEnabled: preferences.getBool(analyticsEnabledKey) ?? false,
      crashReportsEnabled: preferences.getBool(crashReportsEnabledKey) ?? false,
    );
  }

  @override
  Future<void> setAnalyticsEnabled(bool enabled) async {
    final preferences = await _preferencesProvider();
    await preferences.setBool(analyticsEnabledKey, enabled);
    await _analyticsCollectionSetter(enabled);
  }

  @override
  Future<void> setCrashReportsEnabled(bool enabled) async {
    final preferences = await _preferencesProvider();
    await preferences.setBool(crashReportsEnabledKey, enabled);
    await _crashCollectionSetter(enabled);
  }
}
