import 'package:cloud_firestore/cloud_firestore.dart';

/// Achievement Model for gamification
/// Tracks unlocked badges and milestones for students
class AchievementModel {
  final String id;
  final String name;
  final String description;
  final String icon; // emoji or icon name
  final AchievementCategory category;
  final AchievementRarity rarity;
  final int requiredValue; // e.g., 7 for week streak, 10 for 10 books
  final String requirementType; // 'streak', 'books', 'minutes', 'days'
  final DateTime earnedAt;
  final bool displayed; // Whether user has seen the achievement popup
  final Map<String, dynamic>? metadata; // Extra contextual data

  AchievementModel({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    required this.rarity,
    required this.requiredValue,
    required this.requirementType,
    required this.earnedAt,
    this.displayed = false,
    this.metadata,
  });

  /// Create from Firestore document
  factory AchievementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AchievementModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '🏆',
      category: AchievementCategory.values.firstWhere(
        (e) => e.toString() == 'AchievementCategory.${data['category']}',
        orElse: () => AchievementCategory.general,
      ),
      rarity: AchievementRarity.values.firstWhere(
        (e) => e.toString() == 'AchievementRarity.${data['rarity']}',
        orElse: () => AchievementRarity.common,
      ),
      requiredValue: data['requiredValue'] ?? 0,
      requirementType: data['requirementType'] ?? 'general',
      earnedAt: (data['earnedAt'] as Timestamp).toDate(),
      displayed: data['displayed'] ?? false,
      metadata: data['metadata'],
    );
  }

  /// Create from map (used by Cloud Functions)
  factory AchievementModel.fromMap(Map<String, dynamic> data) {
    return AchievementModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '🏆',
      category: AchievementCategory.values.firstWhere(
        (e) => e.toString() == 'AchievementCategory.${data['category']}',
        orElse: () => AchievementCategory.general,
      ),
      rarity: AchievementRarity.values.firstWhere(
        (e) => e.toString() == 'AchievementRarity.${data['rarity']}',
        orElse: () => AchievementRarity.common,
      ),
      requiredValue: data['requiredValue'] ?? 0,
      requirementType: data['requirementType'] ?? 'general',
      earnedAt: data['earnedAt'] is Timestamp
          ? (data['earnedAt'] as Timestamp).toDate()
          : DateTime.parse(data['earnedAt']),
      displayed: data['displayed'] ?? false,
      metadata: data['metadata'],
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'category': category.toString().split('.').last,
      'rarity': rarity.toString().split('.').last,
      'requiredValue': requiredValue,
      'requirementType': requirementType,
      'earnedAt': Timestamp.fromDate(earnedAt),
      'displayed': displayed,
      'metadata': metadata,
    };
  }

  /// Copy with modifications
  AchievementModel copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    AchievementCategory? category,
    AchievementRarity? rarity,
    int? requiredValue,
    String? requirementType,
    DateTime? earnedAt,
    bool? displayed,
    Map<String, dynamic>? metadata,
  }) {
    return AchievementModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      rarity: rarity ?? this.rarity,
      requiredValue: requiredValue ?? this.requiredValue,
      requirementType: requirementType ?? this.requirementType,
      earnedAt: earnedAt ?? this.earnedAt,
      displayed: displayed ?? this.displayed,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Achievement categories for organization
enum AchievementCategory {
  streak, // Consecutive reading days
  books, // Books read milestones
  minutes, // Time spent reading
  readingDays, // Total days read
  levelProgress, // Reading level improvements
  genre, // Genre diversity
  special, // Special events or challenges
  general, // Miscellaneous
}

/// Achievement rarity levels
enum AchievementRarity {
  common, // Easy to get (bronze)
  uncommon, // Moderate effort (silver)
  rare, // Significant achievement (gold)
  epic, // Very difficult (purple)
  legendary, // Extremely rare (rainbow)
}

/// Predefined achievement templates
class AchievementTemplates {
  /// Streak achievements
  static const List<Map<String, dynamic>> streakAchievements = [
    {
      'id': 'week_streak',
      'name': 'Week Warrior',
      'description': 'Read for 7 days in a row!',
      'icon': '🔥',
      'category': 'streak',
      'rarity': 'uncommon',
      'requiredValue': 7,
      'requirementType': 'streak',
    },
    {
      'id': 'two_week_streak',
      'name': 'Fortnight Fanatic',
      'description': 'Read for 14 days in a row!',
      'icon': '🔥🔥',
      'category': 'streak',
      'rarity': 'rare',
      'requiredValue': 14,
      'requirementType': 'streak',
    },
    {
      'id': 'month_streak',
      'name': 'Monthly Master',
      'description': 'Read for 30 days in a row!',
      'icon': '🌟',
      'category': 'streak',
      'rarity': 'epic',
      'requiredValue': 30,
      'requirementType': 'streak',
    },
    {
      'id': 'hundred_day_streak',
      'name': 'Century Champion',
      'description': 'Read for 100 days in a row!',
      'icon': '💯',
      'category': 'streak',
      'rarity': 'legendary',
      'requiredValue': 100,
      'requirementType': 'streak',
    },
  ];

  /// Book count achievements
  static const List<Map<String, dynamic>> bookAchievements = [
    {
      'id': 'five_books',
      'name': 'Book Beginner',
      'description': 'Read 5 books!',
      'icon': '📖',
      'category': 'books',
      'rarity': 'common',
      'requiredValue': 5,
      'requirementType': 'books',
    },
    {
      'id': 'ten_books',
      'name': 'Book Collector',
      'description': 'Read 10 books!',
      'icon': '📚',
      'category': 'books',
      'rarity': 'uncommon',
      'requiredValue': 10,
      'requirementType': 'books',
    },
    {
      'id': 'twenty_five_books',
      'name': 'Avid Reader',
      'description': 'Read 25 books!',
      'icon': '📗',
      'category': 'books',
      'rarity': 'rare',
      'requiredValue': 25,
      'requirementType': 'books',
    },
    {
      'id': 'fifty_books',
      'name': 'Bookworm',
      'description': 'Read 50 books!',
      'icon': '🐛',
      'category': 'books',
      'rarity': 'epic',
      'requiredValue': 50,
      'requirementType': 'books',
    },
    {
      'id': 'hundred_books',
      'name': 'Reading Legend',
      'description': 'Read 100 books!',
      'icon': '🏆',
      'category': 'books',
      'rarity': 'legendary',
      'requiredValue': 100,
      'requirementType': 'books',
    },
  ];

  /// Time-based achievements
  static const List<Map<String, dynamic>> timeAchievements = [
    {
      'id': 'five_hours',
      'name': 'Hour Hand',
      'description': 'Read for 5 hours total!',
      'icon': '⏰',
      'category': 'minutes',
      'rarity': 'common',
      'requiredValue': 300, // minutes
      'requirementType': 'minutes',
    },
    {
      'id': 'ten_hours',
      'name': 'Time Traveler',
      'description': 'Read for 10 hours total!',
      'icon': '⌚',
      'category': 'minutes',
      'rarity': 'uncommon',
      'requiredValue': 600,
      'requirementType': 'minutes',
    },
    {
      'id': 'twenty_five_hours',
      'name': 'Marathon Reader',
      'description': 'Read for 25 hours total!',
      'icon': '🏃',
      'category': 'minutes',
      'rarity': 'rare',
      'requiredValue': 1500,
      'requirementType': 'minutes',
    },
    {
      'id': 'fifty_hours',
      'name': 'Time Master',
      'description': 'Read for 50 hours total!',
      'icon': '⏳',
      'category': 'minutes',
      'rarity': 'epic',
      'requiredValue': 3000,
      'requirementType': 'minutes',
    },
    {
      'id': 'hundred_hours',
      'name': 'Eternal Reader',
      'description': 'Read for 100 hours total!',
      'icon': '♾️',
      'category': 'minutes',
      'rarity': 'legendary',
      'requiredValue': 6000,
      'requirementType': 'minutes',
    },
  ];

  /// Reading days achievements
  static const List<Map<String, dynamic>> daysAchievements = [
    {
      'id': 'ten_days',
      'name': 'Decade Reader',
      'description': 'Read on 10 different days!',
      'icon': '📅',
      'category': 'readingDays',
      'rarity': 'common',
      'requiredValue': 10,
      'requirementType': 'days',
    },
    {
      'id': 'thirty_days',
      'name': 'Monthly Reader',
      'description': 'Read on 30 different days!',
      'icon': '🗓️',
      'category': 'readingDays',
      'rarity': 'uncommon',
      'requiredValue': 30,
      'requirementType': 'days',
    },
    {
      'id': 'fifty_days',
      'name': 'Consistent Reader',
      'description': 'Read on 50 different days!',
      'icon': '📆',
      'category': 'readingDays',
      'rarity': 'rare',
      'requiredValue': 50,
      'requirementType': 'days',
    },
    {
      'id': 'hundred_days',
      'name': 'Century Reader',
      'description': 'Read on 100 different days!',
      'icon': '📊',
      'category': 'readingDays',
      'rarity': 'epic',
      'requiredValue': 100,
      'requirementType': 'days',
    },
  ];

  /// Get all achievement templates
  static List<Map<String, dynamic>> get allTemplates => [
        ...streakAchievements,
        ...bookAchievements,
        ...timeAchievements,
        ...daysAchievements,
      ];

  /// Get achievement template by ID
  static Map<String, dynamic>? getTemplate(String id) {
    try {
      return allTemplates.firstWhere((template) => template['id'] == id);
    } catch (e) {
      return null;
    }
  }

  /// Check if achievement should be unlocked based on stats
  static List<Map<String, dynamic>> checkAchievementsForStats({
    required int currentStreak,
    required int totalBooksRead,
    required int totalMinutesRead,
    required int totalReadingDays,
    required List<String> earnedAchievementIds,
  }) {
    final newAchievements = <Map<String, dynamic>>[];

    for (final template in allTemplates) {
      final id = template['id'] as String;

      // Skip if already earned
      if (earnedAchievementIds.contains(id)) continue;

      final requirementType = template['requirementType'] as String;
      final requiredValue = template['requiredValue'] as int;

      bool shouldUnlock = false;

      switch (requirementType) {
        case 'streak':
          shouldUnlock = currentStreak >= requiredValue;
          break;
        case 'books':
          shouldUnlock = totalBooksRead >= requiredValue;
          break;
        case 'minutes':
          shouldUnlock = totalMinutesRead >= requiredValue;
          break;
        case 'days':
          shouldUnlock = totalReadingDays >= requiredValue;
          break;
      }

      if (shouldUnlock) {
        newAchievements.add(template);
      }
    }

    return newAchievements;
  }
}

/// Extension for rarity colors
extension AchievementRarityExtension on AchievementRarity {
  /// Get color for rarity
  int get color {
    switch (this) {
      case AchievementRarity.common:
        return 0xFFCD7F32; // Bronze
      case AchievementRarity.uncommon:
        return 0xFFC0C0C0; // Silver
      case AchievementRarity.rare:
        return 0xFFFFD700; // Gold
      case AchievementRarity.epic:
        return 0xFFA855F7; // Purple
      case AchievementRarity.legendary:
        return 0xFFFF1493; // Deep pink (rainbow effect)
    }
  }

  /// Get display name
  String get displayName {
    switch (this) {
      case AchievementRarity.common:
        return 'Common';
      case AchievementRarity.uncommon:
        return 'Uncommon';
      case AchievementRarity.rare:
        return 'Rare';
      case AchievementRarity.epic:
        return 'Epic';
      case AchievementRarity.legendary:
        return 'Legendary';
    }
  }
}

/// Extension for category icons
extension AchievementCategoryExtension on AchievementCategory {
  /// Get icon for category
  String get icon {
    switch (this) {
      case AchievementCategory.streak:
        return '🔥';
      case AchievementCategory.books:
        return '📚';
      case AchievementCategory.minutes:
        return '⏰';
      case AchievementCategory.readingDays:
        return '📅';
      case AchievementCategory.levelProgress:
        return '📈';
      case AchievementCategory.genre:
        return '🎭';
      case AchievementCategory.special:
        return '⭐';
      case AchievementCategory.general:
        return '🏆';
    }
  }

  /// Get display name
  String get displayName {
    switch (this) {
      case AchievementCategory.streak:
        return 'Streak';
      case AchievementCategory.books:
        return 'Books';
      case AchievementCategory.minutes:
        return 'Time';
      case AchievementCategory.readingDays:
        return 'Reading Days';
      case AchievementCategory.levelProgress:
        return 'Level Progress';
      case AchievementCategory.genre:
        return 'Genre Explorer';
      case AchievementCategory.special:
        return 'Special';
      case AchievementCategory.general:
        return 'General';
    }
  }
}
