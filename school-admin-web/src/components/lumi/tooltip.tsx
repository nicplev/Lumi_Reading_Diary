import { Icon } from './icon';

interface InfoTooltipProps {
  children: React.ReactNode;
}

export function InfoTooltip({ children }: InfoTooltipProps) {
  return (
    <span className="relative group inline-flex items-center">
      <button
        type="button"
        className="inline-flex items-center justify-center text-text-secondary hover:text-charcoal transition-colors focus:outline-none focus-visible:outline-none cursor-help"
        tabIndex={0}
        aria-label="More information"
      >
        <Icon name="info" size={15} />
      </button>
      <span className="absolute left-1/2 -translate-x-1/2 bottom-full mb-2 z-50 invisible opacity-0 group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100 transition-opacity duration-150 w-80 bg-charcoal text-white text-xs rounded-[var(--radius-md)] px-3 py-2.5 shadow-lg leading-relaxed pointer-events-none">
        {children}
        {/* Arrow */}
        <span className="absolute left-1/2 -translate-x-1/2 top-full w-0 h-0 border-x-4 border-x-transparent border-t-4 border-t-charcoal" />
      </span>
    </span>
  );
}
