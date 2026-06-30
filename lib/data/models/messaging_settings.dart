/// Per-school configuration for parent↔teacher messaging — the threaded
/// comment conversations attached to reading logs.
///
/// Stored at `schools/{schoolId}.settings.messaging` in Firestore and
/// administered from the school-admin web portal. Absent = enabled, so existing
/// schools keep messaging until an admin turns it off.
class MessagingSettings {
  final bool enabled;

  const MessagingSettings({required this.enabled});

  factory MessagingSettings.defaults() =>
      const MessagingSettings(enabled: true);

  factory MessagingSettings.fromMap(Map<String, dynamic>? map) =>
      MessagingSettings(
        enabled: map?['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {'enabled': enabled};
}
