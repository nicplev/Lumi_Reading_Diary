import 'package:flutter/foundation.dart';

/// Severity controls the banner's colour and icon.
///
/// Kept independent of [ServiceStatusSeverity] because the remote message is
/// authored by humans and its severity reflects editorial intent, not a
/// probe outcome.
enum RemoteMessageSeverity { info, warn, critical }

/// Decoded `status.json` payload from the Cloudflare status worker.
///
/// `version: 0, id: null` is the empty state — the banner is hidden. The
/// in-app client never *clears* its Hive cache when it receives empty
/// state, so a transient Worker blip can't wipe a real message.
@immutable
class RemoteMessage {
  const RemoteMessage({
    required this.version,
    required this.id,
    required this.message,
    required this.severity,
    required this.dismissible,
    required this.fetchedAt,
    this.updatedAt,
    this.minAppVersion,
    this.platforms,
  });

  /// `version` is monotonic. Bump it when re-publishing the same `id` to
  /// re-show after dismissal.
  final int version;
  final String? id;
  final String? message;
  final RemoteMessageSeverity severity;
  final bool dismissible;
  final DateTime? updatedAt;
  final DateTime fetchedAt;
  final String? minAppVersion;
  final List<String>? platforms;

  /// True iff there's actually a message to render.
  bool get isVisible => id != null && message != null && message!.isNotEmpty;

  /// Dismissal key — same `id` with a bumped `version` re-shows the banner
  /// even after the user dismissed the prior version. This is intentional:
  /// editors bump `version` precisely to re-grab attention.
  String get dismissalKey => '${version}_${id ?? ''}';

  factory RemoteMessage.fromJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
  }) {
    final severity = switch (json['severity']) {
      'critical' => RemoteMessageSeverity.critical,
      'warn' => RemoteMessageSeverity.warn,
      _ => RemoteMessageSeverity.info,
    };
    return RemoteMessage(
      version: (json['version'] as num?)?.toInt() ?? 0,
      id: json['id'] as String?,
      message: json['message'] as String?,
      severity: severity,
      dismissible: json['dismissible'] != false,
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      fetchedAt: fetchedAt,
      minAppVersion: json['minAppVersion'] as String?,
      platforms:
          (json['platforms'] as List?)?.whereType<String>().toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'id': id,
        'message': message,
        'severity': severity.name,
        'dismissible': dismissible,
        'updatedAt': updatedAt?.toIso8601String(),
        '_fetchedAt': fetchedAt.toIso8601String(),
        'minAppVersion': minAppVersion,
        'platforms': platforms,
      };

  /// Restores from the Hive cache (note the `_fetchedAt` key, written by
  /// [toJson] but never sent by the Worker).
  factory RemoteMessage.fromCache(Map<String, dynamic> json) {
    final fetched = json['_fetchedAt'] is String
        ? DateTime.tryParse(json['_fetchedAt'] as String) ?? DateTime.now()
        : DateTime.now();
    return RemoteMessage.fromJson(json, fetchedAt: fetched);
  }
}
