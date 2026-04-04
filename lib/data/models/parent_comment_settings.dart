/// Per-school configuration for parent comment presets and free-text input
/// on the reading log screen.
///
/// Stored at `schools/{schoolId}.settings.parentComments` in Firestore.
class CommentPresetCategory {
  final String id;
  final String name;
  final List<String> chips;

  const CommentPresetCategory({
    required this.id,
    required this.name,
    required this.chips,
  });

  factory CommentPresetCategory.fromMap(Map<String, dynamic> map) {
    return CommentPresetCategory(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      chips: List<String>.from(map['chips'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'chips': chips,
    };
  }
}

class ParentCommentSettings {
  final bool enabled;
  final bool freeTextEnabled;
  final List<CommentPresetCategory> customPresets;

  const ParentCommentSettings({
    required this.enabled,
    required this.freeTextEnabled,
    required this.customPresets,
  });

  factory ParentCommentSettings.defaults() {
    return const ParentCommentSettings(
      enabled: true,
      freeTextEnabled: true,
      customPresets: [],
    );
  }

  factory ParentCommentSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return ParentCommentSettings.defaults();
    return ParentCommentSettings(
      enabled: map['enabled'] as bool? ?? true,
      freeTextEnabled: map['freeTextEnabled'] as bool? ?? true,
      customPresets: (map['customPresets'] as List<dynamic>?)
              ?.map((e) =>
                  CommentPresetCategory.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  bool get hasCustomPresets => customPresets.isNotEmpty;

  /// Returns the presets to display: custom if configured, otherwise the
  /// hardcoded defaults from CommentChips.
  Map<String, List<String>> get effectivePresets {
    if (hasCustomPresets) {
      return {for (var cat in customPresets) cat.name: cat.chips};
    }
    // Fallback handled by CommentChips.defaultCommentCategories
    return const {};
  }
}
