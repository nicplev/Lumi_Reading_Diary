'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { useBreadcrumbs } from './breadcrumb-context';
import { sectionForPath } from '@/lib/theme/sections';

const breadcrumbLabels: Record<string, string> = {
  dashboard: 'Dashboard',
  classes: 'Classes',
  students: 'Students',
  library: 'Library',
  communication: 'Communication',
  users: 'Users',
  'parent-links': 'Parent Links',
  analytics: 'Analytics',
  settings: 'Settings',
  profile: 'Profile',
  renewals: 'Renewals',
  allocations: 'Allocations',
  new: 'New',
  groups: 'Groups',
  report: 'Report',
};

export function Header() {
  const pathname = usePathname();
  const { overrides } = useBreadcrumbs();
  const segments = pathname.split('/').filter(Boolean);
  const accent = sectionForPath(pathname).accent;

  return (
    <header className="h-14 border-b border-rule bg-paper flex items-center px-6 sticky top-0 z-30">
      {/* Section dot — a quiet cue for which colour world you're in */}
      <span
        className="w-2 h-2 rounded-full mr-3 shrink-0"
        style={{ backgroundColor: accent }}
        aria-hidden
      />
      <nav className="flex items-center gap-1.5 text-sm">
        {segments.map((segment, index) => {
          const href = '/' + segments.slice(0, index + 1).join('/');
          const isLast = index === segments.length - 1;
          const label = overrides[segment] || breadcrumbLabels[segment] || segment;

          return (
            <span key={href} className="flex items-center gap-1.5">
              {index > 0 && <span className="text-muted/40">/</span>}
              {isLast ? (
                <span className="font-semibold text-ink">{label}</span>
              ) : (
                <Link href={href} className="text-muted hover:text-ink transition-colors">
                  {label}
                </Link>
              )}
            </span>
          );
        })}
      </nav>
    </header>
  );
}
