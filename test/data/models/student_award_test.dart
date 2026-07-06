import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/characters/lumi_character.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';

Future<StudentModel> _student(Map<String, dynamic> extra) async {
  final fs = FakeFirebaseFirestore();
  final ref = fs.collection('schools').doc('s1').collection('students').doc('st1');
  await ref.set({
    'firstName': 'Lily',
    'lastName': 'Tale',
    'schoolId': 's1',
    'classId': 'c1',
    'characterId': 'lumi_shark',
    'isActive': true,
    ...extra,
  });
  return StudentModel.fromFirestore(await ref.get());
}

void main() {
  group('LumiCharacters awards', () {
    test('findById resolves the award characters to the special-lumi folder', () {
      expect(LumiCharacters.findById('gold_lumi')?.assetPath,
          'assets/special lumi/Gold Lumi.png');
      expect(LumiCharacters.findById('special_lumi')?.assetPath,
          'assets/special lumi/Special Lumi.png');
    });

    test('award characters are NOT in the selectable picker list', () {
      final selectableIds = LumiCharacters.all.map((c) => c.id).toSet();
      expect(selectableIds.contains('gold_lumi'), isFalse);
      expect(selectableIds.contains('special_lumi'), isFalse);
    });
  });

  group('StudentModel award fields + displayCharacterId', () {
    test('no award → displays the chosen character', () async {
      final s = await _student({});
      expect(s.autoAward, isNull);
      expect(s.manualAward, isNull);
      expect(s.hasActiveAward, isFalse);
      expect(s.displayCharacterId, 'lumi_shark');
    });

    test('autoAward overrides the chosen character', () async {
      final s = await _student({
        'autoAward': {
          'characterId': 'gold_lumi',
          'name': 'Reader of the Week',
          'weekOf': '2026-06-29',
        },
      });
      expect(s.autoAward?.characterId, 'gold_lumi');
      expect(s.autoAward?.weekOf, '2026-06-29');
      expect(s.displayCharacterId, 'gold_lumi');
      expect(s.activeAwardName, 'Reader of the Week');
    });

    test('manualAward takes precedence over autoAward', () async {
      final s = await _student({
        'autoAward': {'characterId': 'gold_lumi', 'name': 'Reader of the Week'},
        'manualAward': {
          'characterId': 'special_lumi',
          'name': 'Star Reader',
          'awardedBy': 'teacher_1',
        },
      });
      expect(s.displayCharacterId, 'special_lumi');
      expect(s.activeAwardName, 'Star Reader');
      expect(s.manualAward?.awardedBy, 'teacher_1');
    });

    test('award fields round-trip through toFirestore', () async {
      final s = await _student({
        'manualAward': {'characterId': 'special_lumi', 'name': 'Star Reader'},
      });
      final map = s.toFirestore();
      expect((map['manualAward'] as Map)['characterId'], 'special_lumi');
      expect(map.containsKey('autoAward'), isFalse);
    });
  });
}
