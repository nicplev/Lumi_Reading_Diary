"use client";

import { useCallback, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { useForm, type Resolver } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
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
import {
  updateSchoolSchema,
  type UpdateSchoolInput,
} from "@/lib/validations/school";
import type { SchoolDetail } from "@/lib/firestore/schools";

const TIMEZONES = [
  "Pacific/Auckland",
  "Australia/Sydney",
  "Australia/Melbourne",
  "Australia/Brisbane",
  "Australia/Adelaide",
  "Australia/Perth",
];

interface SchoolFormProps {
  school: SchoolDetail;
}

export function SchoolForm({ school }: SchoolFormProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [dragOver, setDragOver] = useState(false);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<UpdateSchoolInput>({
    // Cast: @hookform/resolvers@5.2.2's types are pinned to zod 4.0's internal
    // version marker, but the app resolves zod 4.4.x — a types-only mismatch
    // (runtime is fine). Remove when resolvers/zod versions are realigned.
    resolver: zodResolver(updateSchoolSchema as never) as unknown as Resolver<UpdateSchoolInput>,
    defaultValues: {
      name: school.name,
      contactEmail: school.contactEmail ?? "",
      contactPhone: school.contactPhone ?? "",
      address: school.address ?? "",
      timezone: school.timezone,
      subscriptionPlan: school.subscriptionPlan ?? "",
      displayName: school.displayName ?? "",
      logoUrl: school.logoUrl ?? "",
      primaryColor: school.primaryColor ?? "#6366f1",
      secondaryColor: school.secondaryColor ?? "#f59e0b",
    },
  });

  const watchedLogo = watch("logoUrl");
  const watchedDisplayName = watch("displayName");
  const watchedPrimary = watch("primaryColor");
  const watchedSecondary = watch("secondaryColor");

  const uploadLogo = useCallback(
    async (file: File) => {
      if (file.size > 2 * 1024 * 1024) {
        toast.error("File too large. Maximum size is 2MB");
        return;
      }
      if (
        !["image/png", "image/jpeg", "image/webp", "image/svg+xml"].includes(
          file.type
        )
      ) {
        toast.error("Invalid file type. Use PNG, JPEG, WebP, or SVG");
        return;
      }

      setUploading(true);
      try {
        const formData = new FormData();
        formData.append("file", file);

        const res = await fetch(`/api/schools/${school.id}/logo`, {
          method: "POST",
          body: formData,
        });

        if (!res.ok) {
          const err = await res.json();
          throw new Error(err.error || "Failed to upload logo");
        }

        const { logoUrl } = await res.json();
        setValue("logoUrl", logoUrl);
        toast.success("Logo uploaded");
      } catch (err: unknown) {
        toast.error(err instanceof Error ? err.message : "Upload failed");
      } finally {
        setUploading(false);
      }
    },
    [school.id, setValue]
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setDragOver(false);
      const file = e.dataTransfer.files[0];
      if (file) uploadLogo(file);
    },
    [uploadLogo]
  );

  const onSubmit = async (data: UpdateSchoolInput) => {
    setLoading(true);

    try {
      const res = await fetch(`/api/schools/${school.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to update school");
      }

      toast.success("School updated successfully");
      router.refresh();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Edit School</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="edit-name">School Name</Label>
            <Input id="edit-name" {...register("name")} />
            {errors.name && (
              <p className="text-sm text-destructive">
                {errors.name.message}
              </p>
            )}
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="edit-contactEmail">Contact Email</Label>
              <Input
                id="edit-contactEmail"
                type="email"
                {...register("contactEmail")}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-contactPhone">Contact Phone</Label>
              <Input
                id="edit-contactPhone"
                {...register("contactPhone")}
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="edit-address">Address</Label>
            <Input id="edit-address" {...register("address")} />
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>Timezone</Label>
              <Select
                defaultValue={school.timezone}
                onValueChange={(v) => v && setValue("timezone", v)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {TIMEZONES.map((tz) => (
                    <SelectItem key={tz} value={tz}>
                      {tz}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-subscriptionPlan">Subscription Plan</Label>
              <Input
                id="edit-subscriptionPlan"
                {...register("subscriptionPlan")}
              />
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>School Branding</CardTitle>
          <CardDescription>
            Customize how this school appears in their admin portal
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Logo Upload */}
          <div className="space-y-2">
            <Label>School Logo</Label>
            <div
              className={`relative flex flex-col items-center justify-center rounded-lg border-2 border-dashed p-6 transition-colors ${
                dragOver
                  ? "border-primary bg-primary/5"
                  : "border-muted-foreground/25 hover:border-muted-foreground/50"
              }`}
              onDragOver={(e) => {
                e.preventDefault();
                setDragOver(true);
              }}
              onDragLeave={() => setDragOver(false)}
              onDrop={handleDrop}
            >
              {watchedLogo ? (
                <img
                  src={watchedLogo}
                  alt="School logo"
                  className="mb-3 h-20 w-20 rounded-lg object-contain"
                />
              ) : (
                <div className="mb-3 flex h-20 w-20 items-center justify-center rounded-lg bg-muted">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="32"
                    height="32"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    className="text-muted-foreground"
                  >
                    <rect width="18" height="18" x="3" y="3" rx="2" ry="2" />
                    <circle cx="9" cy="9" r="2" />
                    <path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" />
                  </svg>
                </div>
              )}
              <p className="text-sm text-muted-foreground">
                {uploading
                  ? "Uploading..."
                  : "Drag & drop an image, or click to browse"}
              </p>
              <p className="text-xs text-muted-foreground">
                PNG, JPEG, WebP, or SVG. Max 2MB.
              </p>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/png,image/jpeg,image/webp,image/svg+xml"
                className="absolute inset-0 cursor-pointer opacity-0"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) uploadLogo(file);
                }}
                disabled={uploading}
              />
            </div>
          </div>

          {/* Display Name */}
          <div className="space-y-2">
            <Label htmlFor="edit-displayName">Display Name</Label>
            <Input
              id="edit-displayName"
              placeholder="e.g. St Mary's Primary"
              {...register("displayName")}
            />
            <p className="text-xs text-muted-foreground">
              Shown in the school&apos;s admin portal header. Falls back to the
              school name if empty.
            </p>
          </div>

          {/* Color Pickers */}
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="edit-primaryColor">Primary Color</Label>
              <div className="flex items-center gap-2">
                <input
                  type="color"
                  value={watchedPrimary || "#6366f1"}
                  onChange={(e) => setValue("primaryColor", e.target.value)}
                  className="h-10 w-10 cursor-pointer rounded border border-input p-0.5"
                />
                <Input
                  id="edit-primaryColor"
                  placeholder="#6366f1"
                  {...register("primaryColor")}
                  className="font-mono"
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-secondaryColor">Secondary Color</Label>
              <div className="flex items-center gap-2">
                <input
                  type="color"
                  value={watchedSecondary || "#f59e0b"}
                  onChange={(e) => setValue("secondaryColor", e.target.value)}
                  className="h-10 w-10 cursor-pointer rounded border border-input p-0.5"
                />
                <Input
                  id="edit-secondaryColor"
                  placeholder="#f59e0b"
                  {...register("secondaryColor")}
                  className="font-mono"
                />
              </div>
            </div>
          </div>

          {/* Live Preview */}
          <div className="space-y-2">
            <Label>Preview</Label>
            <div className="overflow-hidden rounded-lg border">
              <div className="flex">
                {/* Mini sidebar */}
                <div
                  className="flex w-48 flex-col gap-3 p-4"
                  style={{ backgroundColor: watchedPrimary || "#6366f1" }}
                >
                  <div className="flex items-center gap-2">
                    {watchedLogo ? (
                      <img
                        src={watchedLogo}
                        alt=""
                        className="h-8 w-8 rounded object-contain"
                      />
                    ) : (
                      <div className="flex h-8 w-8 items-center justify-center rounded bg-white/20 text-xs font-bold text-white">
                        {(
                          watchedDisplayName ||
                          school.name ||
                          "S"
                        ).charAt(0)}
                      </div>
                    )}
                    <span className="truncate text-sm font-semibold text-white">
                      {watchedDisplayName || school.name}
                    </span>
                  </div>
                  <div className="space-y-1.5">
                    <div
                      className="h-2 w-full rounded"
                      style={{
                        backgroundColor: watchedSecondary || "#f59e0b",
                      }}
                    />
                    <div className="h-2 w-3/4 rounded bg-white/20" />
                    <div className="h-2 w-5/6 rounded bg-white/20" />
                    <div className="h-2 w-2/3 rounded bg-white/20" />
                  </div>
                </div>
                {/* Content area */}
                <div className="flex-1 bg-muted/30 p-4">
                  <div className="space-y-2">
                    <div
                      className="h-3 w-1/3 rounded"
                      style={{
                        backgroundColor: watchedPrimary || "#6366f1",
                        opacity: 0.7,
                      }}
                    />
                    <div className="h-2 w-full rounded bg-muted" />
                    <div className="h-2 w-5/6 rounded bg-muted" />
                    <div className="h-2 w-4/6 rounded bg-muted" />
                    <div className="mt-3 flex gap-2">
                      <div
                        className="h-6 w-16 rounded"
                        style={{
                          backgroundColor: watchedPrimary || "#6366f1",
                        }}
                      />
                      <div
                        className="h-6 w-16 rounded border"
                        style={{
                          borderColor: watchedSecondary || "#f59e0b",
                        }}
                      />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <div>
        <Button type="submit" disabled={loading || uploading}>
          {loading ? "Saving..." : "Save Changes"}
        </Button>
      </div>
    </form>
  );
}
