/**
 * Single source of truth for the reading-feeling scale in the portal — the web
 * mirror of `lib/core/feelings/feeling_scale.dart`. Colours match the blob
 * character art (concern → confident); keep in sync with the Flutter scale.
 *
 * Blob PNGs live in `public/blobs/` (vendored from the app's `assets/blobs/`).
 */

export type FeelingKey = 'hard' | 'tricky' | 'okay' | 'good' | 'great';

export interface FeelingMeta {
  key: FeelingKey;
  /** Short display label. */
  label: string;
  /** Canonical per-feeling colour (matches the blob art). */
  color: string;
  /** Public path to the blob asset. */
  blob: string;
  /** Position on the 1–5 mood scale (hard = 1 … great = 5). */
  value: number;
}

export const FEELINGS: Record<FeelingKey, FeelingMeta> = {
  hard: { key: 'hard', label: 'Hard', color: '#6FA8DC', blob: '/blobs/blob-hard.png', value: 1 },
  tricky: { key: 'tricky', label: 'Tricky', color: '#7CB97C', blob: '/blobs/blob-tricky.png', value: 2 },
  okay: { key: 'okay', label: 'Okay', color: '#E8C547', blob: '/blobs/blob-okay.png', value: 3 },
  good: { key: 'good', label: 'Good', color: '#F5A347', blob: '/blobs/blob-good.png', value: 4 },
  great: { key: 'great', label: 'Great', color: '#E86B6B', blob: '/blobs/blob-great.png', value: 5 },
};

/** Feeling keys ordered hard → great (concern → confident). */
export const FEELING_ORDER: FeelingKey[] = ['hard', 'tricky', 'okay', 'good', 'great'];

/** Metadata for a feeling key, or undefined if unrecognised. */
export function feelingMeta(key: string): FeelingMeta | undefined {
  return (FEELINGS as Record<string, FeelingMeta>)[key];
}
