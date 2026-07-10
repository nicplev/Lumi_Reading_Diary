/// Per-school configuration for the parent app's one-tap reading-log shortcut.
///
/// Stored at `schools/{schoolId}.settings.quickLogging` in Firestore and
/// administered from the school-admin web portal. Absent = enabled so existing
/// schools keep their current behaviour until an admin turns it off.
class QuickLoggingSettings {
  final bool enabled;

  const QuickLoggingSettings({required this.enabled});

  factory QuickLoggingSettings.defaults() =>
      const QuickLoggingSettings(enabled: true);

  factory QuickLoggingSettings.fromMap(Map<String, dynamic>? map) =>
      QuickLoggingSettings(
        enabled: map?['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {'enabled': enabled};
}
