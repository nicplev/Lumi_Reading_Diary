'use client';

import { usePathname } from 'next/navigation';
import {
  SECTIONS,
  sectionForPath,
  sectionVars,
  type LumiSectionKey,
  type LumiSectionTheme,
} from '@/lib/theme/sections';

/**
 * Declares a section theme for everything inside it. Sets the `--section-*`
 * CSS variables that drive the `section` colour utilities (bg-section,
 * text-section, ring-section, bg-section-tint, …) so design-system widgets
 * pick up the right accent without hard-coding a colour.
 *
 *   <SectionScope section="library"> … </SectionScope>
 *
 * Mirrors the Flutter LumiSectionScope.
 */
export function SectionScope({
  section,
  className,
  children,
}: {
  section: LumiSectionKey | LumiSectionTheme;
  className?: string;
  children: React.ReactNode;
}) {
  const theme = typeof section === 'string' ? SECTIONS[section] : section;
  return (
    <div className={className} style={sectionVars(theme)}>
      {children}
    </div>
  );
}

/**
 * Section scope that derives its theme from the current route. Wrap the
 * authenticated page area in this so every page is automatically themed by
 * the `sectionForPath` mapping — pages don't need to declare their own scope.
 */
export function RouteSectionScope({
  className,
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const theme = sectionForPath(pathname);
  return (
    <div className={className} style={sectionVars(theme)} data-section={theme.key}>
      {children}
    </div>
  );
}
