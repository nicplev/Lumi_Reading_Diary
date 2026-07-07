"use client";

import { useState, type ChangeEvent } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const EMPTY = {
  schoolName: "",
  contactPerson: "",
  contactEmail: "",
  contactPhone: "",
  estimatedStudentCount: "",
  estimatedTeacherCount: "",
  referralSource: "",
  status: "demo",
  notes: "",
};

export function NewRequestDialog() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ ...EMPTY });

  const set =
    (k: keyof typeof EMPTY) =>
    (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
      setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async () => {
    if (!form.schoolName.trim() || !form.contactEmail.trim()) {
      toast.error("School name and contact email are required");
      return;
    }
    setLoading(true);
    try {
      const res = await fetch("/api/onboarding", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          schoolName: form.schoolName.trim(),
          contactEmail: form.contactEmail.trim(),
          contactPerson: form.contactPerson.trim() || undefined,
          contactPhone: form.contactPhone.trim() || undefined,
          estimatedStudentCount: Number(form.estimatedStudentCount) || 0,
          estimatedTeacherCount: Number(form.estimatedTeacherCount) || 0,
          referralSource: form.referralSource.trim() || undefined,
          status: form.status,
          notes: form.notes.trim() || undefined,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Failed to create request");
      toast.success(`Added ${form.schoolName.trim()} to the pipeline`);
      setForm({ ...EMPTY });
      setOpen(false);
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to create request");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button />}>
        <Plus className="mr-2 h-4 w-4" />
        New Request
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New onboarding request</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 pt-2">
          <div className="space-y-2">
            <Label>School name *</Label>
            <Input value={form.schoolName} onChange={set("schoolName")} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Contact person</Label>
              <Input
                value={form.contactPerson}
                onChange={set("contactPerson")}
              />
            </div>
            <div className="space-y-2">
              <Label>Contact email *</Label>
              <Input
                type="email"
                value={form.contactEmail}
                onChange={set("contactEmail")}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Contact phone</Label>
              <Input value={form.contactPhone} onChange={set("contactPhone")} />
            </div>
            <div className="space-y-2">
              <Label>Referral source</Label>
              <Input
                value={form.referralSource}
                onChange={set("referralSource")}
              />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-2">
              <Label>Est. students</Label>
              <Input
                type="number"
                min={0}
                value={form.estimatedStudentCount}
                onChange={set("estimatedStudentCount")}
              />
            </div>
            <div className="space-y-2">
              <Label>Est. teachers</Label>
              <Input
                type="number"
                min={0}
                value={form.estimatedTeacherCount}
                onChange={set("estimatedTeacherCount")}
              />
            </div>
            <div className="space-y-2">
              <Label>Stage</Label>
              <Select
                value={form.status}
                onValueChange={(v) => v && setForm((f) => ({ ...f, status: v }))}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="demo">Demo</SelectItem>
                  <SelectItem value="interested">Interested</SelectItem>
                  <SelectItem value="registered">Registered</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-2">
            <Label>Notes</Label>
            <Textarea
              rows={3}
              value={form.notes}
              onChange={set("notes")}
              placeholder="Where the lead came from, what landed, next step…"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={loading}>
            {loading ? "Adding…" : "Add request"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
