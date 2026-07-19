import '../../../data/models/reading_level_option.dart';
import '../../../data/models/student_model.dart';
import '../../../services/reading_level_service.dart';

/// Pure label/state helpers shared by the student-detail appbar pill and the
/// reading-level card. Extracted unchanged from the screen's former private
/// methods.

String readingLevelDisplayLabel(
  StudentModel student, {
  required List<ReadingLevelOption> options,
  required ReadingLevelService service,
}) {
  if (options.isEmpty) {
    final raw = student.currentReadingLevel?.trim();
    return raw == null || raw.isEmpty ? 'Needs level' : raw;
  }

  return service.formatLevelLabel(
    student.currentReadingLevel,
    options: options,
  );
}

String readingLevelCompactLabel(
  StudentModel student, {
  required List<ReadingLevelOption> options,
  required ReadingLevelService service,
}) {
  if (options.isEmpty) {
    final raw = student.currentReadingLevel?.trim();
    return raw == null || raw.isEmpty ? 'Needs level' : raw;
  }

  return service.formatCompactLabel(
    student.currentReadingLevel,
    options: options,
  );
}

bool isReadingLevelUnset(StudentModel student) {
  final raw = student.currentReadingLevel?.trim();
  return raw == null || raw.isEmpty;
}

bool isReadingLevelUnresolved(
  StudentModel student, {
  required List<ReadingLevelOption> options,
  required ReadingLevelService service,
}) {
  if (options.isEmpty) return false;
  return service.hasUnresolvedLevel(
    student.currentReadingLevel,
    options: options,
  );
}
