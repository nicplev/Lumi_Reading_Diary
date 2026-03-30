import 'school_model.dart';

class ReadingLevelOption {
  final String value;
  final String shortLabel;
  final String displayLabel;
  final int sortIndex;
  final ReadingLevelSchema schema;
  final String? colorHex;

  const ReadingLevelOption({
    required this.value,
    required this.shortLabel,
    required this.displayLabel,
    required this.sortIndex,
    required this.schema,
    this.colorHex,
  });
}
