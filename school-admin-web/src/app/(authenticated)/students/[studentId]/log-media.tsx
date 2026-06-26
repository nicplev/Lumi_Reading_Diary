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
 * Media attached to a reading log: the child's comprehension recording (streamed
 * session-gated from /api/reading-logs/[logId]/audio, lazy-loaded on play) and
 * any parent photo attachments (thumbnails → click-to-enlarge lightbox).
 */
export function LogMedia({
  logId,
  hasAudio,
  durationSec,
  photoUrls,
}: {
  logId: string;
  hasAudio: boolean;
  durationSec: number | null;
  photoUrls: string[];
}) {
  const [lightbox, setLightbox] = useState<string | null>(null);

  if (!hasAudio && photoUrls.length === 0) return null;

  return (
    <div className="mt-3 space-y-3">
      {hasAudio && (
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
      )}

      {photoUrls.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {photoUrls.map((url, i) => (
            <button
              key={url}
              type="button"
              onClick={() => setLightbox(url)}
              className="block w-16 h-16 rounded-[var(--radius-md)] overflow-hidden border border-divider hover:opacity-90 transition-opacity"
              aria-label={`View reading photo ${i + 1}`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={url} alt={`Reading photo ${i + 1}`} className="w-full h-full object-cover" />
            </button>
          ))}
        </div>
      )}

      {lightbox && (
        <div
          className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4"
          onClick={() => setLightbox(null)}
          role="dialog"
          aria-modal="true"
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={lightbox}
            alt="Reading photo"
            className="max-w-full max-h-full rounded-[var(--radius-lg)] shadow-card"
            onClick={(e) => e.stopPropagation()}
          />
          <button
            type="button"
            onClick={() => setLightbox(null)}
            className="absolute top-4 right-4 text-white/90 hover:text-white"
            aria-label="Close"
          >
            <Icon name="close" size={28} />
          </button>
        </div>
      )}
    </div>
  );
}
