"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
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
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import type { SchoolListItem } from "@/lib/firestore/schools";

interface CreateCodeDialogProps {
  schools: SchoolListItem[];
}

export function CreateCodeDialog({ schools }: CreateCodeDialogProps) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [schoolId, setSchoolId] = useState("");
  const [maxUsages, setMaxUsages] = useState("");
  const [expiresInDays, setExpiresInDays] = useState("");

  const handleCreate = async () => {
    if (!schoolId) {
      setError("Please select a school");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const body: Record<string, unknown> = { schoolId };
      if (maxUsages) body.maxUsages = parseInt(maxUsages, 10);
      if (expiresInDays) body.expiresInDays = parseInt(expiresInDays, 10);

      const res = await fetch("/api/school-codes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to create code");
      }

      setOpen(false);
      setSchoolId("");
      setMaxUsages("");
      setExpiresInDays("");
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button />}>
        <Plus className="mr-2 h-4 w-4" />
        Generate Code
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Generate School Code</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 pt-4">
          {error && (
            <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">
              {error}
            </div>
          )}

          <div className="space-y-2">
            <Label>School *</Label>
            <Select value={schoolId} onValueChange={(v) => v && setSchoolId(v)}>
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

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>Max Usages</Label>
              <Input
                type="number"
                placeholder="Unlimited"
                value={maxUsages}
                onChange={(e) => setMaxUsages(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>Expires In (days)</Label>
              <Input
                type="number"
                placeholder="Never"
                value={expiresInDays}
                onChange={(e) => setExpiresInDays(e.target.value)}
              />
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button onClick={handleCreate} disabled={loading}>
              {loading ? "Generating..." : "Generate"}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
