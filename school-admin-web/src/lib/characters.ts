/**
 * Lumi character catalogue (web mirror of `lib/core/characters/lumi_character.dart`).
 *
 * The `characterId` stored on a student doc is also the PNG filename stem. PNGs
 * are vendored into `public/characters/` from the app's `assets/characters/`.
 * Validating against the known id set means corrupt / legacy ids fall back to
 * initials instead of rendering a broken image.
 */

const CHARACTER_IDS: ReadonlySet<string> = new Set([
  // Colored Lumi flames
  'blue_lumi',
  'light_blue_lumi',
  'green_lumi',
  'yellow_lumi',
  'orange_lumi',
  'pink_lumi',
  'purple_lumi',
  // Themed Lumis
  'lumi_chef',
  'lumi_cool_kid',
  'lumi_crown',
  'lumi_headphones',
  'lumi_ninja',
  'lumi_pirate',
  'lumi_space',
  'lumi_wizard',
  // Animal Lumis
  'lumi_bear',
  'lumi_cat',
  'lumi_frog',
  'lumi_penguin',
  'lumi_pig',
  'lumi_shark',
  'lumi_tiger',
  // Colored variants
  'blue_crown',
  'blue_pig',
  'blue_space',
  'blue_tiger',
  'green_bear',
  'green_dj',
  'orange_penguin',
  'orange_wizard',
  'pink_frog',
  'pink_pirate',
  'pink_shark',
  'purple_cool_kid',
  'yellow_cat',
  'yellow_chef',
  'yellow_ninja',
]);

/** Public path to the character PNG, or null if the id is unset/unrecognised. */
export function characterImageSrc(characterId?: string | null): string | null {
  if (!characterId) return null;
  return CHARACTER_IDS.has(characterId) ? `/characters/${characterId}.png` : null;
}
