'use client';

import { Button } from '@/components/lumi/button';

/**
 * Inline error card for a failed data fetch (react-query `isError`). Replaces
 * the anti-pattern of collapsing an error into a hung spinner or a
 * confident-but-false empty state ("no books" / "0% participation"). Pass the
 * query's `refetch` as `onRetry`.
 */
export function QueryError({
  message = "We couldn't load this data.",
  onRetry,
  className = '',
}: {
  message?: string;
  onRetry?: () => void;
  className?: string;
}) {
  return (
    <div
      className={`rounded-lg border border-error/30 bg-error/5 p-4 text-sm text-error ${className}`}
      role="alert"
    >
      <p>{message}</p>
      {onRetry && (
        <div className="mt-3">
          <Button variant="secondary" size="sm" onClick={() => onRetry()}>
            Retry
          </Button>
        </div>
      )}
    </div>
  );
}
