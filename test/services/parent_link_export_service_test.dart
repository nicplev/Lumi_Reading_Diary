import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/parent_link_export_service.dart';

void main() {
  group('ParentLinkExportService', () {
    test('buildCsv includes operational columns and row values', () {
      final service = ParentLinkExportService();
      final csv = service.buildCsv(
        const [
          LinkCodeExportRow(
            studentName: 'Alex Reader',
            studentId: 'S-100',
            className: 'Class A',
            code: 'ABCD1234',
            status: 'active',
            createdAt: '2026-03-08',
            expiresAt: '2027-03-08',
            linkedParentCount: 1,
          ),
        ],
      );

      expect(csv, contains('Student Name'));
      expect(csv, contains('Student ID'));
      expect(csv, contains('Class'));
      expect(csv, contains('Link Code'));
      expect(csv, contains('Code Status'));
      expect(csv, contains('Created At'));
      expect(csv, contains('Expires At'));
      expect(csv, contains('Linked Parent Count'));
      expect(csv, contains('Alex Reader'));
      expect(csv, contains('ABCD1234'));
    });
  });
}
