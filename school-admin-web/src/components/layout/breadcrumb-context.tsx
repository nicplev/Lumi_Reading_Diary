'use client';

import { createContext, useContext, useState, useCallback } from 'react';

interface BreadcrumbContextType {
  overrides: Record<string, string>;
  setOverride: (key: string, label: string) => void;
}

const BreadcrumbContext = createContext<BreadcrumbContextType>({
  overrides: {},
  setOverride: () => {},
});

export function BreadcrumbProvider({ children }: { children: React.ReactNode }) {
  const [overrides, setOverrides] = useState<Record<string, string>>({});

  const setOverride = useCallback((key: string, label: string) => {
    setOverrides((prev) => ({ ...prev, [key]: label }));
  }, []);

  return (
    <BreadcrumbContext.Provider value={{ overrides, setOverride }}>
      {children}
    </BreadcrumbContext.Provider>
  );
}

export const useBreadcrumbs = () => useContext(BreadcrumbContext);
