"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { SchoolListItem } from "@/lib/firestore/schools";

interface ExportToolProps {
  schools: SchoolListItem[];
}

const dataTypes = [
  { id: "students", label: "Students", needsDateRange: false },
  { id: "readingLogs", label: "Reading Logs", needsDateRange: true },
  { id: "allocations", label: "Allocations", needsDateRange: false },
] as const;

export function ExportTool({ schools }: ExportToolProps) {
  const [schoolId, setSchoolId] = useState("");
  const [selectedTypes, setSelectedTypes] = useState<string[]>([]);
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [downloading, setDownloading] = useState<string | null>(null);

  const toggleType = (typeId: string) => {
    setSelectedTypes((prev) =>
      prev.includes(typeId)
        ? prev.filter((t) => t !== typeId)
        : [...prev, typeId]
    );
  };

  const needsDateRange = selectedTypes.includes("readingLogs");

  const handleDownload = async (type: string) => {
    if (!schoolId) return;
    if (type === "readingLogs" && (!startDate || !endDate)) {
      toast.error("Date range is required for reading log exports");
      return;
    }
    setDownloading(type);

    const params = new URLSearchParams({ schoolId, type });
    if (type === "readingLogs") {
      params.set("startDate", startDate);
      params.set("endDate", endDate);
    }

    try {
      window.location.href = `/api/export?${params.toString()}`;
    } finally {
      setTimeout(() => setDownloading(null), 1000);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Configure Export</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="space-y-2">
          <Label>School *</Label>
          <Select
            value={schoolId}
            onValueChange={(v) => v && setSchoolId(v)}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select a school" />
            </SelectTrigger>
            <SelectContent>
              {schools.map((s) => (
                <SelectItem key={s.id} value={s.id}>
                  {s.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="space-y-3">
          <Label>Data Types *</Label>
          {dataTypes.map((dt) => (
            <div key={dt.id} className="flex items-center gap-2">
              <Checkbox
                id={`export-${dt.id}`}
                checked={selectedTypes.includes(dt.id)}
                onCheckedChange={() => toggleType(dt.id)}
              />
              <Label htmlFor={`export-${dt.id}`} className="font-normal">
                {dt.label}
              </Label>
            </div>
          ))}
        </div>

        {needsDateRange && (
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>Start Date</Label>
              <Input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>End Date</Label>
              <Input
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
              />
            </div>
          </div>
        )}

        <div className="flex flex-wrap gap-2 pt-2">
          {selectedTypes.map((type) => (
            <Button
              key={type}
              onClick={() => handleDownload(type)}
              disabled={!schoolId || downloading === type}
            >
              <Download className="mr-2 h-4 w-4" />
              {downloading === type
                ? "Downloading..."
                : `Download ${dataTypes.find((d) => d.id === type)?.label}`}
            </Button>
          ))}
          {selectedTypes.length === 0 && (
            <p className="text-sm text-muted-foreground">
              Select at least one data type to export.
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
