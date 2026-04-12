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
  final int requiredValue; // e.g., 5 for 5-day streak, 10 for 10 books
  final String requirementType; // 'streak', 'books', 'minutes', 'days'
  final DateTime earnedAt;
  final bool displayed; // Whether user has seen the achievement popup
  final Map<String, dynamic>? metadata; // Extra contextual data
  final int? customColor; // Optional admin-configured color override (ARGB int); not persisted to Firestore

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
    this.customColor,
  });

  /// The color to use for all rendering. Uses admin-configured color when set,
  /// otherwise falls back to the rarity-based default.
  int get effectiveColor => customColor ?? rarity.color;

  /// Create from Firestore document
  factory AchievementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AchievementModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '🏆',
      category: AchievementCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => AchievementCategory.general,
      ),
      rarity: AchievementRarity.values.firstWhere(
        (e) => e.name == data['rarity'],
        orElse: () => AchievementRarity.common,
      ),
      requiredValue: data['requiredValue'] ?? 0,
      requirementType: data['requirementType'] ?? 'general',
      earnedAt: data['earnedAt'] == null
          ? DateTime.now()
          : (data['earnedAt'] as Timestamp).toDate(),
      displayed: data['displayed'] ?? false,
      metadata: data['metadata'],
    );
  }

  /// Create from map (used for Firestore array entries written by Cloud Functions)
  factory AchievementModel.fromMap(Map<String, dynamic> data) {
    return AchievementModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '🏆',
      category: AchievementCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => AchievementCategory.general,
      ),
      rarity: AchievementRarity.values.firstWhere(
        (e) => e.name == data['rarity'],
        orElse: () => AchievementRarity.common,
      ),
      requiredValue: data['requiredValue'] ?? 0,
      requirementType: data['requirementType'] ?? 'general',
      earnedAt: data['earnedAt'] == null
          ? DateTime.now()
          : data['earnedAt'] is Timestamp
              ? (data['earnedAt'] as Timestamp).toDate()
              : DateTime.tryParse(data['earnedAt'].toString()) ?? DateTime.now(),
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
      'category': category.name,
      'rarity': rarity.name,
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
    int? customColor,
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
      customColor: customColor ?? this.customColor,
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
  legendary, // Extremely rare (deep pink)
}

/// School-configurable achievement thresholds.
/// Stored in Firestore under schools/{schoolId}/settings.achievementThresholds.
/// Falls back to [AchievementThresholds.defaults] when not configured.
class AchievementThresholds {
  final List<int> streak;      // 5 tiers
  final List<int> books;       // 5 tiers
  final List<int> minutes;     // 5 tiers (stored as minutes, displayed as hours)
  final List<int> readingDays; // 4 tiers

  const AchievementThresholds({
    required this.streak,
    required this.books,
    required this.minutes,
    required this.readingDays,
  });

  static const AchievementThresholds defaults = AchievementThresholds(
    streak:      [5, 10, 20, 50, 100],
    books:       [5, 10, 25, 50, 100],
    minutes:     [300, 600, 1500, 3000, 6000],
    readingDays: [10, 30, 50, 100],
  );

  factory AchievementThresholds.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    return AchievementThresholds(
      streak:      _parseList(map['streak'],      defaults.streak),
      books:       _parseList(map['books'],       defaults.books),
      minutes:     _parseList(map['minutes'],     defaults.minutes),
      readingDays: _parseList(map['readingDays'], defaults.readingDays),
    );
  }

  static List<int> _parseList(dynamic value, List<int> fallback) {
    if (value == null) return fallback;
    try {
      final list = (value as List).map((e) => (e as num).toInt()).toList();
      return list.length == fallback.length ? list : fallback;
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic> toMap() => {
    'streak':      streak,
    'books':       books,
    'minutes':     minutes,
    'readingDays': readingDays,
  };
}

// ─── Achievement Customization ────────────────────────────────────────────────

/// Admin-configured overrides for one achievement tier (name and/or color).
/// Stored in Firestore under schools/{schoolId}/settings.achievementCustomization.
class AchievementTierCustomization {
  final String? name;  // null = use template default name
  final int? color;    // null = use rarity default color; stored as ARGB int (0xFFrrggbb)

  const AchievementTierCustomization({this.name, this.color});

  factory AchievementTierCustomization.fromMap(dynamic map) {
    if (map is! Map<String, dynamic>) return const AchievementTierCustomization();
    return AchievementTierCustomization(
      name:  map['name'] as String?,
      color: _hexToArgb(map['color'] as String?),
    );
  }

  /// Converts a CSS hex string (e.g. "#FF1493") to an ARGB int (e.g. 0xFFFF1493).
  static int? _hexToArgb(String? hex) {
    if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
    return int.tryParse('FF${hex.substring(1)}', radix: 16);
  }
}

/// Per-category, per-tier name and color overrides from school settings.
/// Falls back to [AchievementCustomization.empty] when not configured.
class AchievementCustomization {
  final List<AchievementTierCustomization> streak;      // 5 tiers
  final List<AchievementTierCustomization> books;       // 5 tiers
  final List<AchievementTierCustomization> minutes;     // 5 tiers
  final List<AchievementTierCustomization> readingDays; // 4 tiers

  const AchievementCustomization({
    required this.streak,
    required this.books,
    required this.minutes,
    required this.readingDays,
  });

  static final AchievementCustomization empty = AchievementCustomization(
    streak:      List.filled(5, const AchievementTierCustomization()),
    books:       List.filled(5, const AchievementTierCustomization()),
    minutes:     List.filled(5, const AchievementTierCustomization()),
    readingDays: List.filled(4, const AchievementTierCustomization()),
  );

  factory AchievementCustomization.fromMap(Map<String, dynamic>? map) {
    if (map == null) return empty;
    return AchievementCustomization(
      streak:      _parseTiers(map['streak'],      5),
      books:       _parseTiers(map['books'],       5),
      minutes:     _parseTiers(map['minutes'],     5),
      readingDays: _parseTiers(map['readingDays'], 4),
    );
  }

  static List<AchievementTierCustomization> _parseTiers(dynamic raw, int expectedLength) {
    if (raw is! List) return List.filled(expectedLength, const AchievementTierCustomization());
    final tiers = raw.map(AchievementTierCustomization.fromMap).toList();
    // Pad with empties if shorter, trim if longer
    while (tiers.length < expectedLength) { tiers.add(const AchievementTierCustomization()); }
    return tiers.take(expectedLength).toList();
  }
}

/// Generates and validates achievement templates.
/// All achievement IDs use stable rarity-tier keys (streak_t1…t5, etc.)
/// so they remain correct when school admins adjust thresholds.
class AchievementTemplates {
  // ─── Per-tier metadata (threshold-agnostic) ───────────────────────────────

  static const _streakMeta = [
    {'id': 'streak_t1', 'name': 'Weekly Winner',    'icon': '🔥',  'rarity': 'common'},
    {'id': 'streak_t2', 'name': 'Fortnight Fan',    'icon': '🔥',  'rarity': 'uncommon'},
    {'id': 'streak_t3', 'name': 'Month Warrior',    'icon': '🌟',  'rarity': 'rare'},
    {'id': 'streak_t4', 'name': 'Season Streak',    'icon': '⭐',  'rarity': 'epic'},
    {'id': 'streak_t5', 'name': 'Century Champion', 'icon': '💯',  'rarity': 'legendary'},
  ];

  static const _booksMeta = [
    {'id': 'books_t1', 'name': 'Book Beginner',  'icon': '📖',  'rarity': 'common'},
    {'id': 'books_t2', 'name': 'Book Collector', 'icon': '📚',  'rarity': 'uncommon'},
    {'id': 'books_t3', 'name': 'Avid Reader',    'icon': '📗',  'rarity': 'rare'},
    {'id': 'books_t4', 'name': 'Bookworm',       'icon': '🐛',  'rarity': 'epic'},
    {'id': 'books_t5', 'name': 'Reading Legend', 'icon': '🏆',  'rarity': 'legendary'},
  ];

  static const _minutesMeta = [
    {'id': 'minutes_t1', 'name': 'Hour Hand',       'icon': '⏰',  'rarity': 'common'},
    {'id': 'minutes_t2', 'name': 'Time Traveler',   'icon': '⌚',  'rarity': 'uncommon'},
    {'id': 'minutes_t3', 'name': 'Marathon Reader', 'icon': '🏃',  'rarity': 'rare'},
    {'id': 'minutes_t4', 'name': 'Time Master',     'icon': '⏳',  'rarity': 'epic'},
    {'id': 'minutes_t5', 'name': 'Eternal Reader',  'icon': '♾️', 'rarity': 'legendary'},
  ];

  static const _daysMeta = [
    {'id': 'days_t1', 'name': 'Decade Reader',    'icon': '📅',  'rarity': 'common'},
    {'id': 'days_t2', 'name': 'Monthly Reader',   'icon': '🗓️', 'rarity': 'uncommon'},
    {'id': 'days_t3', 'name': 'Consistent Reader','icon': '📆',  'rarity': 'rare'},
    {'id': 'days_t4', 'name': 'Century Reader',   'icon': '📊',  'rarity': 'epic'},
  ];

  // ─── Dynamic template generation ─────────────────────────────────────────

  /// Generates all achievement templates using [thresholds] and optional [customization].
  /// Custom names and colors from [customization] override the built-in defaults.
  /// Includes the special first_log achievement which is not threshold-dependent.
  static List<AchievementModel> generateTemplates(
    AchievementThresholds thresholds, {
    AchievementCustomization? customization,
  }) {
    final custom = customization ?? AchievementCustomization.empty;
    final templates = <AchievementModel>[];
    final now = DateTime.fromMillisecondsSinceEpoch(0); // placeholder earnedAt for templates

    // Streak
    for (int i = 0; i < _streakMeta.length; i++) {
      final meta = _streakMeta[i];
      final value = thresholds.streak[i];
      final c = custom.streak[i];
      templates.add(AchievementModel(
        id: meta['id']!,
        name: (c.name?.isNotEmpty == true) ? c.name! : meta['name']!,
        description: 'Read for $value school days in a row!',
        icon: meta['icon']!,
        category: AchievementCategory.streak,
        rarity: _rarityFromString(meta['rarity']!),
        requiredValue: value,
        requirementType: 'streak',
        earnedAt: now,
        customColor: c.color,
      ));
    }

    // Books
    for (int i = 0; i < _booksMeta.length; i++) {
      final meta = _booksMeta[i];
      final value = thresholds.books[i];
      final c = custom.books[i];
      templates.add(AchievementModel(
        id: meta['id']!,
        name: (c.name?.isNotEmpty == true) ? c.name! : meta['name']!,
        description: 'Read $value books!',
        icon: meta['icon']!,
        category: AchievementCategory.books,
        rarity: _rarityFromString(meta['rarity']!),
        requiredValue: value,
        requirementType: 'books',
        earnedAt: now,
        customColor: c.color,
      ));
    }

    // Minutes (displayed as hours in description)
    for (int i = 0; i < _minutesMeta.length; i++) {
      final meta = _minutesMeta[i];
      final value = thresholds.minutes[i];
      final hours = value ~/ 60;
      final c = custom.minutes[i];
      templates.add(AchievementModel(
        id: meta['id']!,
        name: (c.name?.isNotEmpty == true) ? c.name! : meta['name']!,
        description: 'Read for $hours hours total!',
        icon: meta['icon']!,
        category: AchievementCategory.minutes,
        rarity: _rarityFromString(meta['rarity']!),
        requiredValue: value,
        requirementType: 'minutes',
        earnedAt: now,
        customColor: c.color,
      ));
    }

    // Reading days
    for (int i = 0; i < _daysMeta.length; i++) {
      final meta = _daysMeta[i];
      final value = thresholds.readingDays[i];
      final c = custom.readingDays[i];
      templates.add(AchievementModel(
        id: meta['id']!,
        name: (c.name?.isNotEmpty == true) ? c.name! : meta['name']!,
        description: 'Read on $value different days!',
        icon: meta['icon']!,
        category: AchievementCategory.readingDays,
        rarity: _rarityFromString(meta['rarity']!),
        requiredValue: value,
        requirementType: 'days',
        earnedAt: now,
        customColor: c.color,
      ));
    }

    // Special: first log (not threshold-dependent)
    templates.add(AchievementModel(
      id: 'first_log',
      name: 'First Chapter',
      description: 'Logged your very first reading session!',
      icon: '📖',
      category: AchievementCategory.special,
      rarity: AchievementRarity.common,
      requiredValue: 1,
      requirementType: 'days',
      earnedAt: now,
    ));

    return templates;
  }

  /// Shortcut: generate templates using default thresholds.
  static List<AchievementModel> get defaultTemplates =>
      generateTemplates(AchievementThresholds.defaults);

  static AchievementRarity _rarityFromString(String value) =>
      AchievementRarity.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AchievementRarity.common,
      );

  // ─── Template lookup ──────────────────────────────────────────────────────

  /// Find a template by ID from a pre-generated list.
  static AchievementModel? findById(
      List<AchievementModel> templates, String id) {
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  // ─── Client-side unlock check ─────────────────────────────────────────────

  /// Returns achievements that should now be unlocked based on current stats.
  /// The Cloud Function is authoritative for awarding; this is for local UI checks.
  static List<AchievementModel> checkAchievementsForStats({
    required int currentStreak,
    required int totalBooksRead,
    required int totalMinutesRead,
    required int totalReadingDays,
    required List<String> earnedAchievementIds,
    AchievementThresholds thresholds = AchievementThresholds.defaults,
  }) {
    final templates = generateTemplates(thresholds);
    final newAchievements = <AchievementModel>[];

    for (final template in templates) {
      if (earnedAchievementIds.contains(template.id)) continue;

      bool shouldUnlock = false;
      switch (template.requirementType) {
        case 'streak':
          shouldUnlock = currentStreak >= template.requiredValue;
          break;
        case 'books':
          shouldUnlock = totalBooksRead >= template.requiredValue;
          break;
        case 'minutes':
          shouldUnlock = totalMinutesRead >= template.requiredValue;
          break;
        case 'days':
          shouldUnlock = totalReadingDays >= template.requiredValue;
          break;
      }

      if (shouldUnlock) newAchievements.add(template);
    }

    return newAchievements;
  }

  // ─── Near-miss calculation ────────────────────────────────────────────────

  /// Returns the single closest unearned achievement (progress >= 0.0).
  /// Used for near-miss nudges on parent home and teacher dashboard.
  static ({AchievementModel achievement, double progress})? nearestUnearned({
    required int currentStreak,
    required int totalBooksRead,
    required int totalMinutesRead,
    required int totalReadingDays,
    required List<String> earnedAchievementIds,
    AchievementThresholds thresholds = AchievementThresholds.defaults,
    AchievementCustomization? customization,
    double minProgress = 0.8,
  }) {
    final templates = generateTemplates(thresholds, customization: customization);
    AchievementModel? closest;
    double closestProgress = -1;

    for (final template in templates) {
      if (earnedAchievementIds.contains(template.id)) continue;
      if (template.requiredValue <= 0) continue;

      int current;
      switch (template.requirementType) {
        case 'streak':
          current = currentStreak;
          break;
        case 'books':
          current = totalBooksRead;
          break;
        case 'minutes':
          current = totalMinutesRead;
          break;
        case 'days':
          current = totalReadingDays;
          break;
        default:
          continue;
      }

      final progress = current / template.requiredValue;
      if (progress >= minProgress && progress > closestProgress) {
        closestProgress = progress;
        closest = template;
      }
    }

    if (closest == null) return null;
    return (achievement: closest, progress: closestProgress.clamp(0.0, 1.0));
  }

  /// Returns near-miss achievements per student for teacher dashboard nudges.
  /// Returns up to [maxNudges] entries where progress >= [minProgress].
  static List<({String studentFirstName, AchievementModel achievement, double progress, int remaining})>
      nearMissNudgesForStudents({
    required List<({
      String firstName,
      int currentStreak,
      int totalBooksRead,
      int totalMinutesRead,
      int totalReadingDays,
      List<String> earnedAchievementIds,
    })> students,
    AchievementThresholds thresholds = AchievementThresholds.defaults,
    AchievementCustomization? customization,
    double minProgress = 0.8,
    int maxNudges = 3,
  }) {
    final nudges = <({String studentFirstName, AchievementModel achievement, double progress, int remaining})>[];

    for (final student in students) {
      final result = nearestUnearned(
        currentStreak: student.currentStreak,
        totalBooksRead: student.totalBooksRead,
        totalMinutesRead: student.totalMinutesRead,
        totalReadingDays: student.totalReadingDays,
        earnedAchievementIds: student.earnedAchievementIds,
        thresholds: thresholds,
        customization: customization,
        minProgress: minProgress,
      );
      if (result == null) continue;

      int current;
      switch (result.achievement.requirementType) {
        case 'streak':  current = student.currentStreak;      break;
        case 'books':   current = student.totalBooksRead;     break;
        case 'minutes': current = student.totalMinutesRead;   break;
        case 'days':    current = student.totalReadingDays;   break;
        default:        continue;
      }

      final remaining = result.achievement.requiredValue - current;
      if (remaining <= 0) continue;

      nudges.add((
        studentFirstName: student.firstName,
        achievement: result.achievement,
        progress: result.progress,
        remaining: remaining,
      ));

      if (nudges.length >= maxNudges) break;
    }

    return nudges;
  }
}

/// Extension for rarity colors
extension AchievementRarityExtension on AchievementRarity {
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
        return 0xFFFF1493; // Deep pink
    }
  }

  String get displayName {
    switch (this) {
      case AchievementRarity.common:    return 'Common';
      case AchievementRarity.uncommon:  return 'Uncommon';
      case AchievementRarity.rare:      return 'Rare';
      case AchievementRarity.epic:      return 'Epic';
      case AchievementRarity.legendary: return 'Legendary';
    }
  }
}

/// Extension for category icons
extension AchievementCategoryExtension on AchievementCategory {
  String get icon {
    switch (this) {
      case AchievementCategory.streak:       return '🔥';
      case AchievementCategory.books:        return '📚';
      case AchievementCategory.minutes:      return '⏰';
      case AchievementCategory.readingDays:  return '📅';
      case AchievementCategory.levelProgress:return '📈';
      case AchievementCategory.genre:        return '🎭';
      case AchievementCategory.special:      return '⭐';
      case AchievementCategory.general:      return '🏆';
    }
  }

  String get displayName {
    switch (this) {
      case AchievementCategory.streak:       return 'Streak';
      case AchievementCategory.books:        return 'Books';
      case AchievementCategory.minutes:      return 'Time';
      case AchievementCategory.readingDays:  return 'Reading Days';
      case AchievementCategory.levelProgress:return 'Level Progress';
      case AchievementCategory.genre:        return 'Genre Explorer';
      case AchievementCategory.special:      return 'Special';
      case AchievementCategory.general:      return 'General';
    }
  }
}
