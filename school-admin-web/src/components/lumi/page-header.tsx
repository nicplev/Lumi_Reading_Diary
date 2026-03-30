interface PageHeaderProps {
  title: string;
  description?: string;
  action?: React.ReactNode;
}

export function PageHeader({ title, description, action }: PageHeaderProps) {
  return (
    <div className="flex items-start justify-between mb-6">
      <div>
        <h1 className="text-[28px] font-bold text-charcoal">{title}</h1>
        {description && <p className="text-sm text-text-secondary mt-1">{description}</p>}
      </div>
      {action && <div>{action}</div>}
    </div>
  );
}
