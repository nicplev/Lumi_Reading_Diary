"use client";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export type DateRangePreset = "thisWeek" | "thisMonth" | "last30" | "last90" | "custom";

interface DateRangePickerProps {
  startDate: string;
  endDate: string;
  preset: DateRangePreset;
  onRangeChange: (start: string, end: string, preset: DateRangePreset) => void;
  loading?: boolean;
}

function computePreset(preset: DateRangePreset): { start: string; end: string } {
  const now = new Date();
  const end = now.toISOString().split("T")[0];
  const start = new Date(now);

  switch (preset) {
    case "thisWeek":
      start.setDate(now.getDate() - now.getDay());
      break;
    case "thisMonth":
      start.setDate(1);
      break;
    case "last30":
      start.setDate(now.getDate() - 30);
      break;
    case "last90":
      start.setDate(now.getDate() - 90);
      break;
    default:
      return { start: "", end: "" };
  }
  return { start: start.toISOString().split("T")[0], end };
}

const presets: { label: string; value: DateRangePreset }[] = [
  { label: "This Week", value: "thisWeek" },
  { label: "This Month", value: "thisMonth" },
  { label: "Last 30 Days", value: "last30" },
  { label: "Last 90 Days", value: "last90" },
];

export function DateRangePicker({
  startDate,
  endDate,
  preset,
  onRangeChange,
  loading,
}: DateRangePickerProps) {
  const handlePreset = (p: DateRangePreset) => {
    const { start, end } = computePreset(p);
    onRangeChange(start, end, p);
  };

  return (
    <div className="flex flex-wrap items-end gap-2">
      {presets.map((p) => (
        <Button
          key={p.value}
          variant={preset === p.value ? "default" : "outline"}
          size="sm"
          onClick={() => handlePreset(p.value)}
          disabled={loading}
        >
          {p.label}
        </Button>
      ))}
      <div className="flex items-end gap-2">
        <Input
          type="date"
          value={startDate}
          onChange={(e) =>
            onRangeChange(e.target.value, endDate, "custom")
          }
          className="w-[140px]"
        />
        <span className="pb-1 text-sm text-muted-foreground">to</span>
        <Input
          type="date"
          value={endDate}
          onChange={(e) =>
            onRangeChange(startDate, e.target.value, "custom")
          }
          className="w-[140px]"
        />
        {preset === "custom" && (
          <Button
            size="sm"
            onClick={() => onRangeChange(startDate, endDate, "custom")}
            disabled={loading}
          >
            {loading ? "Loading..." : "Apply"}
          </Button>
        )}
      </div>
    </div>
  );
}

export function getDefaultRange(): { start: string; end: string } {
  return computePreset("thisWeek");
}
