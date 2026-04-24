"use client";

import { useState } from "react";
import { toast } from "sonner";
import { CheckCircle, AlertTriangle, Loader2 } from "lucide-react";
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
import type { SchoolListItem } from "@/lib/firestore/schools";

interface OffboardWizardProps {
  schools: SchoolListItem[];
}

interface PreviewData {
  schoolName: string;
  users: number;
  students: number;
  parents: number;
  classes: number;
  allocations: number;
  books: number;
  readingLogs: number;
}

const STEPS = [
  { key: "users", label: "Users" },
  { key: "students", label: "Students" },
  { key: "parents", label: "Parents" },
  { key: "classes", label: "Classes" },
  { key: "allocations", label: "Allocations" },
  { key: "school", label: "School" },
] as const;

export function OffboardWizard({ schools }: OffboardWizardProps) {
  const [schoolId, setSchoolId] = useState("");
  const [preview, setPreview] = useState<PreviewData | null>(null);
  const [loading, setLoading] = useState(false);
  const [confirmName, setConfirmName] = useState("");
  const [executing, setExecuting] = useState(false);
  const [completedSteps, setCompletedSteps] = useState<string[]>([]);
  const [currentStep, setCurrentStep] = useState<string | null>(null);

  const activeSchools = schools.filter((s) => s.isActive);

  const handlePreview = async () => {
    if (!schoolId) return;
    setLoading(true);
    try {
      const res = await fetch("/api/offboard", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "preview", schoolId }),
      });
      if (!res.ok) throw new Error("Failed to load preview");
      const data = await res.json();
      setPreview(data);
      setCompletedSteps([]);
      setConfirmName("");
    } catch {
      toast.error("Failed to load school preview");
    } finally {
      setLoading(false);
    }
  };

  const handleExecute = async () => {
    if (!preview || confirmName !== preview.schoolName) return;
    setExecuting(true);

    for (const step of STEPS) {
      setCurrentStep(step.key);
      try {
        const res = await fetch("/api/offboard", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action: "execute",
            schoolId,
            step: step.key,
          }),
        });
        if (!res.ok) throw new Error(`Failed at step: ${step.label}`);
        const result = await res.json();
        setCompletedSteps((prev) => [...prev, step.key]);
        toast.success(`${step.label}: ${result.affected} items deactivated`);
      } catch (err) {
        toast.error(
          err instanceof Error ? err.message : `Failed at ${step.label}`
        );
        setCurrentStep(null);
        setExecuting(false);
        return;
      }
    }

    setCurrentStep(null);
    setExecuting(false);
    toast.success("School offboarding complete");
  };

  const allDone = completedSteps.length === STEPS.length;

  return (
    <div className="space-y-6">
      {/* Step 1: Select School */}
      <Card>
        <CardHeader>
          <CardTitle>1. Select School</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-end gap-4">
            <div className="flex-1 space-y-2">
              <Label>School</Label>
              <Select
                value={schoolId}
                onValueChange={(v) => {
                  if (v) {
                    setSchoolId(v);
                    setPreview(null);
                    setCompletedSteps([]);
                  }
                }}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select a school to offboard" />
                </SelectTrigger>
                <SelectContent>
                  {activeSchools.map((s) => (
                    <SelectItem key={s.id} value={s.id}>
                      {s.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button
              onClick={handlePreview}
              disabled={!schoolId || loading}
            >
              {loading ? "Loading..." : "Preview"}
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Step 2: Preview */}
      {preview && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-amber-500" />
              2. Review Impact — {preview.schoolName}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="mb-4 text-sm text-muted-foreground">
              The following data will be soft-deactivated (isActive set to
              false):
            </p>
            <div className="grid gap-2 sm:grid-cols-3">
              {[
                { label: "Users", count: preview.users },
                { label: "Students", count: preview.students },
                { label: "Parents", count: preview.parents },
                { label: "Classes", count: preview.classes },
                { label: "Allocations", count: preview.allocations },
                { label: "Books", count: preview.books },
                { label: "Reading Logs", count: preview.readingLogs },
              ].map((item) => (
                <div
                  key={item.label}
                  className="rounded-md border p-3 text-center"
                >
                  <p className="text-2xl font-bold">{item.count}</p>
                  <p className="text-sm text-muted-foreground">
                    {item.label}
                  </p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Step 3: Confirm & Execute */}
      {preview && !allDone && (
        <Card>
          <CardHeader>
            <CardTitle>3. Confirm & Execute</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Type <strong>{preview.schoolName}</strong> to confirm
              deactivation.
            </p>
            <Input
              value={confirmName}
              onChange={(e) => setConfirmName(e.target.value)}
              placeholder="Type school name..."
              disabled={executing}
            />
            <Button
              variant="destructive"
              onClick={handleExecute}
              disabled={
                confirmName !== preview.schoolName || executing
              }
            >
              {executing ? "Executing..." : "Deactivate School"}
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Step 4: Progress */}
      {(executing || completedSteps.length > 0) && (
        <Card>
          <CardHeader>
            <CardTitle>4. Progress</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {STEPS.map((step) => {
                const done = completedSteps.includes(step.key);
                const active = currentStep === step.key;
                return (
                  <div
                    key={step.key}
                    className="flex items-center gap-3 rounded-md border p-3"
                  >
                    {done ? (
                      <CheckCircle className="h-5 w-5 text-green-500" />
                    ) : active ? (
                      <Loader2 className="h-5 w-5 animate-spin text-blue-500" />
                    ) : (
                      <div className="h-5 w-5 rounded-full border-2" />
                    )}
                    <span
                      className={
                        done
                          ? "text-green-700 dark:text-green-400"
                          : active
                            ? "font-medium"
                            : "text-muted-foreground"
                      }
                    >
                      {step.label}
                    </span>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
