'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth/auth-context';
import { useSchool } from '@/lib/hooks/use-school';
import { Icon } from '@/components/lumi/icon';

interface NavItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  adminOnly?: boolean;
}

const navItems: NavItem[] = [
  { label: 'Dashboard', href: '/dashboard', icon: <Icon name="home" size={18} /> },
  { label: 'Classes', href: '/classes', icon: <Icon name="school" size={18} /> },
  { label: 'Students', href: '/students', icon: <Icon name="person" size={18} /> },
  { label: 'Library', href: '/library', icon: <Icon name="library_books" size={18} /> },
  { label: 'Users', href: '/users', icon: <Icon name="group" size={18} />, adminOnly: true },
  { label: 'Parent Links', href: '/parent-links', icon: <Icon name="link" size={18} />, adminOnly: true },
  { label: 'Analytics', href: '/analytics', icon: <Icon name="bar_chart" size={18} />, adminOnly: true },
  { label: 'Settings', href: '/settings', icon: <Icon name="settings" size={18} />, adminOnly: true },
];

export function Sidebar() {
  const pathname = usePathname();
  const { user, logout } = useAuth();
  const { data: school } = useSchool();

  const visibleItems = navItems.filter(
    (item) => !item.adminOnly || user?.role === 'schoolAdmin'
  );

  return (
    <aside className="fixed left-0 top-0 bottom-0 w-[240px] bg-surface border-r border-divider flex flex-col z-40">
      {/* Logo */}
      <div className="px-5 py-5 border-b border-divider">
        <Link href="/dashboard" className="flex items-center gap-2.5">
          {school?.logoUrl ? (
            <img
              src={school.logoUrl}
              alt=""
              className="w-9 h-9 rounded-[var(--radius-md)] object-contain"
            />
          ) : (
            <span className="inline-flex items-center justify-center w-9 h-9 rounded-[var(--radius-md)] bg-brand-primary/10 text-brand-primary">
              <Icon name="library_books" size={20} />
            </span>
          )}
          <div>
            <span className="text-lg font-bold text-charcoal">{school?.displayName || school?.name || 'Lumi'}</span>
            <span className="text-[11px] font-semibold text-text-secondary block -mt-0.5">School Portal</span>
          </div>
        </Link>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 overflow-y-auto">
        <ul className="space-y-1">
          {visibleItems.map((item) => {
            const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className={`flex items-center gap-3 px-3 py-2.5 rounded-[var(--radius-md)] text-[14px] font-semibold transition-colors ${
                    isActive
                      ? 'bg-brand-primary/10 text-brand-primary'
                      : 'text-text-secondary hover:bg-background hover:text-charcoal'
                  }`}
                >
                  <span className="text-base leading-none">{item.icon}</span>
                  {item.label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      {/* User section */}
      <div className="px-3 py-4 border-t border-divider">
        <Link
          href="/profile"
          className="flex items-center gap-3 px-3 py-2 rounded-[var(--radius-md)] hover:bg-background transition-colors"
        >
          <div className="w-8 h-8 rounded-full bg-brand-primary/10 flex items-center justify-center text-xs font-bold text-brand-primary">
            {user?.fullName?.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2) || '??'}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-charcoal truncate">{user?.fullName || 'Loading...'}</p>
            <p className="text-[11px] text-text-secondary capitalize">{user?.role === 'schoolAdmin' ? 'Admin' : 'Teacher'}</p>
          </div>
        </Link>
        <button
          onClick={logout}
          className="w-full mt-2 px-3 py-2 rounded-[var(--radius-md)] text-[13px] font-semibold text-text-secondary hover:bg-background hover:text-charcoal transition-colors text-left"
        >
          Sign Out
        </button>
      </div>
    </aside>
  );
}
