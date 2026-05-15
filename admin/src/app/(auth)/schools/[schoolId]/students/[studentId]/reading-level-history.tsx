"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { formatDateTime } from "@/lib/utils";
import type { ReadingLevelEventItem } from "@/lib/firestore/students";

interface ReadingLevelHistoryProps {
  events: ReadingLevelEventItem[];
  schoolId: string;
  studentId: string;
}

export function ReadingLevelHistory({
  events,
  schoolId,
  studentId,
}: ReadingLevelHistoryProps) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [level, setLevel] = useState("");
  const [reason, setReason] = useState("");

  const handleChangeLevel = async () => {
    if (!level) {
      setError("Reading level is required");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/students/${studentId}/reading-level`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ level, reason: reason || undefined }),
        }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to update reading level");
      }
      setOpen(false);
      setLevel("");
      setReason("");
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle>Reading Level History</CardTitle>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger render={<Button variant="outline" />}>
            Change Level
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Change Reading Level</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              {error && (
                <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">
                  {error}
                </div>
              )}
              <div className="space-y-2">
                <Label>New Level *</Label>
                <Input
                  value={level}
                  onChange={(e) => setLevel(e.target.value)}
                  placeholder="e.g. Level C, PM 12, 450L"
                />
              </div>
              <div className="space-y-2">
                <Label>Reason</Label>
                <Textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Optional reason for level change"
                  rows={3}
                />
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <Button variant="outline" onClick={() => setOpen(false)}>
                  Cancel
                </Button>
                <Button onClick={handleChangeLevel} disabled={loading}>
                  {loading ? "Updating..." : "Update Level"}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </CardHeader>
      <CardContent>
        {events.length > 0 ? (
          <div className="space-y-4">
            {events.map((event) => (
              <div
                key={event.id}
                className="flex items-start gap-4 rounded-md border p-3"
              >
                <div className="flex-1 space-y-1">
                  <div className="flex items-center gap-2 text-sm font-medium">
                    <span>{event.fromLevel ?? "None"}</span>
                    <ArrowRight className="h-3 w-3" />
                    <span>{event.toLevel ?? "None"}</span>
                  </div>
                  {event.reason && (
                    <p className="text-sm text-muted-foreground">
                      {event.reason}
                    </p>
                  )}
                  <p className="text-xs text-muted-foreground">
                    {event.changedByName || "System"} &middot;{" "}
                    {formatDateTime(event.createdAt)}
                  </p>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            No reading level changes recorded.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
