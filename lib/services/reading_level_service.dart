import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/reading_level_option.dart';
import '../data/models/school_model.dart';
import 'firebase_service.dart';

class ReadingLevelService {
  ReadingLevelService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseService.instance.firestore;

  final FirebaseFirestore _firestore;
  final Map<String, List<ReadingLevelOption>> _optionsCache =
      <String, List<ReadingLevelOption>>{};

  Future<List<ReadingLevelOption>> loadSchoolLevels(
    String schoolId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _optionsCache.containsKey(schoolId)) {
      return _optionsCache[schoolId]!;
    }

    final schoolDoc =
        await _firestore.collection('schools').doc(schoolId).get();
    if (!schoolDoc.exists) {
      throw StateError('School not found: $schoolId');
    }

    final school = SchoolModel.fromFirestore(schoolDoc);

    if (school.levelSchema == ReadingLevelSchema.none) {
      _optionsCache[schoolId] = const [];
      return const [];
    }

    final options = school.readingLevels
        .asMap()
        .entries
        .map(
          (entry) => ReadingLevelOption(
            value: entry.value,
            shortLabel: _shortLabelForValue(
              entry.value,
              schema: school.levelSchema,
            ),
            displayLabel: _displayLabelForValue(
              entry.value,
              schema: school.levelSchema,
            ),
            sortIndex: entry.key,
            schema: school.levelSchema,
            colorHex: school.levelSchema == ReadingLevelSchema.colouredLevels &&
                    school.levelColors != null
                ? school.levelColors![entry.value]
                : null,
          ),
        )
        .toList(growable: false);

    _optionsCache[schoolId] = options;
    return options;
  }

  Future<bool> schoolHasReadingLevels(String schoolId) async {
    final schoolDoc =
        await _firestore.collection('schools').doc(schoolId).get();
    if (!schoolDoc.exists) return false;
    final school = SchoolModel.fromFirestore(schoolDoc);
    return school.hasReadingLevels;
  }

  ReadingLevelOption? resolveOption(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
  }) {
    final normalized = normalizeLevel(rawLevel, options: options);
    if (normalized == null) return null;
    for (final option in options) {
      if (option.value == normalized) return option;
    }
    return null;
  }

  String? normalizeLevel(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
  }) {
    final trimmed = rawLevel?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final rawTokens = _rawTokens(trimmed);
    for (final option in options) {
      final optionTokens = _optionTokens(option);
      for (final token in rawTokens) {
        if (optionTokens.contains(token)) {
          return option.value;
        }
      }
    }
    return null;
  }

  String formatLevelLabel(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
    String unsetLabel = 'Needs level',
    String unknownLabel = 'Review level',
  }) {
    final option = resolveOption(rawLevel, options: options);
    if (option != null) return option.displayLabel;

    final trimmed = rawLevel?.trim();
    if (trimmed == null || trimmed.isEmpty) return unsetLabel;

    return unknownLabel;
  }

  String formatCompactLabel(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
    String unsetLabel = 'Needs level',
    String unknownLabel = 'Review level',
  }) {
    final option = resolveOption(rawLevel, options: options);
    if (option != null) return option.shortLabel;

    final trimmed = rawLevel?.trim();
    if (trimmed == null || trimmed.isEmpty) return unsetLabel;

    return unknownLabel;
  }

  int? sortIndexForLevel(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
  }) {
    final option = resolveOption(rawLevel, options: options);
    return option?.sortIndex;
  }

  int compareLevels(
    String? levelA,
    String? levelB, {
    required List<ReadingLevelOption> options,
  }) {
    final indexA = sortIndexForLevel(levelA, options: options);
    final indexB = sortIndexForLevel(levelB, options: options);

    if (indexA != null && indexB != null) {
      return indexA.compareTo(indexB);
    }

    if (indexA != null) return -1;
    if (indexB != null) return 1;

    final hasAValue = levelA?.trim().isNotEmpty == true;
    final hasBValue = levelB?.trim().isNotEmpty == true;

    if (hasAValue && !hasBValue) return -1;
    if (!hasAValue && hasBValue) return 1;

    return (levelA ?? '').compareTo(levelB ?? '');
  }

  ReadingLevelOption? nextLevel(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
  }) {
    final option = resolveOption(rawLevel, options: options);
    if (option == null) return null;
    final nextIndex = option.sortIndex + 1;
    if (nextIndex >= options.length) return null;
    return options[nextIndex];
  }

  ReadingLevelOption? previousLevel(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
  }) {
    final option = resolveOption(rawLevel, options: options);
    if (option == null) return null;
    final previousIndex = option.sortIndex - 1;
    if (previousIndex < 0) return null;
    return options[previousIndex];
  }

  bool hasUnresolvedLevel(
    String? rawLevel, {
    required List<ReadingLevelOption> options,
  }) {
    final trimmed = rawLevel?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;
    return normalizeLevel(trimmed, options: options) == null;
  }

  String schemaDisplayName(List<ReadingLevelOption> options) {
    if (options.isEmpty) return 'No reading levels';

    switch (options.first.schema) {
      case ReadingLevelSchema.none:
        return 'No reading levels';
      case ReadingLevelSchema.aToZ:
        return 'A-Z levels';
      case ReadingLevelSchema.pmBenchmark:
        return 'PM Benchmark';
      case ReadingLevelSchema.lexile:
        return 'Lexile';
      case ReadingLevelSchema.numbered:
        return 'Numbered 1-100';
      case ReadingLevelSchema.namedLevels:
        return 'Named levels';
      case ReadingLevelSchema.colouredLevels:
        return 'Colour levels';
      case ReadingLevelSchema.custom:
        return 'Custom levels';
    }
  }

  String _displayLabelForValue(
    String value, {
    required ReadingLevelSchema schema,
  }) {
    switch (schema) {
      case ReadingLevelSchema.none:
        return value;
      case ReadingLevelSchema.aToZ:
        return 'Level $value';
      case ReadingLevelSchema.pmBenchmark:
        return 'PM $value';
      case ReadingLevelSchema.lexile:
        return value;
      case ReadingLevelSchema.numbered:
        return 'Level $value';
      case ReadingLevelSchema.namedLevels:
      case ReadingLevelSchema.colouredLevels:
        return value;
      case ReadingLevelSchema.custom:
        return value;
    }
  }

  String _shortLabelForValue(
    String value, {
    required ReadingLevelSchema schema,
  }) {
    switch (schema) {
      case ReadingLevelSchema.none:
        return value;
      case ReadingLevelSchema.aToZ:
        return value;
      case ReadingLevelSchema.pmBenchmark:
        return 'PM $value';
      case ReadingLevelSchema.lexile:
        return value;
      case ReadingLevelSchema.numbered:
        return value;
      case ReadingLevelSchema.namedLevels:
      case ReadingLevelSchema.colouredLevels:
        return value;
      case ReadingLevelSchema.custom:
        return value;
    }
  }

  Set<String> _rawTokens(String rawLevel) {
    final compact = _normalizeForComparison(rawLevel);
    final tokens = <String>{compact};

    final withoutLevel = compact.replaceFirst(RegExp(r'^LEVEL'), '');
    if (withoutLevel.isNotEmpty) tokens.add(withoutLevel);

    final withoutPm = compact.replaceFirst(RegExp(r'^PM'), '');
    if (withoutPm.isNotEmpty) tokens.add(withoutPm);

    return tokens;
  }

  Set<String> _optionTokens(ReadingLevelOption option) {
    return <String>{
      _normalizeForComparison(option.value),
      _normalizeForComparison(option.shortLabel),
      _normalizeForComparison(option.displayLabel),
    };
  }

  String _normalizeForComparison(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }
}
