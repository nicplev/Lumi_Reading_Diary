'use client';

import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

interface WeeklyChartProps {
  data: Array<{ day: string; count: number }>;
}

// Dashboard is the Lumi Blue section — its data-viz reads in blue.
const ACCENT = '#56C8E6';

export function WeeklyChart({ data }: WeeklyChartProps) {
  const maxValue = Math.max(...data.map(d => d.count), 1);

  return (
    <div className="h-[180px]">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 5, right: 5, bottom: 5, left: -15 }}>
          <defs>
            <linearGradient id="readingGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={ACCENT} stopOpacity={0.3} />
              <stop offset="100%" stopColor={ACCENT} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#E5E2DC" vertical={false} />
          <XAxis
            dataKey="day"
            tick={{ fill: '#6B6B6B', fontSize: 12, fontWeight: 600 }}
            tickLine={false}
            axisLine={{ stroke: '#E5E2DC' }}
          />
          <YAxis
            tick={{ fill: '#6B6B6B', fontSize: 12 }}
            tickLine={false}
            axisLine={false}
            domain={[0, Math.max(5, Math.ceil(maxValue * 1.2))]}
            allowDecimals={false}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: '#FFFFFF',
              border: '1px solid #E5E2DC',
              borderRadius: '12px',
              fontSize: '13px',
              fontWeight: 600,
              boxShadow: '0 8px 24px -12px rgba(26,26,26,0.16)',
            }}
            formatter={(value: number) => [`${value} logs`, 'Reading']}
            cursor={{ stroke: 'rgba(86, 200, 230, 0.25)', strokeWidth: 1 }}
          />
          <Area
            type="monotone"
            dataKey="count"
            stroke={ACCENT}
            strokeWidth={2}
            fill="url(#readingGradient)"
            dot={false}
            activeDot={{ r: 4, fill: ACCENT, strokeWidth: 0 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
