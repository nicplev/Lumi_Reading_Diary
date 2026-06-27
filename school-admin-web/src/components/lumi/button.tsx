import { forwardRef, ButtonHTMLAttributes } from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'outline' | 'ghost' | 'danger';
type ButtonSize = 'sm' | 'md' | 'lg';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
}

// The primary + secondary variants follow the active section accent
// (bg-section / bg-section-tint); danger is always Lumi Red, regardless of
// section, because destructive actions read the same everywhere.
const variantClasses: Record<ButtonVariant, string> = {
  primary: 'bg-section text-on-section hover:brightness-95 shadow-card',
  secondary: 'bg-section-tint text-ink hover:brightness-95',
  outline: 'border border-rule bg-paper text-ink hover:bg-cream',
  ghost: 'text-ink hover:bg-cream',
  danger: 'bg-lumi-red text-white hover:bg-lumi-red-dark shadow-card',
};

const sizeClasses: Record<ButtonSize, string> = {
  sm: 'px-3 py-1.5 text-[13px] rounded-[var(--radius-sm)]',
  md: 'px-4 py-2.5 text-[15px] rounded-[var(--radius-md)]',
  lg: 'px-6 py-3 text-[15px] rounded-[var(--radius-md)]',
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = 'primary', size = 'md', loading, className = '', children, disabled, ...props }, ref) => {
    return (
      <button
        ref={ref}
        disabled={disabled || loading}
        className={`inline-flex items-center justify-center font-display font-bold transition disabled:opacity-50 disabled:cursor-not-allowed ${variantClasses[variant]} ${sizeClasses[size]} ${className}`}
        {...props}
      >
        {loading && (
          <svg className="animate-spin -ml-1 mr-2 h-4 w-4" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
        )}
        {children}
      </button>
    );
  }
);
Button.displayName = 'Button';
