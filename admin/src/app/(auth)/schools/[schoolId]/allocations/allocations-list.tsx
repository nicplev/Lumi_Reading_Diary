"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import { Plus } from "lucide-react";
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
import { formatDate } from "@/lib/utils";
import type { AllocationListItem } from "@/lib/firestore/allocations";
import type { ClassListItem } from "@/lib/firestore/classes";
import type { SchoolUserListItem } from "@/lib/firestore/school-users";
import type { StudentListItem } from "@/lib/firestore/students";

interface AllocationsListProps {
  schoolId: string;
  allocations: AllocationListItem[];
  classes: ClassListItem[];
  users: SchoolUserListItem[];
  students: StudentListItem[];
}

export function AllocationsList({
  schoolId,
  allocations,
  classes,
  users,
  students,
}: AllocationsListProps) {
  const router = useRouter();
  const [createOpen, setCreateOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [filterClassId, setFilterClassId] = useState<string>("all");

  // Create form state
  const [classId, setClassId] = useState("");
  const [teacherId, setTeacherId] = useState("");
  const [type, setType] = useState<string>("");
  const [cadence, setCadence] = useState<string>("");
  const [targetMinutes, setTargetMinutes] = useState("15");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [levelStart, setLevelStart] = useState("");
  const [levelEnd, setLevelEnd] = useState("");
  const [bookTitles, setBookTitles] = useState("");
  const [isRecurring, setIsRecurring] = useState(false);
  const [templateName, setTemplateName] = useState("");
  const [selectedStudentIds, setSelectedStudentIds] = useState<string[]>([]);

  const classMap = new Map(classes.map((c) => [c.id, c.name]));
  const userMap = new Map(users.map((u) => [u.id, u.fullName]));

  const filteredAllocations =
    filterClassId && filterClassId !== "all"
      ? allocations.filter((a) => a.classId === filterClassId)
      : allocations;

  const classStudents = classId
    ? students.filter((s) => s.classId === classId && s.isActive)
    : [];

  const toggleStudent = (studentId: string) => {
    setSelectedStudentIds((prev) =>
      prev.includes(studentId)
        ? prev.filter((id) => id !== studentId)
        : [...prev, studentId]
    );
  };

  const selectAllStudents = () => {
    setSelectedStudentIds(classStudents.map((s) => s.id));
  };

  const resetForm = () => {
    setClassId("");
    setTeacherId("");
    setType("");
    setCadence("");
    setTargetMinutes("15");
    setStartDate("");
    setEndDate("");
    setLevelStart("");
    setLevelEnd("");
    setBookTitles("");
    setIsRecurring(false);
    setTemplateName("");
    setSelectedStudentIds([]);
  };

  const handleCreate = async () => {
    if (!classId || !teacherId || !type || !cadence || !startDate || !endDate) {
      toast.error("Please fill in all required fields");
      return;
    }
    if (selectedStudentIds.length === 0) {
      toast.error("At least one student is required");
      return;
    }
    setLoading(true);
    try {
      const body: Record<string, unknown> = {
        classId,
        teacherId,
        type,
        cadence,
        targetMinutes: parseInt(targetMinutes, 10),
        startDate,
        endDate,
        studentIds: selectedStudentIds,
      };
      if (type === "byLevel") {
        if (levelStart) body.levelStart = levelStart;
        if (levelEnd) body.levelEnd = levelEnd;
      }
      if (type === "byTitle" && bookTitles) {
        body.bookTitles = bookTitles
          .split(",")
          .map((t) => t.trim())
          .filter(Boolean);
      }
      if (isRecurring) body.isRecurring = true;
      if (templateName) body.templateName = templateName;

      const res = await fetch(`/api/schools/${schoolId}/allocations`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to create allocation");
      }
      setCreateOpen(false);
      resetForm();
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<AllocationListItem, unknown>[] = [
    {
      accessorKey: "classId",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Class" />
      ),
      cell: ({ row }) => classMap.get(row.original.classId) ?? "\u2014",
    },
    {
      accessorKey: "teacherId",
      header: "Teacher",
      cell: ({ row }) => userMap.get(row.original.teacherId) ?? "\u2014",
    },
    {
      accessorKey: "type",
      header: "Type",
      cell: ({ row }) => <StatusBadge status={row.original.type} />,
    },
    {
      accessorKey: "cadence",
      header: "Cadence",
      cell: ({ row }) => (
        <span className="capitalize">{row.original.cadence}</span>
      ),
    },
    {
      accessorKey: "targetMinutes",
      header: "Target",
      cell: ({ row }) => `${row.original.targetMinutes} min`,
    },
    {
      accessorKey: "studentCount",
      header: "Students",
    },
    {
      id: "dates",
      header: "Dates",
      cell: ({ row }) =>
        `${formatDate(row.original.startDate)} – ${formatDate(row.original.endDate ?? "")}`,
    },
    {
      accessorKey: "isActive",
      header: "Status",
      cell: ({ row }) => (
        <StatusBadge
          status={row.original.isActive ? "active" : "completed"}
        />
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Allocations</h3>
        <Dialog
          open={createOpen}
          onOpenChange={(open) => {
            setCreateOpen(open);
            if (!open) resetForm();
          }}
        >
          <DialogTrigger render={<Button />}>
            <Plus className="mr-2 h-4 w-4" />
            Create Allocation
          </DialogTrigger>
          <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
            <DialogHeader>
              <DialogTitle>Create Allocation</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div className="space-y-2">
                <Label>Class *</Label>
                <Select
                  value={classId}
                  onValueChange={(v) => {
                    if (v) {
                      setClassId(v);
                      setSelectedStudentIds([]);
                    }
                  }}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select class" />
                  </SelectTrigger>
                  <SelectContent>
                    {classes.map((c) => (
                      <SelectItem key={c.id} value={c.id}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
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
                    {users.map((u) => (
                      <SelectItem key={u.id} value={u.id}>
                        {u.fullName}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Type *</Label>
                <Select value={type} onValueChange={(v) => v && setType(v)}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select type" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="byLevel">By Level</SelectItem>
                    <SelectItem value="byTitle">By Title</SelectItem>
                    <SelectItem value="freeChoice">Free Choice</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              {type === "byLevel" && (
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Level Start</Label>
                    <Input
                      value={levelStart}
                      onChange={(e) => setLevelStart(e.target.value)}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Level End</Label>
                    <Input
                      value={levelEnd}
                      onChange={(e) => setLevelEnd(e.target.value)}
                    />
                  </div>
                </div>
              )}
              {type === "byTitle" && (
                <div className="space-y-2">
                  <Label>Book Titles (comma-separated)</Label>
                  <Input
                    value={bookTitles}
                    onChange={(e) => setBookTitles(e.target.value)}
                    placeholder="e.g. The Cat in the Hat, Green Eggs and Ham"
                  />
                </div>
              )}
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Cadence *</Label>
                  <Select
                    value={cadence}
                    onValueChange={(v) => v && setCadence(v)}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Select cadence" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="daily">Daily</SelectItem>
                      <SelectItem value="weekly">Weekly</SelectItem>
                      <SelectItem value="fortnightly">Fortnightly</SelectItem>
                      <SelectItem value="custom">Custom</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Target Minutes *</Label>
                  <Input
                    type="number"
                    value={targetMinutes}
                    onChange={(e) => setTargetMinutes(e.target.value)}
                    min={1}
                  />
                </div>
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Start Date *</Label>
                  <Input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>End Date *</Label>
                  <Input
                    type="date"
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                  />
                </div>
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Template Name</Label>
                  <Input
                    value={templateName}
                    onChange={(e) => setTemplateName(e.target.value)}
                    placeholder="Optional"
                  />
                </div>
                <div className="flex items-center gap-2 pt-7">
                  <Checkbox
                    id="isRecurring"
                    checked={isRecurring}
                    onCheckedChange={(checked) =>
                      setIsRecurring(checked === true)
                    }
                  />
                  <Label htmlFor="isRecurring">Recurring</Label>
                </div>
              </div>
              {classId && (
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <Label>
                      Students * ({selectedStudentIds.length} selected)
                    </Label>
                    <Button
                      variant="ghost"
                      size="sm"
                      type="button"
                      onClick={selectAllStudents}
                    >
                      Select All
                    </Button>
                  </div>
                  <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border p-2">
                    {classStudents.length === 0 ? (
                      <p className="text-sm text-muted-foreground">
                        No active students in this class
                      </p>
                    ) : (
                      classStudents.map((s) => (
                        <div key={s.id} className="flex items-center gap-2">
                          <Checkbox
                            id={`student-${s.id}`}
                            checked={selectedStudentIds.includes(s.id)}
                            onCheckedChange={() => toggleStudent(s.id)}
                          />
                          <Label
                            htmlFor={`student-${s.id}`}
                            className="text-sm font-normal"
                          >
                            {s.firstName} {s.lastName}
                          </Label>
                        </div>
                      ))
                    )}
                  </div>
                </div>
              )}
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

      <div className="flex items-center gap-4">
        <Select
          value={filterClassId}
          onValueChange={(v) => v && setFilterClassId(v)}
        >
          <SelectTrigger className="w-[200px]">
            <SelectValue placeholder="All classes" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All classes</SelectItem>
            {classes.map((c) => (
              <SelectItem key={c.id} value={c.id}>
                {c.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={filteredAllocations}
        searchKey="classId"
        searchPlaceholder="Search allocations..."
        onRowClick={(row) =>
          router.push(`/schools/${schoolId}/allocations/${row.id}`)
        }
      />
    </div>
  );
}
