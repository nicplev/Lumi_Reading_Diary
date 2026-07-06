/// Lumi character catalogue.
///
/// Each [LumiCharacter] maps a stable [id] string (also the Firestore field
/// value and the PNG filename stem) to a display name and asset path.
///
/// To add characters: drop a PNG in assets/characters/ (slug-cased, e.g.
/// `lumi_bear.png`) and append an entry below. The folder is already declared
/// in pubspec.yaml, so no other wiring is needed.
class LumiCharacter {
  final String id;
  final String displayName;
  final String assetPath;

  const LumiCharacter({
    required this.id,
    required this.displayName,
    required this.assetPath,
  });
}

class LumiCharacters {
  LumiCharacters._();

  static const List<LumiCharacter> all = [
    // Colored Lumi flames
    LumiCharacter(id: 'blue_lumi', displayName: 'Blue Lumi', assetPath: 'assets/characters/blue_lumi.png'),
    LumiCharacter(id: 'light_blue_lumi', displayName: 'Light Blue Lumi', assetPath: 'assets/characters/light_blue_lumi.png'),
    LumiCharacter(id: 'green_lumi', displayName: 'Green Lumi', assetPath: 'assets/characters/green_lumi.png'),
    LumiCharacter(id: 'yellow_lumi', displayName: 'Yellow Lumi', assetPath: 'assets/characters/yellow_lumi.png'),
    LumiCharacter(id: 'orange_lumi', displayName: 'Orange Lumi', assetPath: 'assets/characters/orange_lumi.png'),
    LumiCharacter(id: 'pink_lumi', displayName: 'Pink Lumi', assetPath: 'assets/characters/pink_lumi.png'),
    LumiCharacter(id: 'purple_lumi', displayName: 'Purple Lumi', assetPath: 'assets/characters/purple_lumi.png'),

    // Themed Lumis
    LumiCharacter(id: 'lumi_chef', displayName: 'Lumi Chef', assetPath: 'assets/characters/lumi_chef.png'),
    LumiCharacter(id: 'lumi_cool_kid', displayName: 'Lumi Cool Kid', assetPath: 'assets/characters/lumi_cool_kid.png'),
    LumiCharacter(id: 'lumi_crown', displayName: 'Lumi Crown', assetPath: 'assets/characters/lumi_crown.png'),
    LumiCharacter(id: 'lumi_headphones', displayName: 'Lumi Headphones', assetPath: 'assets/characters/lumi_headphones.png'),
    LumiCharacter(id: 'lumi_ninja', displayName: 'Lumi Ninja', assetPath: 'assets/characters/lumi_ninja.png'),
    LumiCharacter(id: 'lumi_pirate', displayName: 'Lumi Pirate', assetPath: 'assets/characters/lumi_pirate.png'),
    LumiCharacter(id: 'lumi_space', displayName: 'Lumi Space', assetPath: 'assets/characters/lumi_space.png'),
    LumiCharacter(id: 'lumi_wizard', displayName: 'Lumi Wizard', assetPath: 'assets/characters/lumi_wizard.png'),

    // Animal Lumis
    LumiCharacter(id: 'lumi_bear', displayName: 'Lumi Bear', assetPath: 'assets/characters/lumi_bear.png'),
    LumiCharacter(id: 'lumi_cat', displayName: 'Lumi Cat', assetPath: 'assets/characters/lumi_cat.png'),
    LumiCharacter(id: 'lumi_frog', displayName: 'Lumi Frog', assetPath: 'assets/characters/lumi_frog.png'),
    LumiCharacter(id: 'lumi_penguin', displayName: 'Lumi Penguin', assetPath: 'assets/characters/lumi_penguin.png'),
    LumiCharacter(id: 'lumi_pig', displayName: 'Lumi Pig', assetPath: 'assets/characters/lumi_pig.png'),
    LumiCharacter(id: 'lumi_shark', displayName: 'Lumi Shark', assetPath: 'assets/characters/lumi_shark.png'),
    LumiCharacter(id: 'lumi_tiger', displayName: 'Lumi Tiger', assetPath: 'assets/characters/lumi_tiger.png'),

    // Colored variants
    LumiCharacter(id: 'blue_crown', displayName: 'Blue Crown', assetPath: 'assets/characters/blue_crown.png'),
    LumiCharacter(id: 'blue_pig', displayName: 'Blue Pig', assetPath: 'assets/characters/blue_pig.png'),
    LumiCharacter(id: 'blue_space', displayName: 'Blue Space', assetPath: 'assets/characters/blue_space.png'),
    LumiCharacter(id: 'blue_tiger', displayName: 'Blue Tiger', assetPath: 'assets/characters/blue_tiger.png'),
    LumiCharacter(id: 'green_bear', displayName: 'Green Bear', assetPath: 'assets/characters/green_bear.png'),
    LumiCharacter(id: 'green_dj', displayName: 'Green DJ', assetPath: 'assets/characters/green_dj.png'),
    LumiCharacter(id: 'orange_penguin', displayName: 'Orange Penguin', assetPath: 'assets/characters/orange_penguin.png'),
    LumiCharacter(id: 'orange_wizard', displayName: 'Orange Wizard', assetPath: 'assets/characters/orange_wizard.png'),
    LumiCharacter(id: 'pink_frog', displayName: 'Pink Frog', assetPath: 'assets/characters/pink_frog.png'),
    LumiCharacter(id: 'pink_pirate', displayName: 'Pink Pirate', assetPath: 'assets/characters/pink_pirate.png'),
    LumiCharacter(id: 'pink_shark', displayName: 'Pink Shark', assetPath: 'assets/characters/pink_shark.png'),
    LumiCharacter(id: 'purple_cool_kid', displayName: 'Purple Cool Kid', assetPath: 'assets/characters/purple_cool_kid.png'),
    LumiCharacter(id: 'yellow_cat', displayName: 'Yellow Cat', assetPath: 'assets/characters/yellow_cat.png'),
    LumiCharacter(id: 'yellow_chef', displayName: 'Yellow Chef', assetPath: 'assets/characters/yellow_chef.png'),
    LumiCharacter(id: 'yellow_ninja', displayName: 'Yellow Ninja', assetPath: 'assets/characters/yellow_ninja.png'),
  ];

  /// Award characters — assigned by the reading-awards feature, NOT chosen by
  /// students. Kept out of [all] so they never appear in the character picker,
  /// but resolved by [findById] so they render wherever a profile character is
  /// shown. Assets live in `assets/special lumi/` (declared in pubspec.yaml).
  static const String goldLumiId = 'gold_lumi';
  static const String specialLumiId = 'special_lumi';

  static const List<LumiCharacter> awards = [
    LumiCharacter(id: goldLumiId, displayName: 'Gold Lumi', assetPath: 'assets/special lumi/Gold Lumi.png'),
    LumiCharacter(id: specialLumiId, displayName: 'Special Lumi', assetPath: 'assets/special lumi/Special Lumi.png'),
  ];

  /// Returns the character with [id] (searching selectable [all] then [awards]),
  /// or null if not found.
  static LumiCharacter? findById(String? id) {
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    for (final c in awards) {
      if (c.id == id) return c;
    }
    return null;
  }
}
