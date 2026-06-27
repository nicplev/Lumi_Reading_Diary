import 'lumi_character.dart';

/// Staff (admin + teacher) profile-character catalogue — the staff counterpart
/// of [LumiCharacters]. Admins choose an **Admin Lumi (LA)** variant; teachers
/// choose a **Male Teacher (MT)** or **Female Teacher (FT)** variant (shown
/// together in one grid). Each [LumiCharacter.id] is the PNG filename stem under
/// `assets/staff_characters/`, prefixed by category (`la_` / `mt_` / `ft_`).
///
/// To add a colour: drop `<cat>_<colour>.png` in assets/staff_characters/ and
/// append an entry below.
class StaffLumiCharacters {
  StaffLumiCharacters._();

  /// Admin Lumi variants (admins pick from these).
  static const List<LumiCharacter> admin = [
    LumiCharacter(id: 'la_default', displayName: 'Admin Lumi', assetPath: 'assets/staff_characters/la_default.png'),
    LumiCharacter(id: 'la_blue', displayName: 'Blue', assetPath: 'assets/staff_characters/la_blue.png'),
    LumiCharacter(id: 'la_green', displayName: 'Green', assetPath: 'assets/staff_characters/la_green.png'),
    LumiCharacter(id: 'la_lblue', displayName: 'Light Blue', assetPath: 'assets/staff_characters/la_lblue.png'),
    LumiCharacter(id: 'la_orange', displayName: 'Orange', assetPath: 'assets/staff_characters/la_orange.png'),
    LumiCharacter(id: 'la_pink', displayName: 'Pink', assetPath: 'assets/staff_characters/la_pink.png'),
    LumiCharacter(id: 'la_purple', displayName: 'Purple', assetPath: 'assets/staff_characters/la_purple.png'),
    LumiCharacter(id: 'la_yellow', displayName: 'Yellow', assetPath: 'assets/staff_characters/la_yellow.png'),
  ];

  /// Teacher variants — male + female, combined into one grid (teachers pick any).
  static const List<LumiCharacter> teacher = [
    // Male Teacher (MT)
    LumiCharacter(id: 'mt_default', displayName: 'Male Teacher', assetPath: 'assets/staff_characters/mt_default.png'),
    LumiCharacter(id: 'mt_blue', displayName: 'Blue', assetPath: 'assets/staff_characters/mt_blue.png'),
    LumiCharacter(id: 'mt_green', displayName: 'Green', assetPath: 'assets/staff_characters/mt_green.png'),
    LumiCharacter(id: 'mt_lblue', displayName: 'Light Blue', assetPath: 'assets/staff_characters/mt_lblue.png'),
    LumiCharacter(id: 'mt_orange', displayName: 'Orange', assetPath: 'assets/staff_characters/mt_orange.png'),
    LumiCharacter(id: 'mt_pink', displayName: 'Pink', assetPath: 'assets/staff_characters/mt_pink.png'),
    LumiCharacter(id: 'mt_purple', displayName: 'Purple', assetPath: 'assets/staff_characters/mt_purple.png'),
    LumiCharacter(id: 'mt_yellow', displayName: 'Yellow', assetPath: 'assets/staff_characters/mt_yellow.png'),
    // Female Teacher (FT)
    LumiCharacter(id: 'ft_default', displayName: 'Female Teacher', assetPath: 'assets/staff_characters/ft_default.png'),
    LumiCharacter(id: 'ft_blue', displayName: 'Blue', assetPath: 'assets/staff_characters/ft_blue.png'),
    LumiCharacter(id: 'ft_green', displayName: 'Green', assetPath: 'assets/staff_characters/ft_green.png'),
    LumiCharacter(id: 'ft_lblue', displayName: 'Light Blue', assetPath: 'assets/staff_characters/ft_lblue.png'),
    LumiCharacter(id: 'ft_orange', displayName: 'Orange', assetPath: 'assets/staff_characters/ft_orange.png'),
    LumiCharacter(id: 'ft_pink', displayName: 'Pink', assetPath: 'assets/staff_characters/ft_pink.png'),
    LumiCharacter(id: 'ft_purple', displayName: 'Purple', assetPath: 'assets/staff_characters/ft_purple.png'),
    LumiCharacter(id: 'ft_yellow', displayName: 'Yellow', assetPath: 'assets/staff_characters/ft_yellow.png'),
  ];

  /// Every staff character (admin + teacher).
  static const List<LumiCharacter> all = [...admin, ...teacher];

  /// Returns the staff character with [id], or null if not found.
  static LumiCharacter? findById(String? id) {
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}
