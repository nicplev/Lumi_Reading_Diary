'use client';

import { useState } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

interface ClassMeta {
  id: string;
  name: string;
}

interface ClassEngagementChartProps {
  classes: ClassMeta[];
  /** Rows keyed by [xKey] plus `${classId}:logs` and `${classId}:minutes`. */
  rows: Array<Record<string, number | string>>;
  metric: 'logs' | 'minutes';
  /** X-axis field on each row (e.g. 'label' for the analytics buckets). */
  xKey?: string;
}

// Distinct, readable-on-cream line colours (Lumi tokens + a couple of extras),
// cycled if a school has more active classes than colours.
const PALETTE = [
  '#56C8E6', // blue
  '#51BA65', // green
  '#EC4544', // red
  '#FAA51A', // orange
  '#1989CA', // indigo
  '#9B5DE5', // purple
  '#E6B600', // amber
  '#2A9FC4', // teal
  '#FF6F91', // pink
  '#429654', // deep green
];

/**
 * Multi-line class-comparison chart — one coloured line per class, so a school
 * admin can see at a glance how each class is tracking. The metric toggle
 * (logs / minutes) switches every line at once. Hovering a legend entry
 * highlights that class and dims the rest.
 *
 * Restored from the pre-#203 dashboard onto the analytics page, where it now
 * follows the term/period selector via [rows].
 */
export function ClassEngagementChart({ classes, rows, metric, xKey = 'label' }: ClassEngagementChartProps) {
  const [hovered, setHovered] = useState<string | null>(null);
  const unit = metric === 'minutes' ? 'min' : 'logs';

  const maxValue = Math.max(
    1,
    ...rows.flatMap((r) => classes.map((c) => Number(r[`${c.id}:${metric}`] ?? 0))),
  );

  return (
    <div className="h-full min-h-[240px]">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={rows} margin={{ top: 5, right: 5, bottom: 5, left: -15 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#E5E2DC" vertical={false} />
          <XAxis
            dataKey={xKey}
            tick={{ fill: '#6B6B6B', fontSize: 11, fontWeight: 600 }}
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
            formatter={(value: number, name: string) => [`${value} ${unit}`, name]}
            cursor={{ stroke: 'rgba(26,26,26,0.12)', strokeWidth: 1 }}
          />
          <Legend
            wrapperStyle={{ fontSize: 12, fontWeight: 600, paddingTop: 8 }}
            onMouseEnter={(o) => {
              const dk = (o as { dataKey?: string | number }).dataKey;
              setHovered(dk != null ? String(dk).split(':')[0] : null);
            }}
            onMouseLeave={() => setHovered(null)}
          />
          {classes.map((c, i) => (
            <Line
              key={c.id}
              type="monotone"
              dataKey={`${c.id}:${metric}`}
              name={c.name}
              stroke={PALETTE[i % PALETTE.length]}
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 3 }}
              strokeOpacity={hovered && hovered !== c.id ? 0.15 : 1}
              isAnimationActive={false}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
