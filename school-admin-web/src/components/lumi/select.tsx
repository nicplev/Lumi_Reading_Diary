import { forwardRef, SelectHTMLAttributes } from 'react';

interface SelectOption {
  value: string;
  label: string;
  disabled?: boolean;
}

interface SelectProps extends Omit<SelectHTMLAttributes<HTMLSelectElement>, 'onChange'> {
  label?: string;
  options: SelectOption[];
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  error?: string;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ label, options, value, onChange, placeholder, error, className = '', id, ...props }, ref) => {
    return (
      <div>
        {label && (
          <label htmlFor={id} className="block text-sm font-semibold text-charcoal mb-1.5">
            {label}
          </label>
        )}
        <div className="relative">
          <select
            ref={ref}
            id={id}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            className={`w-full px-4 py-3 rounded-[var(--radius-md)] border bg-surface text-charcoal focus:outline-none focus:ring-2 focus:ring-rose-pink/30 focus:border-rose-pink transition-colors text-[15px] appearance-none pr-10 ${error ? 'border-error' : 'border-divider'} ${!value && placeholder ? 'text-text-secondary/50' : ''} ${className}`}
            {...props}
          >
            {placeholder && (
              <option value="" disabled>
                {placeholder}
              </option>
            )}
            {options.map((opt) => (
              <option key={opt.value} value={opt.value} disabled={opt.disabled}>
                {opt.label}
              </option>
            ))}
          </select>
          <svg
            className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-text-secondary"
            width="16"
            height="16"
            viewBox="0 0 16 16"
            fill="none"
          >
            <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        {error && <p className="mt-1 text-xs text-error">{error}</p>}
      </div>
    );
  }
);
Select.displayName = 'Select';
