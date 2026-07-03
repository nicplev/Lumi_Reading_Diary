'use client';

import { useEffect } from 'react';
import { Button } from '@/components/lumi/button';

/**
 * Route-level error boundary for the authenticated area. Without this, a thrown
 * error in a server component / render (e.g. a dashboard data fetch rejecting)
 * fell through to Next's default full-page crash. This renders a recoverable
 * card with a retry (Next's `reset()`).
 */
export default function AuthenticatedError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Surface for debugging; the message itself may be a server digest.
    console.error('Authenticated route error:', error);
  }, [error]);

  return (
    <div className="flex min-h-[60vh] items-center justify-center p-6">
      <div className="max-w-md rounded-2xl border border-error/30 bg-error/5 p-6 text-center">
        <h2 className="text-lg font-semibold text-ink">Something went wrong</h2>
        <p className="mt-2 text-sm text-muted">
          We couldn&apos;t load this page. This is usually temporary — please try again.
        </p>
        <div className="mt-5 flex justify-center">
          <Button onClick={() => reset()}>Try again</Button>
        </div>
      </div>
    </div>
  );
}
