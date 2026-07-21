import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'access_provider.dart';
import 'active_child_provider.dart';

/// Whether parent↔teacher messaging (the reading-log comment threads) is
/// enabled for [schoolId].
///
/// Reads the school document via [schoolByIdProvider] and defaults to TRUE
/// while the doc is still loading or for legacy docs without the setting — so
/// messaging fails OPEN and an enabled school never momentarily hides its
/// threads on a transient null. A school admin disables it from the
/// school-admin web portal (Settings → Parent App).
final messagingEnabledProvider = Provider.family<bool, String>((ref, schoolId) {
  if (schoolId.isEmpty) return true;
  final school = ref.watch(schoolByIdProvider(schoolId)).value;
  return school?.messagingSettings.enabled ?? true;
});

/// Whether the parent app's one-tap/minutes-only quick logging shortcut is
/// enabled for [schoolId].
///
/// Defaults to TRUE for legacy school docs and while the school stream is still
/// loading, preserving current behaviour unless an admin explicitly disables it.
/// Firestore rules are the hard backstop for stale or tampered clients.
final quickLoggingEnabledProvider =
    Provider.family<bool, String>((ref, schoolId) {
  if (schoolId.isEmpty) return true;
  final school = ref.watch(schoolByIdProvider(schoolId)).value;
  return school?.quickLoggingSettings.enabled ?? true;
});

/// Live platform-wide emergency switch for comprehension audio.
///
/// Missing, loading and malformed values are treated as OFF. Playback remains
/// independently authorized by the callable endpoint, but the teacher UI also
/// avoids querying or advertising recordings until this privacy-sensitive gate
/// has resolved positively.
final platformComprehensionAudioEnabledProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection('platformConfig')
      .doc('comprehensionRecording')
      .snapshots()
      .map((doc) => doc.data()?['enabled'] == true);
});

/// Whether teachers may see and play comprehension recordings for [schoolId].
///
/// Missing/legacy school settings, loading and errors all fail CLOSED because
/// child voice recording is an opt-in feature.
final comprehensionAudioEnabledProvider =
    Provider.family<bool, String>((ref, schoolId) {
  if (schoolId.isEmpty) return false;
  final platformEnabled =
      ref.watch(platformComprehensionAudioEnabledProvider).when(
            data: (enabled) => enabled,
            loading: () => false,
            error: (_, __) => false,
          );
  final schoolEnabled = ref.watch(schoolByIdProvider(schoolId)).when(
        data: (school) {
          final settings = school?.comprehensionRecordingSettings;
          return settings?.enabled == true && settings?.previewOnly != true;
        },
        loading: () => false,
        error: (_, __) => false,
      );
  return platformEnabled && schoolEnabled;
});
