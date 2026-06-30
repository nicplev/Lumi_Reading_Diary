import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'access_provider.dart';

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
