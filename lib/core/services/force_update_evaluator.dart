import '../models/remote_message.dart';

enum ForceUpdateDecision {
  allow,
  checking,
  updateRequired,
  supportRequired,
}

/// Pure logic for the force-update gate — no Flutter/Firebase imports so it
/// unit-tests directly.
///
/// The status worker's payload carries optional `minAppVersion` +
/// `platforms`; when the running build is older than `minAppVersion` (and
/// the platform matches), the app renders a blocking update screen instead
/// of the UI. This is the safety valve for rules/functions deploys that old
/// clients can't handle. Every ambiguity fails OPEN (no block): a malformed
/// worker payload must never brick every install.

/// Parse "1.2.3" (optionally "1.2.3+45" / "1.2.3-beta") into numeric
/// segments, or null when any segment isn't a plain number.
List<int>? parseVersion(String raw) {
  final core = raw.trim().split(RegExp(r'[+-]')).first;
  if (core.isEmpty) return null;
  final parts = core.split('.');
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out;
}

/// True iff [current] is a valid version strictly below [min].
/// Unparseable input → false (fail open).
bool isVersionBelow(String current, String min) {
  final cur = parseVersion(current);
  final req = parseVersion(min);
  if (cur == null || req == null) return false;
  final len = cur.length > req.length ? cur.length : req.length;
  for (var i = 0; i < len; i++) {
    final c = i < cur.length ? cur[i] : 0;
    final r = i < req.length ? req[i] : 0;
    if (c != r) return c < r;
  }
  return false; // equal
}

/// Whether the running build must be blocked behind the update screen.
///
/// [platform] is 'ios' / 'android' / 'web' (lowercase). A message with no
/// `platforms` list applies to every platform; an empty list too.
bool shouldForceUpdate({
  required RemoteMessage? message,
  required String? currentVersion,
  required String platform,
}) {
  if (message == null) return false;
  final min = message.minAppVersion;
  if (min == null || min.trim().isEmpty) return false;
  if (currentVersion == null || currentVersion.trim().isEmpty) return false;
  final platforms = message.platforms;
  if (platforms != null && platforms.isNotEmpty) {
    final normalized = platforms.map((p) => p.trim().toLowerCase());
    if (!normalized.contains(platform.toLowerCase())) return false;
  }
  return isVersionBelow(currentVersion, min);
}

/// Release-safe decision for the app-wide gate.
///
/// A release blocks on missing configuration, invalid policy data or an
/// unreadable installed version. A confirmed transient transport failure may
/// temporarily fail open while the caller retries in the background; an
/// actual cached or remote minimum-version policy remains enforceable.
ForceUpdateDecision evaluateForceUpdate({
  required bool requireVersionConfig,
  required bool configConfigured,
  required bool? configAvailable,
  bool transientConfigFailure = false,
  required RemoteMessage? message,
  required String? currentVersion,
  required String platform,
}) {
  if (requireVersionConfig && !configConfigured) {
    return ForceUpdateDecision.supportRequired;
  }
  if (requireVersionConfig && configAvailable == null) {
    return ForceUpdateDecision.checking;
  }
  if (requireVersionConfig && configAvailable == false) {
    return transientConfigFailure
        ? ForceUpdateDecision.allow
        : ForceUpdateDecision.supportRequired;
  }
  if (message == null) {
    return requireVersionConfig
        ? ForceUpdateDecision.supportRequired
        : ForceUpdateDecision.allow;
  }

  final min = message.minAppVersion;
  if (min == null || min.trim().isEmpty) return ForceUpdateDecision.allow;

  final platforms = message.platforms;
  if (platforms != null && platforms.isNotEmpty) {
    final normalized = platforms.map((p) => p.trim().toLowerCase());
    if (!normalized.contains(platform.toLowerCase())) {
      return ForceUpdateDecision.allow;
    }
  }

  if (currentVersion == null || currentVersion.trim().isEmpty) {
    return requireVersionConfig
        ? ForceUpdateDecision.supportRequired
        : ForceUpdateDecision.allow;
  }
  if (parseVersion(currentVersion) == null || parseVersion(min) == null) {
    return requireVersionConfig
        ? ForceUpdateDecision.supportRequired
        : ForceUpdateDecision.allow;
  }
  return isVersionBelow(currentVersion, min)
      ? ForceUpdateDecision.updateRequired
      : ForceUpdateDecision.allow;
}
