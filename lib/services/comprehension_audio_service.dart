import '../core/services/functions_instance.dart';

/// Thin client wrapper around the `deleteComprehensionAudio` callable.
///
/// Storage rules deny client deletes, so the trash button on the teacher's
/// audio player has to round-trip through this callable. The function
/// verifies the caller is a teacher or schoolAdmin at the log's school, then
/// deletes the Storage object and clears the audio fields on the log doc.
typedef ComprehensionAudioCallableInvoker = Future<Object?> Function(
  String name,
  Map<String, dynamic> args,
);

Future<Object?> _defaultInvoker(String name, Map<String, dynamic> args) async {
  final callable = lumiFunctions.httpsCallable(name);
  final res = await callable.call<Object?>(args);
  return res.data;
}

class ComprehensionAudioService {
  final ComprehensionAudioCallableInvoker _invoke;

  ComprehensionAudioService({ComprehensionAudioCallableInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  /// Deletes the comprehension audio attached to a reading log. Returns true
  /// when the audio was deleted, false when the log already had no audio
  /// (raced with the cron or another delete) — both outcomes are safe for
  /// the UI to treat as "hide the player".
  Future<bool> deleteAudio({
    required String schoolId,
    required String logId,
  }) async {
    final data = await _invoke('deleteComprehensionAudio', {
      'schoolId': schoolId,
      'logId': logId,
    });
    if (data is Map && data['deleted'] == true) return true;
    return false;
  }

  /// Fetches a short-lived signed URL for a log's comprehension recording,
  /// along with its lifetime in seconds.
  ///
  /// The recording is a child's voice — PII at rest — so the Storage object is
  /// not client-readable; the `getComprehensionAudioUrl` callable authorizes
  /// the caller against the log's school and returns a signed URL to play. The
  /// URL expires (~15 min), so it is fetched on demand and cached only for its
  /// stated lifetime.
  Future<({String url, int expiresInSec})> getAudioUrl({
    required String schoolId,
    required String logId,
  }) async {
    final data = await _invoke('getComprehensionAudioUrl', {
      'schoolId': schoolId,
      'logId': logId,
    });
    if (data is Map &&
        data['url'] is String &&
        (data['url'] as String).isNotEmpty) {
      final ttl = data['expiresInSec'];
      return (
        url: data['url'] as String,
        expiresInSec: ttl is num ? ttl.toInt() : 600,
      );
    }
    throw StateError('No playback URL returned');
  }
}
