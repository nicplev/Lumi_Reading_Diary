interface PageHeaderProps {
  title: string;
  description?: string;
  action?: React.ReactNode;
  /** Optional uppercase section eyebrow shown above the title, in the
   *  active section colour (e.g. "LIBRARY", "CLASS"). */
  eyebrow?: string;
}

export function PageHeader({ title, description, action, eyebrow }: PageHeaderProps) {
  return (
    <div className="flex items-start justify-between mb-6 gap-4">
      <div className="min-w-0">
        {eyebrow && (
          <p className="text-[11px] font-bold tracking-[0.12em] uppercase text-section mb-1.5">
            {eyebrow}
          </p>
        )}
        <h1 className="font-display text-[28px] font-extrabold tracking-tight text-ink">{title}</h1>
        {description && <p className="text-sm text-muted mt-1">{description}</p>}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}
