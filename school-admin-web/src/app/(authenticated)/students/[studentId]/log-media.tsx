'use client';

import { useState } from 'react';
import { Icon } from '@/components/lumi/icon';

function formatDuration(sec: number | null): string {
  if (!sec || sec <= 0) return '';
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

/**
 * The child's comprehension recording for a reading log, streamed session-gated
 * from /api/reading-logs/[logId]/audio and lazy-loaded on play (preload="none").
 */
export function LogMedia({
  logId,
  hasAudio,
  durationSec,
}: {
  logId: string;
  hasAudio: boolean;
  durationSec: number | null;
}) {
  const [failed, setFailed] = useState(false);
  if (!hasAudio) return null;

  return (
    <div className="mt-3">
      <div className="rounded-[var(--radius-md)] bg-cream p-3">
        <div className="flex items-center gap-2 mb-2">
          <Icon name="mic" size={16} className="text-section" />
          <span className="text-xs font-semibold text-ink">Comprehension answer</span>
          {durationSec ? (
            <span className="text-xs text-muted">{formatDuration(durationSec)}</span>
          ) : null}
        </div>
        {failed ? (
          <p className="text-xs text-muted">
            Recording unavailable — it may have been removed or you don&apos;t have access.
          </p>
        ) : (
          <audio
            controls
            preload="none"
            src={`/api/reading-logs/${logId}/audio`}
            onError={() => setFailed(true)}
            className="w-full h-9"
          >
            Your browser does not support audio playback.
          </audio>
        )}
      </div>
    </div>
  );
}
