/// Per-school configuration for the comprehension voice-recording step on
/// the reading log screen.
///
/// Stored at `schools/{schoolId}.settings.comprehensionRecording` in Firestore.
/// The toggle is administered from the school-admin web portal; the per-class
/// prompt is on `classes/{classId}.settings.comprehensionQuestion`.
class ComprehensionRecordingSettings {
  final bool enabled;

  const ComprehensionRecordingSettings({required this.enabled});

  factory ComprehensionRecordingSettings.defaults() =>
      const ComprehensionRecordingSettings(enabled: false);

  factory ComprehensionRecordingSettings.fromMap(Map<String, dynamic>? map) =>
      ComprehensionRecordingSettings(
        enabled: map?['enabled'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {'enabled': enabled};
}
