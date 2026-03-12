import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/isbn_assignment_service.dart';

void main() {
  group('IsbnAssignmentService.normalizeIsbn', () {
    test('normalizes valid ISBN-13 with separators', () {
      final value = IsbnAssignmentService.normalizeIsbn('978-0-7432-7356-5');
      expect(value, '9780743273565');
    });

    test('converts valid ISBN-10 into ISBN-13', () {
      final value = IsbnAssignmentService.normalizeIsbn('0-7432-7356-7');
      expect(value, '9780743273565');
    });

    test('rejects invalid values', () {
      expect(IsbnAssignmentService.normalizeIsbn('12345'), isNull);
      expect(IsbnAssignmentService.normalizeIsbn('ABCDEFGHIJ'), isNull);
    });
  });

  group('IsbnAssignmentService week helpers', () {
    test('calculates Monday-based start of week', () {
      final start = IsbnAssignmentService.startOfWeek(DateTime(2026, 3, 12));
      expect(start, DateTime(2026, 3, 9));
    });

    test('builds stable weekly allocation id', () {
      final id = IsbnAssignmentService.buildWeeklyAllocationId(
        studentId: 'student_1',
        weekStart: DateTime(2026, 3, 9),
      );
      expect(id, 'isbn_student_1_20260309');
    });
  });
}
