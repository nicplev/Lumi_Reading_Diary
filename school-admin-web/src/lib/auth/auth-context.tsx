'use client';

import { createContext, useContext, useEffect, useState, useCallback, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { onAuthStateChanged, signOut, User } from 'firebase/auth';
import { auth } from '@/lib/firebase/client';

export interface AuthUser {
  uid: string;
  email: string;
  schoolId: string;
  role: 'teacher' | 'schoolAdmin';
  fullName: string;
  characterId?: string;
  /** UI hint only; demo mutation endpoints re-authorize server-side. */
  demoAllocationMutations?: true;
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

/** How long a tab must be hidden before returning to it triggers a session
 *  re-check. Short enough that a genuinely expired session is caught, long
 *  enough that flicking between tabs doesn't spam `/api/auth/me`. */
const REVALIDATE_AFTER_HIDDEN_MS = 60_000;

/** Reads the server session — the source of truth. Returns null on 401 (no
 *  valid cookie) and `undefined` when the check itself failed (offline, 5xx),
 *  which must NOT be treated as a logout. */
async function fetchServerSession(): Promise<AuthUser | null | undefined> {
  try {
    const res = await fetch('/api/auth/me', { cache: 'no-store' });
    if (res.ok) return (await res.json()) as AuthUser;
    if (res.status === 401) return null;
    return undefined;
  } catch {
    return undefined;
  }
}

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
  const router = useRouter();
  const [user, setUser] = useState<AuthUser | null>(initialUser ?? null);
  const [firebaseUser, setFirebaseUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(!initialUser);
  const sessionSetByLogin = useRef(false);
  /** Set while an intentional sign-out is in flight. `signOut()` fires the
   *  auth listener with a null user, which would otherwise be mistaken for an
   *  expired session and bounce the user to "Your session expired" — after
   *  they deliberately pressed Sign Out. */
  const loggingOut = useRef(false);

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
        // A null Firebase user does NOT mean signed out.
        //
        // The `__session` cookie is the source of truth: middleware gates on
        // it and every SSR render is built from it, and it lives for 5 days
        // (session.ts) while the client ID token lasts an hour and can vanish
        // sooner still — a failed refresh, or Safari evicting IndexedDB.
        //
        // Clearing `user` unconditionally here is what produced the reported
        // bug: a tab left open would fire this listener with null, blank the
        // server-seeded user, and leave a fully-rendered page with a profile
        // chip stuck on "Loading…". Ask the server before believing it.
        const onLoginPage = window.location.pathname.startsWith('/login');
        if (loggingOut.current || onLoginPage) {
          // Deliberate sign-out, or simply not signed in yet on the login
          // page. Neither needs a server round-trip, and neither is an
          // expired session.
          setUser(null);
        } else {
          const serverUser = await fetchServerSession();
          if (serverUser) {
            setUser(serverUser);
          } else if (serverUser === null) {
            // Genuinely signed out. Don't leave them on a dead page.
            setUser(null);
            window.location.href = '/login?reason=expired';
            return;
          }
          // serverUser === undefined: the check itself failed (offline/5xx).
          // Keep what we have rather than falsely signing the user out.
        }
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  // Re-check the session when a tab is returned to after sitting idle.
  //
  // Without this, a tab left open all night shows whatever it rendered
  // yesterday: the session may have expired, and the data on screen (reading
  // minutes, attention counts) is simply old. `router.refresh()` re-runs the
  // server components so the page catches up too, not just the auth state.
  useEffect(() => {
    let hiddenSince: number | null =
      typeof document !== 'undefined' && document.visibilityState === 'hidden'
        ? Date.now()
        : null;
    let checking = false;

    async function revalidate() {
      if (checking || loggingOut.current) return;
      checking = true;
      try {
        const serverUser = await fetchServerSession();
        if (serverUser) {
          setUser(serverUser);
          router.refresh();
        } else if (serverUser === null) {
          setUser(null);
          if (!window.location.pathname.startsWith('/login')) {
            window.location.href = '/login?reason=expired';
          }
        }
        // undefined → transient failure; leave the UI alone.
      } finally {
        checking = false;
      }
    }

    function onVisibilityChange() {
      if (document.visibilityState === 'hidden') {
        hiddenSince = Date.now();
        return;
      }
      if (hiddenSince === null) return;
      const awayMs = Date.now() - hiddenSince;
      hiddenSince = null;
      if (awayMs >= REVALIDATE_AFTER_HIDDEN_MS) void revalidate();
    }

    document.addEventListener('visibilitychange', onVisibilityChange);
    return () =>
      document.removeEventListener('visibilitychange', onVisibilityChange);
  }, [router]);

  const refreshUser = useCallback(async () => {
    const serverUser = await fetchServerSession();
    if (serverUser) setUser(serverUser);
    // A 401 or a transient failure leaves the user as-is: this is the
    // explicit "re-read my profile" path (e.g. after a settings save), not a
    // session check, so it must never sign anyone out as a side effect.
  }, []);

  const logout = useCallback(async () => {
    loggingOut.current = true;
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
