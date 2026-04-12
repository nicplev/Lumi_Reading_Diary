'use client';

interface Tab {
  id: string;
  label: string;
  count?: number;
  icon?: React.ReactNode;
}

interface TabsProps {
  tabs: Tab[];
  activeTab: string;
  onChange: (id: string) => void;
}

export function Tabs({ tabs, activeTab, onChange }: TabsProps) {
  return (
    <div className="border-b border-divider mb-6">
      <nav className="flex gap-6 -mb-px">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onChange(tab.id)}
            className={`pb-3 text-sm font-semibold transition-colors whitespace-nowrap focus:outline-none focus-visible:outline-none ${
              activeTab === tab.id
                ? 'border-b-2 border-rose-pink text-charcoal font-bold'
                : 'text-text-secondary hover:text-charcoal'
            }`}
          >
            <span className="flex items-center gap-1.5">
              {tab.icon && <span>{tab.icon}</span>}
              {tab.label}
              {tab.count != null && (
                <span className={`text-xs px-1.5 py-0.5 rounded-[var(--radius-pill)] ${
                  activeTab === tab.id ? 'bg-rose-pink/10 text-rose-pink' : 'bg-background text-text-secondary'
                }`}>
                  {tab.count}
                </span>
              )}
            </span>
          </button>
        ))}
      </nav>
    </div>
  );
}
