import { feelingMeta } from '@/lib/feelings';

/** Renders a reading-feeling blob (the app's mood art) for a feeling key.
 *  Returns null for unrecognised keys. Replaces the old emoji moods. */
export function FeelingBlob({
  feeling,
  size = 24,
  className = '',
}: {
  feeling: string;
  size?: number;
  className?: string;
}) {
  const meta = feelingMeta(feeling);
  if (!meta) return null;
  return (
    <img
      src={meta.blob}
      alt={meta.label}
      title={meta.label}
      width={size}
      height={size}
      className={`inline-block object-contain ${className}`}
      style={{ width: size, height: size }}
    />
  );
}
