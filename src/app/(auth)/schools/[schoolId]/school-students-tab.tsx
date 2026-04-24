"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
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
import type { StudentListItem } from "@/lib/firestore/students";
import type { ClassListItem } from "@/lib/firestore/classes";

interface SchoolStudentsTabProps {
  schoolId: string;
  students: StudentListItem[];
  classes: ClassListItem[];
}

export function SchoolStudentsTab({
  schoolId,
  students,
  classes,
}: SchoolStudentsTabProps) {
  const router = useRouter();
  const [createOpen, setCreateOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [filterClassId, setFilterClassId] = useState<string>("all");

  // Create form state
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [studentIdField, setStudentIdField] = useState("");
  const [classId, setClassId] = useState("");
  const [readingLevel, setReadingLevel] = useState("");

  const classMap = new Map(classes.map((c) => [c.id, c.name]));

  const filteredStudents =
    filterClassId && filterClassId !== "all"
      ? students.filter((s) => s.classId === filterClassId)
      : students;

  const handleCreate = async () => {
    if (!firstName || !lastName || !classId) {
      toast.error("First name, last name, and class are required");
      return;
    }
    setLoading(true);
    try {
      const body: Record<string, unknown> = {
        firstName,
        lastName,
        classId,
      };
      if (studentIdField) body.studentId = studentIdField;
      if (readingLevel) body.currentReadingLevel = readingLevel;

      const res = await fetch(`/api/schools/${schoolId}/students`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to create student");
      }
      setCreateOpen(false);
      setFirstName("");
      setLastName("");
      setStudentIdField("");
      setClassId("");
      setReadingLevel("");
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<StudentListItem, unknown>[] = [
    {
      accessorKey: "firstName",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Name" />
      ),
      cell: ({ row }) =>
        `${row.original.firstName} ${row.original.lastName}`,
    },
    {
      accessorKey: "classId",
      header: "Class",
      cell: ({ row }) => classMap.get(row.original.classId) ?? "\u2014",
    },
    {
      accessorKey: "currentReadingLevel",
      header: "Reading Level",
      cell: ({ row }) => row.original.currentReadingLevel ?? "\u2014",
    },
    {
      accessorKey: "parentLinked",
      header: "Parent",
      cell: ({ row }) => (
        <StatusBadge
          status={row.original.parentLinked ? "linked" : "unlinked"}
        />
      ),
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
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Students</h3>
        <Dialog open={createOpen} onOpenChange={setCreateOpen}>
          <DialogTrigger render={<Button />}>
            <Plus className="mr-2 h-4 w-4" />
            Add Student
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Student</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>First Name *</Label>
                  <Input
                    value={firstName}
                    onChange={(e) => setFirstName(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Last Name *</Label>
                  <Input
                    value={lastName}
                    onChange={(e) => setLastName(e.target.value)}
                  />
                </div>
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Student ID</Label>
                  <Input
                    value={studentIdField}
                    onChange={(e) => setStudentIdField(e.target.value)}
                    placeholder="Optional"
                  />
                </div>
                <div className="space-y-2">
                  <Label>Reading Level</Label>
                  <Input
                    value={readingLevel}
                    onChange={(e) => setReadingLevel(e.target.value)}
                    placeholder="Optional"
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Class *</Label>
                <Select
                  value={classId}
                  onValueChange={(v) => v && setClassId(v)}
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
        data={filteredStudents}
        searchKey="firstName"
        searchPlaceholder="Search students..."
        onRowClick={(row) =>
          router.push(`/schools/${schoolId}/students/${row.id}`)
        }
      />
    </div>
  );
}
