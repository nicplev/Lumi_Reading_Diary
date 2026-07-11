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
    <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div className="min-w-0">
        {eyebrow && (
          <p className="text-[11px] font-bold tracking-[0.12em] uppercase text-section-strong mb-1.5">
            {eyebrow}
          </p>
        )}
        <h1 className="font-display text-[28px] font-extrabold tracking-tight text-ink">{title}</h1>
        {description && <p className="text-sm text-muted mt-1">{description}</p>}
      </div>
      {action && <div className="w-full shrink-0 sm:w-auto [&>a]:block [&>a>button]:w-full">{action}</div>}
    </div>
  );
}
