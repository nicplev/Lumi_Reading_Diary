"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { SchoolDetail } from "@/lib/firestore/schools";

const LEVEL_SCHEMAS = [
  {
    value: "none",
    label: "None",
    description: "Do not use reading levels",
  },
  {
    value: "aToZ",
    label: "A to Z",
    description: "Levels A through Z",
  },
  {
    value: "pmBenchmark",
    label: "PM Benchmark",
    description: "PM Benchmark levels 1-30",
  },
  {
    value: "lexile",
    label: "Lexile",
    description: "Lexile measure ranges",
  },
  {
    value: "custom",
    label: "Custom",
    description: "Define your own levels",
  },
];

interface ReadingLevelConfigProps {
  school: SchoolDetail;
}

export function ReadingLevelConfig({ school }: ReadingLevelConfigProps) {
  const router = useRouter();
  const [levelSchema, setLevelSchema] = useState(school.levelSchema);
  const [customLevels, setCustomLevels] = useState<string[]>(
    school.customLevels ?? []
  );
  const [newLevel, setNewLevel] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const addLevel = () => {
    const trimmed = newLevel.trim();
    if (trimmed && !customLevels.includes(trimmed)) {
      setCustomLevels([...customLevels, trimmed]);
      setNewLevel("");
    }
  };

  const removeLevel = (level: string) => {
    setCustomLevels(customLevels.filter((l) => l !== level));
  };

  const handleSave = async () => {
    setLoading(true);
    setError(null);
    setSuccess(false);

    try {
      const res = await fetch(`/api/schools/${school.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          levelSchema,
          customLevels: levelSchema === "custom" ? customLevels : [],
        }),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to update");
      }

      setSuccess(true);
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Reading Level Configuration</CardTitle>
        <CardDescription>
          Choose the reading level schema used by this school
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {error && (
          <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">
            {error}
          </div>
        )}
        {success && (
          <div className="rounded-md bg-green-100 p-3 text-sm text-green-800 dark:bg-green-900 dark:text-green-200">
            Reading level configuration updated.
          </div>
        )}

        <div className="space-y-2">
          <Label>Level Schema</Label>
          <Select value={levelSchema} onValueChange={(v) => v && setLevelSchema(v)}>
            <SelectTrigger className="max-w-sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {LEVEL_SCHEMAS.map((ls) => (
                <SelectItem key={ls.value} value={ls.value}>
                  {ls.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <p className="text-sm text-muted-foreground">
            {LEVEL_SCHEMAS.find((ls) => ls.value === levelSchema)?.description}
          </p>
        </div>

        {levelSchema === "custom" && (
          <div className="space-y-2">
            <Label>Custom Levels</Label>
            <div className="flex flex-wrap gap-2">
              {customLevels.map((level) => (
                <span
                  key={level}
                  className="inline-flex items-center gap-1 rounded-md bg-muted px-2 py-1 text-sm"
                >
                  {level}
                  <button
                    type="button"
                    onClick={() => removeLevel(level)}
                    className="text-muted-foreground hover:text-foreground"
                  >
                    <X className="h-3 w-3" />
                  </button>
                </span>
              ))}
            </div>
            <div className="flex gap-2">
              <Input
                value={newLevel}
                onChange={(e) => setNewLevel(e.target.value)}
                placeholder="Add a level..."
                className="max-w-xs"
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    addLevel();
                  }
                }}
              />
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={addLevel}
              >
                <Plus className="mr-1 h-4 w-4" />
                Add
              </Button>
            </div>
          </div>
        )}

        <div className="pt-4">
          <Button onClick={handleSave} disabled={loading}>
            {loading ? "Saving..." : "Save Configuration"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
