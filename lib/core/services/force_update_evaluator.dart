import '../models/remote_message.dart';

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
