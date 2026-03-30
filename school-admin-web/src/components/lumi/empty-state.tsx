import { Icon } from './icon';

interface EmptyStateProps {
  icon?: React.ReactNode;
  title: string;
  description?: string;
  action?: React.ReactNode;
}

export function EmptyState({ icon = <Icon name="inbox" size={40} />, title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <span className="text-text-secondary/40 mb-4">{icon}</span>
      <h3 className="text-lg font-bold text-charcoal mb-1">{title}</h3>
      {description && <p className="text-sm text-text-secondary max-w-sm">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}
