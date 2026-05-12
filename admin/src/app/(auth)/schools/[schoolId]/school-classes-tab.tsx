"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
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
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import type { ClassListItem } from "@/lib/firestore/classes";
import type { SchoolUserListItem } from "@/lib/firestore/school-users";

interface SchoolClassesTabProps {
  schoolId: string;
  classes: ClassListItem[];
  users: SchoolUserListItem[];
}

export function SchoolClassesTab({
  schoolId,
  classes,
  users,
}: SchoolClassesTabProps) {
  const router = useRouter();
  const [createOpen, setCreateOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [deactivateClass, setDeactivateClass] =
    useState<ClassListItem | null>(null);

  // Create form state
  const [name, setName] = useState("");
  const [yearLevel, setYearLevel] = useState("");
  const [room, setRoom] = useState("");
  const [teacherId, setTeacherId] = useState("");
  const [minutesTarget, setMinutesTarget] = useState("");
  const [description, setDescription] = useState("");

  const teachers = users.filter(
    (u) => u.role === "teacher" || u.role === "schoolAdmin"
  );
  const teacherMap = new Map(teachers.map((t) => [t.id, t.fullName]));

  const handleCreate = async () => {
    if (!name || !teacherId) {
      setError("Name and teacher are required");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const body: Record<string, unknown> = { name, teacherId };
      if (yearLevel) body.yearLevel = yearLevel;
      if (room) body.room = room;
      if (minutesTarget) body.defaultMinutesTarget = parseInt(minutesTarget, 10);
      if (description) body.description = description;

      const res = await fetch(`/api/schools/${schoolId}/classes`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to create class");
      }
      setCreateOpen(false);
      setName("");
      setYearLevel("");
      setRoom("");
      setTeacherId("");
      setMinutesTarget("");
      setDescription("");
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleDeactivate = async () => {
    if (!deactivateClass) return;
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/classes/${deactivateClass.id}`,
        { method: "DELETE" }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to deactivate class");
      }
      setDeactivateClass(null);
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<ClassListItem, unknown>[] = [
    {
      accessorKey: "name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Name" />
      ),
    },
    {
      accessorKey: "yearLevel",
      header: "Year Level",
      cell: ({ row }) => row.original.yearLevel ?? "\u2014",
    },
    {
      accessorKey: "room",
      header: "Room",
      cell: ({ row }) => row.original.room ?? "\u2014",
    },
    {
      accessorKey: "teacherId",
      header: "Teacher",
      cell: ({ row }) =>
        teacherMap.get(row.original.teacherId) ?? "\u2014",
    },
    {
      accessorKey: "studentCount",
      header: "Students",
      cell: ({ row }) => row.original.studentCount,
    },
    {
      accessorKey: "isActive",
      header: "Status",
      cell: ({ row }) => (
        <StatusBadge
          status={row.original.isActive ? "active" : "disabled"}
        />
      ),
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => {
        const cls = row.original;
        return cls.isActive ? (
          <Button
            variant="ghost"
            size="sm"
            className="text-destructive"
            onClick={(e) => {
              e.stopPropagation();
              setDeactivateClass(cls);
            }}
          >
            Deactivate
          </Button>
        ) : null;
      },
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Classes</h3>
        <Dialog open={createOpen} onOpenChange={setCreateOpen}>
          <DialogTrigger render={<Button />}>
            <Plus className="mr-2 h-4 w-4" />
            Add Class
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Class</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              {error && (
                <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">
                  {error}
                </div>
              )}
              <div className="space-y-2">
                <Label>Class Name *</Label>
                <Input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Year Level</Label>
                  <Input
                    value={yearLevel}
                    onChange={(e) => setYearLevel(e.target.value)}
                    placeholder="Optional"
                  />
                </div>
                <div className="space-y-2">
                  <Label>Room</Label>
                  <Input
                    value={room}
                    onChange={(e) => setRoom(e.target.value)}
                    placeholder="Optional"
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Teacher *</Label>
                <Select
                  value={teacherId}
                  onValueChange={(v) => v && setTeacherId(v)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select teacher" />
                  </SelectTrigger>
                  <SelectContent>
                    {teachers.map((t) => (
                      <SelectItem key={t.id} value={t.id}>
                        {t.fullName}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Minutes Target</Label>
                  <Input
                    type="number"
                    value={minutesTarget}
                    onChange={(e) => setMinutesTarget(e.target.value)}
                    placeholder="15"
                  />
                </div>
                <div className="space-y-2">
                  <Label>Description</Label>
                  <Input
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    placeholder="Optional"
                  />
                </div>
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <Button
                  variant="outline"
                  onClick={() => setCreateOpen(false)}
                >
                  Cancel
                </Button>
                <Button onClick={handleCreate} disabled={loading}>
                  {loading ? "Creating..." : "Create"}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </div>

      <DataTable
        columns={columns}
        data={classes}
        searchKey="name"
        searchPlaceholder="Search classes..."
      />

      <ConfirmDialog
        open={!!deactivateClass}
        onOpenChange={(open) => {
          if (!open) setDeactivateClass(null);
        }}
        title="Deactivate Class"
        description={`Deactivate "${deactivateClass?.name}"? This will mark the class as inactive.`}
        confirmLabel="Deactivate"
        variant="destructive"
        onConfirm={handleDeactivate}
        loading={loading}
      />
    </div>
  );
}
