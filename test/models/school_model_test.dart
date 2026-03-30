import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/school_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('SchoolModel', () {
    Map<String, dynamic> baseSchoolData() {
      return {
        'name': 'Test Primary School',
        'levelSchema': 'aToZ',
        'customLevels': null,
        'levelColors': null,
        'termDates': <String, dynamic>{},
        'quietHours': <String, dynamic>{},
        'timezone': 'Australia/Melbourne',
        'isActive': true,
        'createdAt': Timestamp.now(),
        'createdBy': 'admin-1',
      };
    }

    group('readingLevels getter', () {
      test('none schema returns empty list', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'none';
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.readingLevels, isEmpty);
      });

      test('aToZ schema returns A-Z letters', () async {
        final firestore = TestHelpers.createFakeFirestore();
        await firestore
            .collection('schools')
            .doc('s1')
            .set(baseSchoolData());
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.readingLevels, hasLength(26));
        expect(school.readingLevels.first, 'A');
        expect(school.readingLevels.last, 'Z');
      });

      test('numbered schema returns 1-100', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'numbered';
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.readingLevels, hasLength(100));
        expect(school.readingLevels.first, '1');
        expect(school.readingLevels.last, '100');
      });

      test('namedLevels schema returns customLevels', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'namedLevels';
        data['customLevels'] = ['Beginner', 'Intermediate', 'Advanced'];
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.readingLevels, ['Beginner', 'Intermediate', 'Advanced']);
      });

      test('colouredLevels schema returns customLevels', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'colouredLevels';
        data['customLevels'] = ['Red', 'Blue', 'Green'];
        data['levelColors'] = {
          'Red': '#FF0000',
          'Blue': '#0000FF',
          'Green': '#00FF00',
        };
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.readingLevels, ['Red', 'Blue', 'Green']);
        expect(school.levelColors?['Red'], '#FF0000');
      });
    });

    group('hasReadingLevels getter', () {
      test('returns false for none schema', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'none';
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.hasReadingLevels, isFalse);
      });

      test('returns true for aToZ schema', () async {
        final firestore = TestHelpers.createFakeFirestore();
        await firestore
            .collection('schools')
            .doc('s1')
            .set(baseSchoolData());
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.hasReadingLevels, isTrue);
      });

      test('returns true for numbered schema', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'numbered';
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.hasReadingLevels, isTrue);
      });
    });

    group('serialization round-trip', () {
      test('none schema survives round-trip', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'none';
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        // Write back
        await firestore
            .collection('schools')
            .doc('s2')
            .set(school.toFirestore());
        final doc2 = await firestore.collection('schools').doc('s2').get();
        final school2 = SchoolModel.fromFirestore(doc2);

        expect(school2.levelSchema, ReadingLevelSchema.none);
        expect(school2.hasReadingLevels, isFalse);
        expect(school2.readingLevels, isEmpty);
      });

      test('colouredLevels with levelColors survives round-trip', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'colouredLevels';
        data['customLevels'] = ['Red', 'Blue'];
        data['levelColors'] = {'Red': '#FF0000', 'Blue': '#0000FF'};
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        // Write back
        await firestore
            .collection('schools')
            .doc('s2')
            .set(school.toFirestore());
        final doc2 = await firestore.collection('schools').doc('s2').get();
        final school2 = SchoolModel.fromFirestore(doc2);

        expect(school2.levelSchema, ReadingLevelSchema.colouredLevels);
        expect(school2.customLevels, ['Red', 'Blue']);
        expect(school2.levelColors?['Red'], '#FF0000');
        expect(school2.levelColors?['Blue'], '#0000FF');
      });

      test('unknown schema falls back to aToZ', () async {
        final firestore = TestHelpers.createFakeFirestore();
        final data = baseSchoolData();
        data['levelSchema'] = 'unknownFutureSchema';
        await firestore.collection('schools').doc('s1').set(data);
        final doc = await firestore.collection('schools').doc('s1').get();
        final school = SchoolModel.fromFirestore(doc);

        expect(school.levelSchema, ReadingLevelSchema.aToZ);
        expect(school.hasReadingLevels, isTrue);
      });
    });
  });
}
