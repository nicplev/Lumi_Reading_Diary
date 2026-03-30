'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth/auth-context';
import { Icon } from '@/components/lumi/icon';

const mobileItems = [
  { label: 'Home', href: '/dashboard', icon: <Icon name="home" size={22} /> },
  { label: 'Classes', href: '/classes', icon: <Icon name="school" size={22} /> },
  { label: 'Students', href: '/students', icon: <Icon name="person" size={22} /> },
  { label: 'Library', href: '/library', icon: <Icon name="library_books" size={22} /> },
  { label: 'More', href: '/profile', icon: <Icon name="menu" size={22} /> },
];

export function MobileNav() {
  const pathname = usePathname();
  const { user } = useAuth();

  if (!user) return null;

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-surface border-t border-divider z-40 lg:hidden">
      <ul className="flex items-center justify-around py-2">
        {mobileItems.map((item) => {
          const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                className={`flex flex-col items-center gap-0.5 px-3 py-1 ${
                  isActive ? 'text-brand-primary' : 'text-text-secondary'
                }`}
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
