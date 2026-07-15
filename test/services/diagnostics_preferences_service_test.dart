import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/diagnostics_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('optional diagnostics fail closed when no preference exists', () async {
    final service = DiagnosticsPreferencesService(
      analyticsCollectionSetter: (_) async {},
      crashCollectionSetter: (_) async {},
    );

    final preferences = await service.load();

    expect(preferences.analyticsEnabled, isFalse);
    expect(preferences.crashReportsEnabled, isFalse);
  });

  test('analytics choice persists and is applied to the running SDK', () async {
    bool? applied;
    final service = DiagnosticsPreferencesService(
      analyticsCollectionSetter: (enabled) async => applied = enabled,
      crashCollectionSetter: (_) async {},
    );

    await service.setAnalyticsEnabled(true);

    expect(applied, isTrue);
    expect((await service.load()).analyticsEnabled, isTrue);
  });

  test('crash-report withdrawal persists and is applied immediately', () async {
    SharedPreferences.setMockInitialValues({
      DiagnosticsPreferencesService.crashReportsEnabledKey: true,
    });
    bool? applied;
    final service = DiagnosticsPreferencesService(
      analyticsCollectionSetter: (_) async {},
      crashCollectionSetter: (enabled) async => applied = enabled,
    );

    await service.setCrashReportsEnabled(false);

    expect(applied, isFalse);
    expect((await service.load()).crashReportsEnabled, isFalse);
  });
}
