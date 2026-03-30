interface StatCardProps {
  title: string;
  value: string | number;
  icon?: React.ReactNode;
  trend?: { value: number; label: string };
  color?: 'pink' | 'green' | 'orange' | 'blue';
}

const colorClasses = {
  pink: 'bg-rose-pink/10 text-rose-pink',
  green: 'bg-mint-green/40 text-mint-green-dark',
  orange: 'bg-warm-orange/10 text-warm-orange',
  blue: 'bg-sky-blue/40 text-sky-blue-dark',
};

export function StatCard({ title, value, icon, trend, color = 'pink' }: StatCardProps) {
  return (
    <div className="bg-surface rounded-[var(--radius-lg)] shadow-card p-5">
      <div className="flex items-start justify-between mb-3">
        <span className="text-sm font-semibold text-text-secondary">{title}</span>
        {icon && (
          <span className={`inline-flex items-center justify-center w-9 h-9 rounded-[var(--radius-md)] text-lg ${colorClasses[color]}`}>
            {icon}
          </span>
        )}
      </div>
      <div className="text-[28px] font-extrabold text-charcoal leading-tight">{value}</div>
      {trend && (
        <div className="flex items-center gap-1 mt-2">
          <span className={`text-xs font-semibold ${trend.value >= 0 ? 'text-success' : 'text-error'}`}>
            {trend.value >= 0 ? '↑' : '↓'} {Math.abs(trend.value)}%
          </span>
          <span className="text-xs text-text-secondary">{trend.label}</span>
        </div>
      )}
    </div>
  );
}
