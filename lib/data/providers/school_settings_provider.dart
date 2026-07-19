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
/// A missing document retains the historic fail-open client behaviour. The
/// callable playback endpoint and Storage Rules remain the hard fail-closed
/// boundary when a stale/offline client has not observed a switch change yet.
final platformComprehensionAudioEnabledProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection('platformConfig')
      .doc('comprehensionRecording')
      .snapshots()
      .map((doc) => (doc.data()?['enabled'] as bool?) ?? true);
});

/// Whether teachers may see and play comprehension recordings for [schoolId].
///
/// Missing/legacy school settings fail CLOSED because voice recording is an
/// opt-in feature. While an already-known school document is refreshing, keep
/// the affordance visible; the callable playback endpoint independently
/// enforces both the platform and school switches.
final comprehensionAudioEnabledProvider =
    Provider.family<bool, String>((ref, schoolId) {
  if (schoolId.isEmpty) return false;
  final platformEnabled =
      ref.watch(platformComprehensionAudioEnabledProvider).when(
            data: (enabled) => enabled,
            loading: () => true,
            error: (_, __) => true,
          );
  final schoolEnabled = ref.watch(schoolByIdProvider(schoolId)).when(
        data: (school) =>
            school?.comprehensionRecordingSettings.enabled ?? false,
        loading: () => true,
        error: (_, __) => true,
      );
  return platformEnabled && schoolEnabled;
});
