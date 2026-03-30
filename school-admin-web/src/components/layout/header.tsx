'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';

const breadcrumbLabels: Record<string, string> = {
  dashboard: 'Dashboard',
  classes: 'Classes',
  students: 'Students',
  library: 'Library',
  users: 'Users',
  'parent-links': 'Parent Links',
  analytics: 'Analytics',
  settings: 'Settings',
  profile: 'Profile',
  allocations: 'Allocations',
  new: 'New',
  groups: 'Groups',
  report: 'Report',
};

export function Header() {
  const pathname = usePathname();
  const segments = pathname.split('/').filter(Boolean);

  return (
    <header className="h-14 border-b border-divider bg-surface/80 backdrop-blur-sm flex items-center px-6 sticky top-0 z-30">
      <nav className="flex items-center gap-1.5 text-sm">
        {segments.map((segment, index) => {
          const href = '/' + segments.slice(0, index + 1).join('/');
          const isLast = index === segments.length - 1;
          const label = breadcrumbLabels[segment] || segment;

          return (
            <span key={href} className="flex items-center gap-1.5">
              {index > 0 && <span className="text-text-secondary/40">/</span>}
              {isLast ? (
                <span className="font-semibold text-charcoal">{label}</span>
              ) : (
                <Link href={href} className="text-text-secondary hover:text-charcoal transition-colors">
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
