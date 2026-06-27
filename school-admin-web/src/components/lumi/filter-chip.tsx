'use client';

interface FilterChipProps {
  label: React.ReactNode;
  selected: boolean;
  onClick: () => void;
  count?: number;
}

export function FilterChip({ label, selected, onClick, count }: FilterChipProps) {
  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-[var(--radius-pill)] text-[13px] font-semibold transition-colors ${
        selected
          ? 'bg-section text-on-section'
          : 'bg-paper text-muted border border-rule hover:bg-cream'
      }`}
    >
      {label}
      {count != null && (
        <span className={`text-xs ${selected ? 'text-on-section/80' : 'text-muted/60'}`}>
          {count}
        </span>
      )}
    </button>
  );
}

interface FilterChipGroupProps {
  options: { value: string; label: string; count?: number }[];
  selected: string[];
  onChange: (selected: string[]) => void;
}

export function FilterChipGroup({ options, selected, onChange }: FilterChipGroupProps) {
  const toggle = (value: string) => {
    if (selected.includes(value)) {
      onChange(selected.filter((s) => s !== value));
    } else {
      onChange([...selected, value]);
    }
  };

  return (
    <div className="flex flex-wrap gap-2">
      {options.map((opt) => (
        <FilterChip
          key={opt.value}
          label={opt.label}
          count={opt.count}
          selected={selected.includes(opt.value)}
          onClick={() => toggle(opt.value)}
        />
      ))}
    </div>
  );
}
