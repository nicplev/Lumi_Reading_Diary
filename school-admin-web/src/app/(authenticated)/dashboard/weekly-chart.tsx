'use client';

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

interface WeeklyChartProps {
  data: Array<{ day: string; count: number }>;
}

export function WeeklyChart({ data }: WeeklyChartProps) {
  const maxValue = Math.max(...data.map(d => d.count), 1);

  return (
    <div className="h-[240px]">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 5, right: 5, bottom: 5, left: -15 }}>
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
            cursor={{ fill: 'rgba(255, 134, 152, 0.05)' }}
          />
          <Bar
            dataKey="count"
            fill="#FF8698"
            radius={[6, 6, 0, 0]}
            maxBarSize={40}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
