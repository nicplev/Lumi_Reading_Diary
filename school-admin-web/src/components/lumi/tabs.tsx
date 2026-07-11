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
    <div className="mb-6 overflow-x-auto border-b border-rule">
      <nav className="-mb-px flex min-w-max gap-6 pr-4">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onChange(tab.id)}
            className={`pb-3 text-sm font-semibold transition-colors whitespace-nowrap focus:outline-none focus-visible:outline-none ${
              activeTab === tab.id
                ? 'border-b-2 border-section text-ink font-bold'
                : 'text-muted hover:text-ink'
            }`}
          >
            <span className="flex items-center gap-1.5">
              {tab.icon && <span>{tab.icon}</span>}
              {tab.label}
              {tab.count != null && (
                <span className={`text-xs px-1.5 py-0.5 rounded-[var(--radius-pill)] ${
                  activeTab === tab.id ? 'bg-section/10 text-section-strong' : 'bg-cream text-muted'
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
