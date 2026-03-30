import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/reading_level_service.dart';

void main() {
  group('ReadingLevelService', () {
    late FakeFirebaseFirestore firestore;
    late ReadingLevelService service;
    final now = DateTime(2026, 3, 15, 8, 0, 0);

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ReadingLevelService(firestore: firestore);
    });

    Future<void> seedSchool({
      required String schoolId,
      required String schema,
      List<String>? customLevels,
    }) async {
      await firestore.collection('schools').doc(schoolId).set({
        'name': 'Test School',
        'createdBy': 'admin_1',
        'createdAt': Timestamp.fromDate(now),
        'levelSchema': schema,
        'customLevels': customLevels,
      });
    }

    test('loads A-Z level options with formatted labels', () async {
      await seedSchool(schoolId: 'school_az', schema: 'aToZ');

      final options = await service.loadSchoolLevels('school_az');

      expect(options.length, 26);
      expect(options.first.value, 'A');
      expect(options.first.shortLabel, 'A');
      expect(options.first.displayLabel, 'Level A');
      expect(options.last.value, 'Z');
    });

    test('normalizes legacy level labels to canonical stored values', () async {
      await seedSchool(schoolId: 'school_pm', schema: 'pmBenchmark');
      final options = await service.loadSchoolLevels('school_pm');

      expect(
        service.normalizeLevel('Level 12', options: options),
        '12',
      );
      expect(
        service.normalizeLevel('PM 12', options: options),
        '12',
      );
      expect(
        service.normalizeLevel('12', options: options),
        '12',
      );
    });

    test('compares PM Benchmark levels by schema order instead of string order',
        () async {
      await seedSchool(schoolId: 'school_pm', schema: 'pmBenchmark');
      final options = await service.loadSchoolLevels('school_pm');

      expect(
        service.compareLevels('2', '10', options: options),
        lessThan(0),
      );
      expect(
        service.compareLevels('10', '2', options: options),
        greaterThan(0),
      );
    });

    test('handles custom levels case-insensitively', () async {
      await seedSchool(
        schoolId: 'school_custom',
        schema: 'custom',
        customLevels: const ['Blue', 'Green', 'Orange'],
      );
      final options = await service.loadSchoolLevels('school_custom');

      expect(service.normalizeLevel('green', options: options), 'Green');
      expect(service.formatLevelLabel('orange', options: options), 'Orange');
    });
  });
}
