'use client';

import { useEffect } from 'react';
import { useSchool } from '@/lib/hooks/use-school';

function darkenHex(hex: string, amount: number = 0.1): string {
  const clean = hex.replace('#', '');
  const r = Math.max(0, Math.round(parseInt(clean.slice(0, 2), 16) * (1 - amount)));
  const g = Math.max(0, Math.round(parseInt(clean.slice(2, 4), 16) * (1 - amount)));
  const b = Math.max(0, Math.round(parseInt(clean.slice(4, 6), 16) * (1 - amount)));
  return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
}

interface SchoolThemeProviderProps {
  children: React.ReactNode;
  initialColors?: { primary: string; secondary: string };
}

export function SchoolThemeProvider({ children, initialColors }: SchoolThemeProviderProps) {
  const { data: school } = useSchool();

  useEffect(() => {
    const root = document.documentElement;
    if (school?.primaryColor) {
      root.style.setProperty('--color-brand-primary', school.primaryColor);
      root.style.setProperty('--color-brand-primary-dark', darkenHex(school.primaryColor, 0.12));
    }
    if (school?.secondaryColor) {
      root.style.setProperty('--color-brand-secondary', school.secondaryColor);
    }

    return () => {
      root.style.removeProperty('--color-brand-primary');
      root.style.removeProperty('--color-brand-primary-dark');
      root.style.removeProperty('--color-brand-secondary');
    };
  }, [school?.primaryColor, school?.secondaryColor]);

  return (
    <>
      {initialColors && (
        <style>{`:root { --color-brand-primary: ${initialColors.primary}; --color-brand-primary-dark: ${darkenHex(initialColors.primary, 0.12)}; --color-brand-secondary: ${initialColors.secondary}; }`}</style>
      )}
      {children}
    </>
  );
}
