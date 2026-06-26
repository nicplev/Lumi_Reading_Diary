'use client';

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
  if (!hasAudio) return null;

  return (
    <div className="mt-3">
      <div className="rounded-[var(--radius-md)] bg-background p-3">
        <div className="flex items-center gap-2 mb-2">
          <Icon name="mic" size={16} className="text-rose-pink" />
          <span className="text-xs font-semibold text-charcoal">Comprehension answer</span>
          {durationSec ? (
            <span className="text-xs text-text-secondary">{formatDuration(durationSec)}</span>
          ) : null}
        </div>
        <audio controls preload="none" src={`/api/reading-logs/${logId}/audio`} className="w-full h-9">
          Your browser does not support audio playback.
        </audio>
      </div>
    </div>
  );
}
