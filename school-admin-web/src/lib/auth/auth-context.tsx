'use client';

import { createContext, useContext, useEffect, useState, useCallback, useRef } from 'react';
import { onAuthStateChanged, signOut, User } from 'firebase/auth';
import { auth } from '@/lib/firebase/client';

export interface AuthUser {
  uid: string;
  email: string;
  schoolId: string;
  role: 'teacher' | 'schoolAdmin';
  fullName: string;
  characterId?: string;
}

interface AuthContextType {
  user: AuthUser | null;
  firebaseUser: User | null;
  loading: boolean;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
  setSessionData: (data: AuthUser) => void;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  firebaseUser: null,
  loading: true,
  logout: async () => {},
  refreshUser: async () => {},
  setSessionData: () => {},
});

export function AuthProvider({
  children,
  initialUser,
}: {
  children: React.ReactNode;
  /** Server-resolved session, seeded from the root layout so the user is known
   *  on first paint instead of waiting on the client Firebase + /me round-trip
   *  (which left the profile chip stuck on "Loading…"). */
  initialUser?: AuthUser | null;
}) {
  const [user, setUser] = useState<AuthUser | null>(initialUser ?? null);
  const [firebaseUser, setFirebaseUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(!initialUser);
  const sessionSetByLogin = useRef(false);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (fbUser) => {
      setFirebaseUser(fbUser);
      if (fbUser) {
        // Skip fetch if login page already injected session data
        if (sessionSetByLogin.current) {
          sessionSetByLogin.current = false;
          setLoading(false);
          return;
        }
        try {
          const res = await fetch('/api/auth/me');
          if (res.ok) {
            const data = await res.json();
            setUser(data);
          } else {
            // Session cookie is stale/invalid — attempt recovery with fresh Firebase token
            const idToken = await fbUser.getIdToken(true);
            const sessionRes = await fetch('/api/auth/session', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ idToken }),
            });
            if (sessionRes.ok) {
              const data = await sessionRes.json();
              setUser(data);
            } else {
              const failure = await sessionRes.json().catch(() => null);
              if (failure?.code === 'admin-totp-enrollment-required') {
                // The login page owns the enrollment proof and QR flow. Keep
                // the freshly password-authenticated Firebase user alive so
                // AuthContext's parallel recovery attempt cannot sign them out
                // from underneath that flow.
                setUser(null);
              } else {
                // Recovery failed — full logout
                await fetch('/api/auth/logout', { method: 'POST' });
                await signOut(auth);
                setUser(null);
              }
            }
          }
        } catch {
          setUser(null);
        }
      } else {
        setUser(null);
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const refreshUser = useCallback(async () => {
    try {
      const res = await fetch('/api/auth/me');
      if (res.ok) {
        const data = await res.json();
        setUser(data);
      }
    } catch {
      // Silently fail — user stays as-is
    }
  }, []);

  const logout = useCallback(async () => {
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
      await signOut(auth);
    } finally {
      setUser(null);
      // Hard-redirect so the cleared session cookie is re-evaluated by middleware
      // and all client state resets. Without this the page sits on the current
      // route until a manual refresh (the reported "sign out does nothing" bug).
      window.location.href = '/login';
    }
  }, []);

  const setSessionData = useCallback((data: AuthUser) => {
    sessionSetByLogin.current = true;
    setUser(data);
    setLoading(false);
  }, []);

  return (
    <AuthContext.Provider value={{ user, firebaseUser, loading, logout, refreshUser, setSessionData }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
