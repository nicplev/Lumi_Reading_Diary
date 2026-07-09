import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/achievements/achievement_presentation.dart';
import 'package:lumi_reading_tracker/data/models/achievement_model.dart';

void main() {
  AchievementModel template(String id) {
    return AchievementTemplates.defaultTemplates.firstWhere((t) => t.id == id);
  }

  group('achievement presentation', () {
    test('hides streak and unearned retired book goals', () {
      final displayable = displayableAchievementTemplates(earnedById: const {});

      expect(
        displayable.any((t) => t.category == AchievementCategory.streak),
        isFalse,
      );
      expect(
        displayable.any((t) => t.category == AchievementCategory.books),
        isFalse,
      );
      expect(
          displayable.map((t) => t.id), containsAll(['days_t1', 'first_log']));
    });

    test('shows retired book badges only when already earned', () {
      final earned = template('books_t4').copyWith(
        earnedAt: DateTime(2026, 7, 9, 10),
      );
      final earnedById = earnedAchievementMap([earned]);
      final displayable = displayableAchievementTemplates(
        earnedById: earnedById,
      );

      expect(
        displayable
            .where((t) => t.category == AchievementCategory.books)
            .map((t) => t.id),
        ['books_t4'],
      );
    });

    test('dedupes duplicate earned achievements by newest earnedAt', () {
      final older = template('books_t4').copyWith(
        earnedAt: DateTime(2026, 7, 7),
      );
      final newer = template('books_t4').copyWith(
        earnedAt: DateTime(2026, 7, 9),
      );

      final earnedById = earnedAchievementMap([older, newer]);
      final displays = earnedAchievementDisplays(earnedById: earnedById);

      expect(earnedById, hasLength(1));
      expect(earnedById['books_t4']!.earnedAt, newer.earnedAt);
      expect(displays, hasLength(1));
      expect(displays.single.template.id, 'books_t4');
      expect(displays.single.earned.earnedAt, newer.earnedAt);
    });
  });
}
