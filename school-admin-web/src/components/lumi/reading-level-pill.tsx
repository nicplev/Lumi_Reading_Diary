'use client';

interface ReadingLevelPillProps {
  level?: string;
  colorHex?: string;
  onClick?: () => void;
  size?: 'sm' | 'md';
}

const sizeClasses = {
  sm: 'px-2 py-0.5 text-xs',
  md: 'px-3 py-1 text-sm',
};

export function ReadingLevelPill({ level, colorHex, onClick, size = 'md' }: ReadingLevelPillProps) {
  if (!level) {
    return (
      <span className={`inline-flex items-center rounded-[var(--radius-pill)] font-semibold text-text-secondary/50 bg-background border border-divider ${sizeClasses[size]}`}>
        No Level
      </span>
    );
  }

  const bgColor = colorHex ? `${colorHex}20` : 'var(--color-rose-pink-light)';
  const textColor = colorHex || 'var(--color-rose-pink-dark)';

  const Tag = onClick ? 'button' : 'span';

  return (
    <Tag
      onClick={onClick}
      className={`inline-flex items-center gap-1 rounded-[var(--radius-pill)] font-bold transition-colors ${sizeClasses[size]} ${
        onClick ? 'cursor-pointer hover:opacity-80' : ''
      }`}
      style={{ backgroundColor: bgColor, color: textColor }}
    >
      {level}
      {onClick && (
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
          <path d="M4 5l2 2 2-2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </Tag>
  );
}
