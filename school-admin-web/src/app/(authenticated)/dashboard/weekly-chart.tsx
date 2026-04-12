'use client';

import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

interface WeeklyChartProps {
  data: Array<{ day: string; count: number }>;
}

export function WeeklyChart({ data }: WeeklyChartProps) {
  const maxValue = Math.max(...data.map(d => d.count), 1);

  return (
    <div className="h-[180px]">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 5, right: 5, bottom: 5, left: -15 }}>
          <defs>
            <linearGradient id="readingGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#FF8698" stopOpacity={0.3} />
              <stop offset="100%" stopColor="#FF8698" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
          <XAxis
            dataKey="day"
            tick={{ fill: '#6B7280', fontSize: 12, fontWeight: 600 }}
            tickLine={false}
            axisLine={{ stroke: '#E5E7EB' }}
          />
          <YAxis
            tick={{ fill: '#6B7280', fontSize: 12 }}
            tickLine={false}
            axisLine={false}
            domain={[0, Math.ceil(maxValue * 1.2)]}
            allowDecimals={false}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: '#FFFFFF',
              border: '1px solid #E5E7EB',
              borderRadius: '12px',
              fontSize: '13px',
              fontWeight: 600,
              boxShadow: '0 4px 10px -6px rgba(18,18,17,0.1)',
            }}
            formatter={(value: number) => [`${value} logs`, 'Reading']}
            cursor={{ stroke: 'rgba(255, 134, 152, 0.2)', strokeWidth: 1 }}
          />
          <Area
            type="monotone"
            dataKey="count"
            stroke="#FF8698"
            strokeWidth={2}
            fill="url(#readingGradient)"
            dot={false}
            activeDot={{ r: 4, fill: '#FF8698', strokeWidth: 0 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
