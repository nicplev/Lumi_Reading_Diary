'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth/auth-context';
import { Icon } from '@/components/lumi/icon';
import { sectionForPath } from '@/lib/theme/sections';

interface NavigationItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  adminOnly?: boolean;
}

const primaryItems: NavigationItem[] = [
  { label: 'Home', href: '/dashboard', icon: <Icon name="home" size={22} /> },
  { label: 'Classes', href: '/classes', icon: <Icon name="school" size={22} /> },
  { label: 'Students', href: '/students', icon: <Icon name="person" size={22} />, adminOnly: true },
  { label: 'Library', href: '/library', icon: <Icon name="library_books" size={22} /> },
];

const moreItems: NavigationItem[] = [
  { label: 'Communication', href: '/communication', icon: <Icon name="forum" size={22} /> },
  { label: 'Staff', href: '/users', icon: <Icon name="groups" size={22} />, adminOnly: true },
  { label: 'Parents', href: '/parent-links', icon: <Icon name="family_restroom" size={22} />, adminOnly: true },
  { label: 'Analytics', href: '/analytics', icon: <Icon name="bar_chart" size={22} />, adminOnly: true },
  { label: 'Settings', href: '/settings', icon: <Icon name="settings" size={22} />, adminOnly: true },
  { label: 'Profile', href: '/profile', icon: <Icon name="account_circle" size={22} /> },
];

export function MobileNav() {
  const pathname = usePathname();
  const { user } = useAuth();
  const [isMoreOpen, setIsMoreOpen] = useState(false);

  useEffect(() => {
    if (!isMoreOpen || !user) return;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setIsMoreOpen(false);
    };

    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', onKeyDown);
    return () => {
      document.body.style.overflow = '';
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [isMoreOpen, user]);

  if (!user) return null;

  const isAdmin = user.role === 'schoolAdmin';
  const visibleItems = (items: NavigationItem[]) => items
    .filter((item) => !item.adminOnly || isAdmin)
    // Match the sidebar: teachers see a singular "Class".
    .map((item) => (item.href === '/classes' && !isAdmin ? { ...item, label: 'Class' } : item));
  const items = visibleItems(primaryItems);
  const menuItems = visibleItems(moreItems);
  const isMoreActive = menuItems.some((item) => pathname === item.href || pathname.startsWith(item.href + '/'));
  const moreAccent = sectionForPath(pathname).accent;

  return (
    <>
      <nav className="fixed bottom-0 left-0 right-0 z-40 border-t border-rule bg-paper lg:hidden">
        <ul className="mx-auto flex max-w-lg items-center justify-around px-1 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2">
        {items.map((item) => {
          const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
          const accent = sectionForPath(item.href).accent;
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                style={isActive ? { color: accent } : undefined}
                className={`flex min-w-12 flex-col items-center gap-0.5 px-2 py-1 ${isActive ? '' : 'text-muted'}`}
              >
                <span className="leading-none">{item.icon}</span>
                <span className="text-[10px] font-semibold">{item.label}</span>
              </Link>
            </li>
          );
        })}
        <li>
          <button
            type="button"
            onClick={() => setIsMoreOpen(true)}
            aria-expanded={isMoreOpen}
            aria-controls="mobile-navigation-menu"
            style={isMoreActive ? { color: moreAccent } : undefined}
            className={`flex min-w-12 flex-col items-center gap-0.5 px-2 py-1 ${isMoreActive ? '' : 'text-muted'}`}
          >
            <span className="leading-none"><Icon name="menu" size={22} /></span>
            <span className="text-[10px] font-semibold">More</span>
          </button>
        </li>
        </ul>
      </nav>

      {isMoreOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button
            type="button"
            aria-label="Close navigation menu"
            className="absolute inset-0 bg-ink/35"
            onClick={() => setIsMoreOpen(false)}
          />
          <section
            id="mobile-navigation-menu"
            role="dialog"
            aria-modal="true"
            aria-label="More navigation options"
            className="absolute inset-x-0 bottom-0 rounded-t-[var(--radius-xl)] bg-paper px-4 pb-[calc(1rem+env(safe-area-inset-bottom))] pt-4 shadow-card-hover"
          >
            <div className="mb-4 flex items-center justify-between">
              <div>
                <p className="font-display text-lg font-extrabold text-ink">More</p>
                <p className="text-xs text-muted">All school portal areas</p>
              </div>
              <button
                type="button"
                onClick={() => setIsMoreOpen(false)}
                aria-label="Close navigation menu"
                className="rounded-full p-2 text-muted transition-colors hover:bg-cream hover:text-ink"
              >
                <Icon name="close" size={21} />
              </button>
            </div>
            <div className="grid grid-cols-2 gap-2">
              {menuItems.map((item) => {
                const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
                const accent = sectionForPath(item.href).accent;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    onClick={() => setIsMoreOpen(false)}
                    style={isActive ? { borderColor: accent, color: accent } : undefined}
                    className={`flex items-center gap-3 rounded-[var(--radius-md)] border px-3 py-3 text-sm font-semibold transition-colors ${
                      isActive ? 'bg-cream' : 'border-rule text-ink hover:bg-cream'
                    }`}
                  >
                    {item.icon}
                    <span>{item.label}</span>
                  </Link>
                );
              })}
            </div>
          </section>
        </div>
      )}
    </>
  );
}
