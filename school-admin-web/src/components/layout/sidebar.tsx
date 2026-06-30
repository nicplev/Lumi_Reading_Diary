'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth/auth-context';
import { useSchool } from '@/lib/hooks/use-school';
import { Icon } from '@/components/lumi/icon';
import { Avatar } from '@/components/lumi/avatar';
import { sectionForPath } from '@/lib/theme/sections';

interface NavItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  adminOnly?: boolean;
}

const navItems: NavItem[] = [
  { label: 'Dashboard', href: '/dashboard', icon: <Icon name="home" size={18} /> },
  { label: 'Classes', href: '/classes', icon: <Icon name="school" size={18} /> },
  { label: 'Students', href: '/students', icon: <Icon name="person" size={18} />, adminOnly: true },
  { label: 'Library', href: '/library', icon: <Icon name="library_books" size={18} /> },
  { label: 'Communication', href: '/communication', icon: <Icon name="campaign" size={18} /> },
  { label: 'Staff', href: '/users', icon: <Icon name="group" size={18} />, adminOnly: true },
  { label: 'Parents/Guardians', href: '/parent-links', icon: <Icon name="link" size={18} />, adminOnly: true },
  { label: 'Analytics', href: '/analytics', icon: <Icon name="bar_chart" size={18} />, adminOnly: true },
  { label: 'Settings', href: '/settings', icon: <Icon name="settings" size={18} />, adminOnly: true },
];

interface SidebarProps {
  /** True if the signed-in user holds developer access. When set, the footer
   *  shows an extra "Impersonate School" entry. Computed server-side from the
   *  session email + `devAccessEmails` doc and passed down. */
  hasDevAccess?: boolean;
}

export function Sidebar({ hasDevAccess = false }: SidebarProps) {
  const pathname = usePathname();
  const { user, logout } = useAuth();
  const { data: school } = useSchool();

  const isAdmin = user?.role === 'schoolAdmin';
  const visibleItems = navItems
    .filter((item) => !item.adminOnly || isAdmin)
    // Teachers typically have a single class, so the section reads "Class"
    // (admins manage many → "Classes").
    .map((item) =>
      item.href === '/classes' && !isAdmin ? { ...item, label: 'Class' } : item
    );

  return (
    <aside className="fixed left-0 top-0 bottom-0 w-[240px] bg-paper border-r border-rule flex flex-col z-40">
      {/* Wordmark */}
      <div className="px-5 py-5">
        <Link href="/dashboard" className="flex items-center gap-2.5">
          {school?.logoUrl ? (
            <img
              src={school.logoUrl}
              alt=""
              className="w-9 h-9 rounded-[var(--radius-md)] object-contain"
            />
          ) : (
            <span className="inline-flex items-center justify-center w-9 h-9 rounded-[var(--radius-md)] bg-lumi-red/10 text-lumi-red">
              <Icon name="local_fire_department" size={22} />
            </span>
          )}
          <div className="min-w-0">
            <span className="font-display text-lg font-extrabold text-ink tracking-tight block truncate">
              {school?.displayName || school?.name || 'Lumi'}
            </span>
            <span className="text-[11px] font-semibold text-muted block -mt-0.5">School Portal</span>
          </div>
        </Link>
      </div>

      {/* Navigation — each item lights up in its own section colour when active */}
      <nav className="flex-1 px-3 py-2 overflow-y-auto">
        <ul className="space-y-1">
          {visibleItems.map((item) => {
            const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
            const accent = sectionForPath(item.href).accent;
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  style={isActive ? { backgroundColor: `${accent}1A`, color: accent } : undefined}
                  className={`relative flex items-center gap-3 px-3 py-2.5 rounded-[var(--radius-md)] text-[14px] font-semibold transition-colors ${
                    isActive ? '' : 'text-muted hover:bg-cream hover:text-ink'
                  }`}
                >
                  {isActive && (
                    <span
                      className="absolute left-0 top-1/2 -translate-y-1/2 h-5 w-[3px] rounded-full"
                      style={{ backgroundColor: accent }}
                    />
                  )}
                  <span className="text-base leading-none">{item.icon}</span>
                  {item.label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      {/* Dev tools (only when the signed-in user is on the dev allowlist) */}
      {hasDevAccess && (
        <div className="px-3 pt-2 border-t border-rule">
          <Link
            href="/dev/impersonate"
            className="flex items-center gap-3 px-3 py-2 rounded-[var(--radius-md)] text-[13px] font-semibold text-lumi-red-dark hover:bg-lumi-red/5 transition-colors"
          >
            <Icon name="shield" size={16} />
            Impersonate School
          </Link>
        </div>
      )}

      {/* User section */}
      <div className="px-3 py-4 border-t border-rule">
        <Link
          href="/profile"
          className="flex items-center gap-3 px-3 py-2 rounded-[var(--radius-md)] hover:bg-cream transition-colors"
        >
          <Avatar
            name={user?.fullName || user?.email || 'User'}
            characterId={user?.characterId}
            size="sm"
          />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-ink truncate">{user?.fullName || user?.email || 'Loading...'}</p>
            <p className="text-[11px] text-muted capitalize">{user?.role === 'schoolAdmin' ? 'Admin' : 'Teacher'}</p>
          </div>
        </Link>
        <button
          onClick={logout}
          className="w-full mt-2 px-3 py-2 rounded-[var(--radius-md)] text-[13px] font-semibold text-muted hover:bg-cream hover:text-ink transition-colors text-left"
        >
          Sign Out
        </button>
      </div>
    </aside>
  );
}
