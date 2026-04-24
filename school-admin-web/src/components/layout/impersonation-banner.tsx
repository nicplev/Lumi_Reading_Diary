'use client';

import { useEffect, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { functions } from '@/lib/firebase/client';

interface Props {
  sessionId: string;
  schoolName: string;
  role: string;
  expiresAt: number;
}

/**
 * Red persistent banner with live countdown and Exit button. Rendered by the
 * authenticated layout whenever `session.impersonation` is set.
 */
export function ImpersonationBanner({ sessionId, schoolName, role, expiresAt }: Props) {
  // Defer the `Date.now()` read until after mount so SSR and the first
  // client render agree. Otherwise the mm:ss computed on the server (at
  // render time T1) won't match what the client computes during hydration
  // (at T2 ≠ T1), and React throws a hydration mismatch.
  const [now, setNow] = useState<number | null>(null);
  const [exiting, setExiting] = useState(false);

  useEffect(() => {
    setNow(Date.now());
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const mmss = (() => {
    if (now == null) return '--:--';
    const remainingMs = Math.max(0, expiresAt - now);
    const mm = Math.floor(remainingMs / 60_000)
      .toString()
      .padStart(2, '0');
    const ss = Math.floor((remainingMs % 60_000) / 1000)
      .toString()
      .padStart(2, '0');
    return `${mm}:${ss}`;
  })();

  const handleExit = async () => {
    if (exiting) return;
    setExiting(true);
    // Best-effort: record the end-of-session audit event. Failure here must
    // NOT stop the server-side teardown — the scheduled expirer will catch
    // the session within 5 minutes regardless.
    try {
      const endCallable = httpsCallable<{ sessionId: string }, { status: string }>(
        functions,
        'endImpersonationSession',
      );
      await endCallable({ sessionId });
    } catch {
      // Swallow — next step still runs.
    }
    try {
      await fetch('/api/dev/impersonate/end', { method: 'POST' });
    } catch {
      // Swallow — server-side cookie drop is best-effort too.
    }
    window.location.href = '/dashboard';
  };

  return (
    <div className="sticky top-0 z-50 bg-[#B91C1C] text-white">
      <div className="flex items-center gap-3 px-4 py-2 text-sm">
        <span className="font-semibold tracking-wide">IMPERSONATING</span>
        <span className="truncate" suppressHydrationWarning>
          {schoolName} · {role.toUpperCase()} · {mmss} · READ-ONLY
        </span>
        <div className="ml-auto flex items-center gap-2">
          <button
            type="button"
            onClick={handleExit}
            disabled={exiting}
            className="rounded px-3 py-1 text-xs font-semibold underline hover:bg-white/10 disabled:opacity-60"
          >
            {exiting ? 'Exiting…' : 'Exit'}
          </button>
        </div>
      </div>
    </div>
  );
}
