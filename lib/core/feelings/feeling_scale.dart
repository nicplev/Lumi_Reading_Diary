import 'dart:ui';

import '../../data/models/reading_log_model.dart';

/// Single source of truth for mapping the categorical [ReadingFeeling] enum to
/// the numeric 1–5 mood scale, plus its canonical colour, label and blob asset.
///
/// Colours match the blob character art used by `BlobSelector`
/// (`lib/core/widgets/lumi/blob_selector.dart`). Keep this in sync if the art
/// palette ever changes — it is intentionally the one place that owns it.
extension FeelingScale on ReadingFeeling {
  /// Position on the 1–5 mood scale (hard = 1 … great = 5).
  int get value => switch (this) {
        ReadingFeeling.hard => 1,
        ReadingFeeling.tricky => 2,
        ReadingFeeling.okay => 3,
        ReadingFeeling.good => 4,
        ReadingFeeling.great => 5,
      };

  /// Canonical per-feeling colour (matches the blob art / [BlobSelector]).
  Color get color => switch (this) {
        ReadingFeeling.hard => const Color(0xFF6FA8DC),
        ReadingFeeling.tricky => const Color(0xFF7CB97C),
        ReadingFeeling.okay => const Color(0xFFE8C547),
        ReadingFeeling.good => const Color(0xFFF5A347),
        ReadingFeeling.great => const Color(0xFFE86B6B),
      };

  /// Short display label.
  String get label => switch (this) {
        ReadingFeeling.hard => 'Hard',
        ReadingFeeling.tricky => 'Tricky',
        ReadingFeeling.okay => 'Okay',
        ReadingFeeling.good => 'Good',
        ReadingFeeling.great => 'Great',
      };

  /// Blob character asset path.
  String get asset => 'assets/blobs/blob-$name.png';
}

/// Reverse lookup: the [ReadingFeeling] for a 1–5 scale value, or null if the
/// value is out of range. Values are clamped/rounded by callers as needed.
ReadingFeeling? feelingFromValue(int value) {
  for (final f in ReadingFeeling.values) {
    if (f.value == value) return f;
  }
  return null;
}

/// Y-axis tier labels keyed by scale value, used by the feelings line chart.
const Map<int, String> feelingTierByValue = {
  1: 'Hard',
  2: 'Tricky',
  3: 'Okay',
  4: 'Good',
  5: 'Great',
};
