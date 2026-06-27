'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth/auth-context';
import { Icon } from '@/components/lumi/icon';
import { sectionForPath } from '@/lib/theme/sections';

const mobileItems: { label: string; href: string; icon: React.ReactNode; adminOnly?: boolean }[] = [
  { label: 'Home', href: '/dashboard', icon: <Icon name="home" size={22} /> },
  { label: 'Classes', href: '/classes', icon: <Icon name="school" size={22} /> },
  { label: 'Students', href: '/students', icon: <Icon name="person" size={22} />, adminOnly: true },
  { label: 'Library', href: '/library', icon: <Icon name="library_books" size={22} /> },
  { label: 'More', href: '/profile', icon: <Icon name="menu" size={22} /> },
];

export function MobileNav() {
  const pathname = usePathname();
  const { user } = useAuth();

  if (!user) return null;

  const isAdmin = user.role === 'schoolAdmin';
  const items = mobileItems
    .filter((item) => !item.adminOnly || isAdmin)
    // Match the sidebar: teachers see a singular "Class".
    .map((item) => (item.href === '/classes' && !isAdmin ? { ...item, label: 'Class' } : item));

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-paper border-t border-rule z-40 lg:hidden">
      <ul className="flex items-center justify-around py-2">
        {items.map((item) => {
          const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
          const accent = sectionForPath(item.href).accent;
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                style={isActive ? { color: accent } : undefined}
                className={`flex flex-col items-center gap-0.5 px-3 py-1 ${isActive ? '' : 'text-muted'}`}
              >
                <span className="leading-none">{item.icon}</span>
                <span className="text-[10px] font-semibold">{item.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
