/// Lumi character catalogue.
///
/// Each [LumiCharacter] maps a stable [id] string (also used as the Firestore
/// field value and the SVG filename stem) to a display name and asset path.
///
/// To ship real illustrations: replace the SVG files in assets/characters/ —
/// no Dart changes needed. To add new characters: append to [LumiCharacters.all]
/// and add the corresponding SVG.
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
    LumiCharacter(
      id: 'character_fox',
      displayName: 'Fox',
      assetPath: 'assets/characters/character_fox.svg',
    ),
    LumiCharacter(
      id: 'character_bear',
      displayName: 'Bear',
      assetPath: 'assets/characters/character_bear.svg',
    ),
    LumiCharacter(
      id: 'character_owl',
      displayName: 'Owl',
      assetPath: 'assets/characters/character_owl.svg',
    ),
    LumiCharacter(
      id: 'character_rabbit',
      displayName: 'Rabbit',
      assetPath: 'assets/characters/character_rabbit.svg',
    ),
    LumiCharacter(
      id: 'character_cat',
      displayName: 'Cat',
      assetPath: 'assets/characters/character_cat.svg',
    ),
    LumiCharacter(
      id: 'character_dog',
      displayName: 'Dog',
      assetPath: 'assets/characters/character_dog.svg',
    ),
    LumiCharacter(
      id: 'character_penguin',
      displayName: 'Penguin',
      assetPath: 'assets/characters/character_penguin.svg',
    ),
    LumiCharacter(
      id: 'character_turtle',
      displayName: 'Turtle',
      assetPath: 'assets/characters/character_turtle.svg',
    ),
  ];

  /// Returns the character with [id], or null if not found.
  static LumiCharacter? findById(String? id) {
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}
