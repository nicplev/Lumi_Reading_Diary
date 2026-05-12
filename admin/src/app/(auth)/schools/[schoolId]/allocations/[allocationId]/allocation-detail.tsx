"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { formatDate } from "@/lib/utils";
import type {
  AllocationDetail as AllocationDetailType,
} from "@/lib/firestore/allocations";
import type { ClassListItem } from "@/lib/firestore/classes";
import type { SchoolUserListItem } from "@/lib/firestore/school-users";
import type { StudentListItem } from "@/lib/firestore/students";

interface AllocationDetailProps {
  schoolId: string;
  allocation: AllocationDetailType;
  classes: ClassListItem[];
  users: SchoolUserListItem[];
  students: StudentListItem[];
}

export function AllocationDetail({
  schoolId,
  allocation,
  classes,
  users,
  students,
}: AllocationDetailProps) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [deactivateOpen, setDeactivateOpen] = useState(false);

  // Edit form
  const [targetMinutes, setTargetMinutes] = useState(
    String(allocation.targetMinutes)
  );
  const [endDate, setEndDate] = useState(
    allocation.endDate
      ? new Date(allocation.endDate).toISOString().split("T")[0]
      : ""
  );
  const [bookTitlesStr, setBookTitlesStr] = useState(
    (allocation.bookTitles ?? []).join(", ")
  );
  const [templateName, setTemplateName] = useState(
    allocation.templateName ?? ""
  );

  const classMap = new Map(classes.map((c) => [c.id, c.name]));
  const userMap = new Map(users.map((u) => [u.id, u.fullName]));
  const studentMap = new Map(
    students.map((s) => [s.id, `${s.firstName} ${s.lastName}`])
  );

  const handleSave = async () => {
    setLoading(true);
    try {
      const body: Record<string, unknown> = {
        targetMinutes: parseInt(targetMinutes, 10),
        templateName: templateName || undefined,
      };
      if (endDate) body.endDate = endDate;
      if (bookTitlesStr) {
        body.bookTitles = bookTitlesStr
          .split(",")
          .map((t) => t.trim())
          .filter(Boolean);
      }

      const res = await fetch(
        `/api/schools/${schoolId}/allocations/${allocation.id}`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to update allocation");
      }
      toast.success("Allocation updated successfully");
      setEditing(false);
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleDeactivate = async () => {
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/allocations/${allocation.id}`,
        { method: "DELETE" }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to deactivate allocation");
      }
      setDeactivateOpen(false);
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Info Card */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Allocation Information</CardTitle>
          <div className="flex gap-2">
            {!editing && allocation.isActive && (
              <>
                <Button variant="outline" onClick={() => setEditing(true)}>
                  Edit
                </Button>
                <Button
                  variant="destructive"
                  onClick={() => setDeactivateOpen(true)}
                >
                  Deactivate
                </Button>
              </>
            )}
          </div>
        </CardHeader>
        <CardContent>
          {editing ? (
            <div className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Target Minutes</Label>
                  <Input
                    type="number"
                    value={targetMinutes}
                    onChange={(e) => setTargetMinutes(e.target.value)}
                    min={1}
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
              <div className="space-y-2">
                <Label>Book Titles (comma-separated)</Label>
                <Input
                  value={bookTitlesStr}
                  onChange={(e) => setBookTitlesStr(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label>Template Name</Label>
                <Input
                  value={templateName}
                  onChange={(e) => setTemplateName(e.target.value)}
                />
              </div>
              <div className="flex gap-2 pt-2">
                <Button onClick={handleSave} disabled={loading}>
                  {loading ? "Saving..." : "Save Changes"}
                </Button>
                <Button
                  variant="outline"
                  onClick={() => {
                    setEditing(false);
                    setTargetMinutes(String(allocation.targetMinutes));
                    setEndDate(
                      allocation.endDate
                        ? new Date(allocation.endDate)
                            .toISOString()
                            .split("T")[0]
                        : ""
                    );
                    setBookTitlesStr(
                      (allocation.bookTitles ?? []).join(", ")
                    );
                    setTemplateName(allocation.templateName ?? "");
                  }}
                >
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <p className="text-sm text-muted-foreground">Class</p>
                <p className="font-medium">
                  {classMap.get(allocation.classId) ?? "\u2014"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Teacher</p>
                <p className="font-medium">
                  {userMap.get(allocation.teacherId) ?? "\u2014"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Type</p>
                <StatusBadge status={allocation.type} />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Cadence</p>
                <p className="font-medium capitalize">{allocation.cadence}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Target Minutes</p>
                <p className="font-medium">{allocation.targetMinutes} min</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Status</p>
                <StatusBadge
                  status={allocation.isActive ? "active" : "completed"}
                />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Start Date</p>
                <p className="font-medium">
                  {formatDate(allocation.startDate)}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">End Date</p>
                <p className="font-medium">
                  {formatDate(allocation.endDate)}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Recurring</p>
                <p className="font-medium">
                  {allocation.isRecurring ? "Yes" : "No"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Template Name</p>
                <p className="font-medium">
                  {allocation.templateName ?? "\u2014"}
                </p>
              </div>
              {allocation.levelStart && (
                <div>
                  <p className="text-sm text-muted-foreground">Level Range</p>
                  <p className="font-medium">
                    {allocation.levelStart} – {allocation.levelEnd ?? ""}
                  </p>
                </div>
              )}
              {allocation.bookTitles && allocation.bookTitles.length > 0 && (
                <div className="sm:col-span-2">
                  <p className="text-sm text-muted-foreground">Book Titles</p>
                  <p className="font-medium">
                    {allocation.bookTitles.join(", ")}
                  </p>
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Assignment Items Card */}
      {allocation.assignmentItems.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Assignment Items</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {allocation.assignmentItems.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between rounded-md border p-3"
                >
                  <div>
                    <p className="font-medium">{item.title}</p>
                    {item.isbn && (
                      <p className="text-sm text-muted-foreground">
                        ISBN: {item.isbn}
                      </p>
                    )}
                  </div>
                  {item.isDeleted && (
                    <StatusBadge status="disabled" />
                  )}
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Student Overrides Card */}
      {allocation.studentOverrides.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Student Overrides (Read-only)</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {allocation.studentOverrides.map((override) => (
                <div
                  key={override.studentId}
                  className="flex items-center justify-between rounded-md border p-3"
                >
                  <p className="font-medium">
                    {studentMap.get(override.studentId) ?? override.studentId}
                  </p>
                  <div className="flex gap-4 text-sm text-muted-foreground">
                    <span>
                      Removed: {override.removedItemIds.length}
                    </span>
                    <span>
                      Added: {override.addedItems.length}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Students Card */}
      <Card>
        <CardHeader>
          <CardTitle>Students ({allocation.studentIds.length})</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {allocation.studentIds.map((sid) => (
              <div key={sid} className="rounded-md border p-2 text-sm">
                {studentMap.get(sid) ?? sid}
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      <ConfirmDialog
        open={deactivateOpen}
        onOpenChange={setDeactivateOpen}
        title="Deactivate Allocation"
        description="This will deactivate the allocation. Students will no longer see this assignment. This can be reversed by editing the allocation."
        confirmLabel="Deactivate"
        variant="destructive"
        onConfirm={handleDeactivate}
        loading={loading}
      />
    </div>
  );
}
