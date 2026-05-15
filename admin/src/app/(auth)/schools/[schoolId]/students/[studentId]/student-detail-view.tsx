"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { BookOpen, Clock, Flame, Trophy } from "lucide-react";
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
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { StatCard } from "@/components/cards/stat-card";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import type { StudentDetail } from "@/lib/firestore/students";
import { formatDate } from "@/lib/utils";
import type { LinkCodeListItem } from "@/lib/firestore/link-codes";
import type { ClassListItem } from "@/lib/firestore/classes";

interface StudentDetailViewProps {
  student: StudentDetail;
  linkCodes: LinkCodeListItem[];
  classes: ClassListItem[];
  schoolId: string;
}

export function StudentDetailView({
  student,
  linkCodes,
  classes,
  schoolId,
}: StudentDetailViewProps) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [revokeCodeId, setRevokeCodeId] = useState<string | null>(null);

  // Edit form
  const [firstName, setFirstName] = useState(student.firstName);
  const [lastName, setLastName] = useState(student.lastName);
  const [studentIdField, setStudentIdField] = useState(student.studentId ?? "");
  const [classId, setClassId] = useState(student.classId);

  const classMap = new Map(classes.map((c) => [c.id, c.name]));

  const handleSave = async () => {
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/students/${student.id}`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            firstName,
            lastName,
            studentId: studentIdField || undefined,
            classId,
          }),
        }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to update student");
      }
      toast.success("Student updated successfully");
      setEditing(false);
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleGenerateCode = async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/link-codes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          studentId: student.id,
          schoolId,
        }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to generate code");
      }
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleRevokeCode = async () => {
    if (!revokeCodeId) return;
    setLoading(true);
    try {
      const res = await fetch(`/api/link-codes/${revokeCodeId}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to revoke code");
      }
      setRevokeCodeId(null);
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      {/* Stats Grid */}
      {student.stats && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            title="Minutes Read"
            value={student.stats.totalMinutesRead}
            icon={Clock}
          />
          <StatCard
            title="Books Read"
            value={student.stats.totalBooksRead}
            icon={BookOpen}
          />
          <StatCard
            title="Current Streak"
            value={`${student.stats.currentStreak} days`}
            icon={Flame}
          />
          <StatCard
            title="Longest Streak"
            value={`${student.stats.longestStreak} days`}
            icon={Trophy}
          />
        </div>
      )}

      {/* Student Info Card */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Student Information</CardTitle>
          {!editing && (
            <Button variant="outline" onClick={() => setEditing(true)}>
              Edit
            </Button>
          )}
        </CardHeader>
        <CardContent>
          {editing ? (
            <div className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>First Name</Label>
                  <Input
                    value={firstName}
                    onChange={(e) => setFirstName(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Last Name</Label>
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
                  />
                </div>
                <div className="space-y-2">
                  <Label>Class</Label>
                  <Select
                    value={classId}
                    onValueChange={(v) => v && setClassId(v)}
                  >
                    <SelectTrigger>
                      <SelectValue />
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
              </div>
              <div className="flex gap-2 pt-2">
                <Button onClick={handleSave} disabled={loading}>
                  {loading ? "Saving..." : "Save Changes"}
                </Button>
                <Button
                  variant="outline"
                  onClick={() => {
                    setEditing(false);
                    setFirstName(student.firstName);
                    setLastName(student.lastName);
                    setStudentIdField(student.studentId ?? "");
                    setClassId(student.classId);
                  }}
                >
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <p className="text-sm text-muted-foreground">Status</p>
                <StatusBadge
                  status={student.isActive ? "active" : "disabled"}
                />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Class</p>
                <p className="font-medium">
                  {classMap.get(student.classId) ?? "\u2014"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Reading Level</p>
                <p className="font-medium">
                  {student.currentReadingLevel ?? "\u2014"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">
                  Level Last Updated
                </p>
                <p className="font-medium">
                  {formatDate(student.readingLevelUpdatedAt)}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Parent Linked</p>
                <StatusBadge
                  status={student.parentLinked ? "linked" : "unlinked"}
                />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Enrolled</p>
                <p className="font-medium">
                  {formatDate(student.createdAt)}
                </p>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Parents & Link Codes */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Parent Link Codes</CardTitle>
          <Button variant="outline" onClick={handleGenerateCode} disabled={loading}>
            Generate Code
          </Button>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            <p className="text-sm text-muted-foreground">
              Parents: {student.parentIds.length > 0 ? student.parentIds.length : "None linked"}
            </p>
          </div>
          {linkCodes.length > 0 ? (
            <div className="mt-4 space-y-2">
              {linkCodes.map((code) => (
                <div
                  key={code.id}
                  className="flex items-center justify-between rounded-md border p-3"
                >
                  <div className="flex items-center gap-3">
                    <code className="rounded bg-muted px-2 py-1 font-mono text-sm">
                      {code.code}
                    </code>
                    <StatusBadge status={code.status} />
                    {code.expiresAt && (
                      <span className="text-sm text-muted-foreground">
                        Expires: {formatDate(code.expiresAt)}
                      </span>
                    )}
                  </div>
                  {code.status === "active" && (
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-destructive"
                      onClick={() => setRevokeCodeId(code.id)}
                    >
                      Revoke
                    </Button>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <p className="mt-4 text-sm text-muted-foreground">
              No link codes generated yet.
            </p>
          )}
        </CardContent>
      </Card>

      <ConfirmDialog
        open={!!revokeCodeId}
        onOpenChange={(open) => {
          if (!open) setRevokeCodeId(null);
        }}
        title="Revoke Link Code"
        description="This will invalidate the link code. Parents who haven't used it yet will no longer be able to link their account."
        confirmLabel="Revoke"
        variant="destructive"
        onConfirm={handleRevokeCode}
        loading={loading}
      />
    </>
  );
}
