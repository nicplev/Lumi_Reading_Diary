type BadgeVariant = 'default' | 'success' | 'warning' | 'error' | 'info';

interface BadgeProps {
  children: React.ReactNode;
  variant?: BadgeVariant;
  className?: string;
}

const variantClasses: Record<BadgeVariant, string> = {
  default: 'bg-cream text-muted',
  success: 'bg-tint-green text-lumi-green-dark',
  warning: 'bg-tint-yellow text-ink',
  error: 'bg-lumi-red/10 text-lumi-red',
  info: 'bg-tint-blue text-lumi-blue-dark',
};

export function Badge({ children, variant = 'default', className = '' }: BadgeProps) {
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-[var(--radius-pill)] text-xs font-semibold ${variantClasses[variant]} ${className}`}>
      {children}
    </span>
  );
}
