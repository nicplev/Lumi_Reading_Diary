import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';

/// Guardian×child quick-log preference getters (plan §6.4) — keyed by
/// guardian so separated households keep independent routines.
void main() {
  UserModel parent(Map<String, dynamic>? preferences) => UserModel(
        id: 'parent_1',
        email: 'p@example.com',
        fullName: 'Parent One',
        role: UserRole.parent,
        schoolId: 'school_1',
        createdAt: DateTime(2026, 1, 1),
        preferences: preferences,
      );

  test('missing preferences fall back cleanly', () {
    expect(parent(null).usualMinutesFor('s1'), isNull);
    expect(parent(null).pinnedBookTitleFor('s1'), isNull);
    expect(parent(const {}).usualMinutesFor('s1'), isNull);
    expect(
        parent(const {'quickLog': 'garbage'}).usualMinutesFor('s1'), isNull);
  });

  test('per-child values resolve independently', () {
    final p = parent(const {
      'quickLog': {
        's1': {'usualMinutes': 15, 'pinnedBookTitle': 'Dog Man'},
        's2': {'usualMinutes': 25},
      },
    });
    expect(p.usualMinutesFor('s1'), 15);
    expect(p.pinnedBookTitleFor('s1'), 'Dog Man');
    expect(p.usualMinutesFor('s2'), 25);
    expect(p.pinnedBookTitleFor('s2'), isNull);
    expect(p.usualMinutesFor('s3'), isNull);
  });

  test('blank pinned titles are treated as unset', () {
    final p = parent(const {
      'quickLog': {
        's1': {'pinnedBookTitle': '   '},
      },
    });
    expect(p.pinnedBookTitleFor('s1'), isNull);
  });
}
