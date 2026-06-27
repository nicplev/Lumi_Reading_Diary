import { characterImageSrc } from '@/lib/characters';

interface AvatarProps {
  name: string;
  imageUrl?: string;
  /** Lumi character id; rendered as the character PNG when recognised. */
  characterId?: string;
  size?: 'xs' | 'sm' | 'md' | 'lg';
  className?: string;
}

const sizeClasses = {
  xs: 'w-5 h-5 text-[10px]',
  sm: 'w-8 h-8 text-xs',
  md: 'w-10 h-10 text-sm',
  lg: 'w-14 h-14 text-lg',
};

function getInitials(name: string): string {
  return name
    .split(' ')
    .map((n) => n[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);
}

const avatarColors = [
  'bg-rose-pink/20 text-rose-pink-dark',
  'bg-mint-green/40 text-mint-green-dark',
  'bg-warm-orange/20 text-warm-orange',
  'bg-sky-blue/40 text-sky-blue-dark',
  'bg-soft-yellow/60 text-charcoal',
];

function getColorForName(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
  return avatarColors[Math.abs(hash) % avatarColors.length];
}

export function Avatar({ name, imageUrl, characterId, size = 'md', className = '' }: AvatarProps) {
  if (imageUrl) {
    return (
      <img
        src={imageUrl}
        alt={name}
        className={`${sizeClasses[size]} rounded-full object-cover ${className}`}
      />
    );
  }

  // Character art is a full-bleed illustration — show it contained with NO
  // circular clip so it's never cropped (mirrors the app's StudentAvatar, which
  // renders the character at size with BoxFit.contain and no circle).
  const charSrc = characterImageSrc(characterId);
  if (charSrc) {
    return (
      <img
        src={charSrc}
        alt={name}
        className={`${sizeClasses[size]} object-contain ${className}`}
      />
    );
  }

  return (
    <div
      className={`${sizeClasses[size]} rounded-full inline-flex items-center justify-center font-bold ${getColorForName(name)} ${className}`}
    >
      {getInitials(name)}
    </div>
  );
}
