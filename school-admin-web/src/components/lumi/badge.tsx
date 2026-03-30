type BadgeVariant = 'default' | 'success' | 'warning' | 'error' | 'info';

interface BadgeProps {
  children: React.ReactNode;
  variant?: BadgeVariant;
  className?: string;
}

const variantClasses: Record<BadgeVariant, string> = {
  default: 'bg-background text-text-secondary',
  success: 'bg-mint-green/40 text-mint-green-dark',
  warning: 'bg-soft-yellow/60 text-charcoal',
  error: 'bg-error/10 text-error',
  info: 'bg-sky-blue/40 text-sky-blue-dark',
};

export function Badge({ children, variant = 'default', className = '' }: BadgeProps) {
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-[var(--radius-pill)] text-xs font-semibold ${variantClasses[variant]} ${className}`}>
      {children}
    </span>
  );
}
