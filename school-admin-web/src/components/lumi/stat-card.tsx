'use client';

import Link from 'next/link';
import { useId } from 'react';
import { AreaChart, Area, ResponsiveContainer } from 'recharts';

interface StatCardProps {
  title: string;
  value: string | number;
  icon?: React.ReactNode;
  trend?: { value: number; label: string };
  color?: 'pink' | 'red' | 'green' | 'orange' | 'blue' | 'yellow';
  href?: string;
  subtitle?: string;
  sparklineData?: number[];
}

// Brand-aligned tile colours — the icon chip + sparkline share one hue.
const sparkColors: Record<NonNullable<StatCardProps['color']>, string> = {
  pink: '#EC4544',
  red: '#EC4544',
  green: '#51BA65',
  orange: '#FAA51A',
  blue: '#56C8E6',
  yellow: '#FFCB05',
};

export function StatCard({ title, value, icon, trend, color = 'blue', href, subtitle, sparklineData }: StatCardProps) {
  const sparkGradId = `sparkGrad-${useId()}`;
  const sparkColor = sparkColors[color];

  const content = (
    <>
      {/* Title row: icon grouped with title */}
      <div className="flex items-center gap-2 mb-2">
        {icon && (
          <span
            className="inline-flex items-center justify-center w-8 h-8 rounded-[var(--radius-md)] text-base flex-shrink-0"
            style={{ backgroundColor: `${sparkColor}1F`, color: sparkColor }}
          >
            {icon}
          </span>
        )}
        <span className="text-sm font-semibold text-muted">{title}</span>
      </div>

      <div className="mt-auto">
        <div className="font-display text-[26px] font-extrabold text-ink leading-tight">{value}</div>

        {subtitle && (
          <p className="text-xs text-muted mt-1">{subtitle}</p>
        )}

        {trend && (
          <div className="flex items-center gap-1 mt-1">
            <span className={`text-xs font-semibold ${trend.value >= 0 ? 'text-success' : 'text-error'}`}>
              {trend.value >= 0 ? '↑' : '↓'} {Math.abs(trend.value)}%
            </span>
            <span className="text-xs text-muted">{trend.label}</span>
          </div>
        )}
      </div>

      {/* Sparkline */}
      {sparklineData && sparklineData.length > 1 && (
        <div className="mt-3 -mx-1 h-12">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={sparklineData.map((v, i) => ({ i, v }))} margin={{ top: 2, right: 2, bottom: 2, left: 2 }}>
              <defs>
                <linearGradient id={sparkGradId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={sparkColor} stopOpacity={0.25} />
                  <stop offset="100%" stopColor={sparkColor} stopOpacity={0} />
                </linearGradient>
              </defs>
              <Area
                type="monotone"
                dataKey="v"
                stroke={sparkColor}
                strokeWidth={1.5}
                fill={`url(#${sparkGradId})`}
                dot={false}
                isAnimationActive={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      )}
    </>
  );

  const className = `bg-paper rounded-[var(--radius-lg)] border border-rule shadow-card p-4 min-h-[132px] flex flex-col ${href ? 'hover:shadow-card-hover hover:-translate-y-0.5 transition' : ''}`;

  if (href) {
    return (
      <Link href={href} className={`block ${className}`}>
        {content}
      </Link>
    );
  }

  return <div className={className}>{content}</div>;
}
