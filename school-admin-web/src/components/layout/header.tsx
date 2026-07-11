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
  users: 'Staff',
  'parent-links': 'Parents/Guardians',
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
    <header className="sticky top-0 z-30 flex h-14 items-center border-b border-rule bg-paper px-4 sm:px-6">
      {/* Section dot — a quiet cue for which colour world you're in */}
      <span
        className="w-2 h-2 rounded-full mr-3 shrink-0"
        style={{ backgroundColor: accent }}
        aria-hidden
      />
      <nav aria-label="Breadcrumb" className="flex min-w-0 items-center gap-1.5 overflow-hidden text-sm">
        {segments.map((segment, index) => {
          const href = '/' + segments.slice(0, index + 1).join('/');
          const isLast = index === segments.length - 1;
          const label = overrides[segment] || breadcrumbLabels[segment] || segment;

          return (
            <span key={href} className={`flex min-w-0 items-center gap-1.5 ${!isLast ? 'hidden sm:flex' : ''}`}>
              {index > 0 && <span className="shrink-0 text-muted/40">/</span>}
              {isLast ? (
                <span className="truncate font-semibold text-ink">{label}</span>
              ) : (
                <Link href={href} className="truncate text-muted transition-colors hover:text-ink">
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
