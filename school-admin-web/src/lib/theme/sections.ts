/**
 * Lumi section themes — colour as section identity, not semantic role.
 *
 * Every page belongs to one of four sections; each section owns one brand
 * colour that flows through headers, primary CTAs, active nav and key chrome.
 * Mirrors the Flutter LumiSectionTheme in docs/New_Lumi_Design_Guide.md, with
 * the portal's admin-only pages folded into the nearest section by function:
 *
 *   Dashboard · Analytics · Communication → Lumi Blue   (data + outreach)
 *   Classes   · Students                  → Lumi Red    (your class + kids)
 *   Library                               → Lumi Yellow
 *   Users     · Parent Links · Settings   → Lumi Green  (admin + config)
 */

export type LumiSectionKey = 'dashboard' | 'class' | 'library' | 'settings';

export interface LumiSectionTheme {
  key: LumiSectionKey;
  /** Accent hex — headers, primary CTAs, active nav. */
  accent: string;
  /** Soft fill for selected states + badges. */
  accentTint: string;
  /** Readable foreground on a filled accent surface. */
  onAccent: string;
  /** Human label for the section (used in section eyebrow labels). */
  label: string;
}

export const SECTIONS: Record<LumiSectionKey, LumiSectionTheme> = {
  dashboard: {
    key: 'dashboard',
    accent: '#56C8E6',
    accentTint: '#C8E8F1',
    onAccent: '#1A1A1A', // blue is light — ink reads better than white
    label: 'Insights',
  },
  class: {
    key: 'class',
    accent: '#EC4544',
    accentTint: '#F4B5B7',
    onAccent: '#FFFFFF',
    label: 'Class',
  },
  library: {
    key: 'library',
    accent: '#FFCB05',
    accentTint: '#FBE89F',
    onAccent: '#1A1A1A', // yellow is light — always ink
    label: 'Library',
  },
  settings: {
    key: 'settings',
    accent: '#51BA65',
    accentTint: '#B5DAB8',
    onAccent: '#FFFFFF',
    label: 'Settings',
  },
};

/** Maps a top-level route segment to its section. */
const ROUTE_SECTION: Record<string, LumiSectionKey> = {
  dashboard: 'dashboard',
  analytics: 'dashboard',
  communication: 'dashboard',
  classes: 'class',
  students: 'class',
  library: 'library',
  users: 'settings',
  'parent-links': 'settings',
  renewals: 'settings',
  settings: 'settings',
  profile: 'settings',
  dev: 'settings',
};

/** Resolve the section theme for a pathname (e.g. "/classes/abc" → class). */
export function sectionForPath(pathname: string): LumiSectionTheme {
  const segment = pathname.split('/').filter(Boolean)[0] ?? 'dashboard';
  const key = ROUTE_SECTION[segment] ?? 'dashboard';
  return SECTIONS[key];
}

/** Inline CSS custom properties that drive the `section` colour utilities. */
export function sectionVars(theme: LumiSectionTheme): React.CSSProperties {
  return {
    '--section-accent': theme.accent,
    '--section-accent-tint': theme.accentTint,
    '--section-on-accent': theme.onAccent,
  } as React.CSSProperties;
}
