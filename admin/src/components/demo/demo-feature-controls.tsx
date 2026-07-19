"use client";

import { useState } from "react";
import {
  LoaderCircle,
  MessageCircleMore,
  MessageSquareText,
  Mic2,
  Plus,
  Rabbit,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import type {
  DemoCommentPreset,
  DemoControlPatch,
  DemoControlValues,
} from "@/lib/demo/control-model";

interface DemoFeatureControlsProps {
  initialControls: DemoControlValues;
  active: boolean;
  patchEndpoint: string;
}

interface ControlResponse {
  success?: boolean;
  error?: string;
  controls?: DemoControlValues;
}

type BooleanControlKey =
  | "audioRecordingEnabled"
  | "parentCommentsEnabled"
  | "freeTextCommentsEnabled"
  | "messagingEnabled"
  | "quickLoggingEnabled";

export function DemoFeatureControls({
  initialControls,
  active,
  patchEndpoint,
}: DemoFeatureControlsProps) {
  const [controls, setControls] = useState(initialControls);
  const [draftPresets, setDraftPresets] = useState(initialControls.commentPresets);
  const [newCategory, setNewCategory] = useState("");
  const [newChips, setNewChips] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const [presetsDirty, setPresetsDirty] = useState(false);

  const save = async (patch: DemoControlPatch, key: string) => {
    setSaving(key);
    try {
      const response = await fetch(patchEndpoint, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(patch),
      });
      const data = (await response.json()) as ControlResponse;
      if (!response.ok || !data.controls) {
        throw new Error(data.error ?? "The demo control could not be updated.");
      }
      setControls(data.controls);
      setDraftPresets(data.controls.commentPresets);
      setPresetsDirty(false);
      toast.success("Live demo setting updated");
    } catch (error) {
      toast.error(
        error instanceof Error
          ? error.message
          : "The demo control could not be updated.",
      );
    } finally {
      setSaving(null);
    }
  };

  const toggle = (key: BooleanControlKey, checked: boolean) => {
    void save({ [key]: checked }, key);
  };

  const updateCategory = (
    categoryId: string,
    update: (category: DemoCommentPreset) => DemoCommentPreset,
  ) => {
    setDraftPresets((current) =>
      current.map((category) =>
        category.id === categoryId ? update(category) : category,
      ),
    );
    setPresetsDirty(true);
  };

  const addCategory = () => {
    const name = newCategory.trim();
    if (!name || draftPresets.length >= 10) return;
    setDraftPresets((current) => [
      ...current,
      { id: crypto.randomUUID(), name, chips: [] },
    ]);
    setNewCategory("");
    setPresetsDirty(true);
  };

  const addChip = (categoryId: string) => {
    const chip = (newChips[categoryId] ?? "").trim();
    if (!chip) return;
    updateCategory(categoryId, (category) => {
      if (
        category.chips.length >= 20 ||
        category.chips.some(
          (existing) => existing.toLocaleLowerCase() === chip.toLocaleLowerCase(),
        )
      ) {
        return category;
      }
      return { ...category, chips: [...category.chips, chip] };
    });
    setNewChips((current) => ({ ...current, [categoryId]: "" }));
  };

  const disabled = !active || saving !== null;
  const toggleRows: Array<{
    key: BooleanControlKey;
    label: string;
    description: string;
    icon: typeof Mic2;
    disabled?: boolean;
  }> = [
    {
      key: "audioRecordingEnabled",
      label: "Comprehension audio recording",
      description:
        "Show or hide the guided record-and-playback preview. Shared demo recordings are never uploaded or retained.",
      icon: Mic2,
      // The global kill switch must prevent enabling, but an operator can
      // always turn an already-enabled school preview back off.
      disabled:
        !controls.audioPlatformEnabled && !controls.audioRecordingEnabled,
    },
    {
      key: "parentCommentsEnabled",
      label: "Parent comment chips",
      description:
        "Show or hide the comment choices in the family reading-log flow.",
      icon: MessageSquareText,
    },
    {
      key: "freeTextCommentsEnabled",
      label: "Typed custom comments",
      description:
        "Allow parents to type a note as well as selecting preset chips.",
      icon: MessageCircleMore,
      disabled: !controls.parentCommentsEnabled,
    },
    {
      key: "messagingEnabled",
      label: "Parent–teacher communication",
      description:
        "Show or hide the private message thread and unread-message surfaces.",
      icon: MessageCircleMore,
    },
    {
      key: "quickLoggingEnabled",
      label: "Quick reading logs",
      description: "Show or hide the faster minutes-only reading-log option.",
      icon: Rabbit,
    },
  ];

  return (
    <div className="space-y-4 rounded-lg border bg-muted/20 p-4">
      <div>
        <h3 className="font-semibold">Live demo controls</h3>
        <p className="mt-1 text-xs text-muted-foreground">
          These settings update only the isolated demo school and flow into the
          parent app, teacher app and school portal. Open screens may need a
          refresh before the change appears.
        </p>
        {!active && (
          <p className="mt-2 text-xs font-medium text-amber-700">
            Prepare today&apos;s demo before changing these controls.
          </p>
        )}
        {!controls.audioPlatformEnabled && (
          <p className="mt-2 text-xs font-medium text-amber-700">
            Audio is currently unavailable under Lumi&apos;s platform-wide safety
            switch.
          </p>
        )}
      </div>

      <div className="grid gap-3 lg:grid-cols-2">
        {toggleRows.map((row) => {
          const Icon = row.icon;
          const rowSaving = saving === row.key;
          return (
            <div
              key={row.key}
              className="flex items-start justify-between gap-4 rounded-lg border bg-background p-3"
            >
              <div className="flex min-w-0 gap-3">
                <Icon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                <div>
                  <Label htmlFor={`demo-${row.key}`} className="text-sm font-medium">
                    {row.label}
                  </Label>
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {row.description}
                  </p>
                </div>
              </div>
              {rowSaving ? (
                <LoaderCircle className="mt-0.5 h-4 w-4 animate-spin" />
              ) : (
                <Switch
                  id={`demo-${row.key}`}
                  checked={controls[row.key]}
                  disabled={disabled || row.disabled}
                  onCheckedChange={(checked) => toggle(row.key, checked)}
                  aria-label={row.label}
                />
              )}
            </div>
          );
        })}
      </div>

      <div className="space-y-3 border-t pt-4">
        <div>
          <h4 className="text-sm font-semibold">Comment chip customisation</h4>
          <p className="text-xs text-muted-foreground">
            The default categories stay populated, but you can change them live
            to demonstrate each school&apos;s customisation options.
          </p>
        </div>

        {draftPresets.map((category) => (
          <div key={category.id} className="rounded-lg border bg-background p-3">
            <div className="mb-3 flex items-center gap-2">
              <Input
                value={category.name}
                maxLength={50}
                disabled={disabled}
                aria-label="Comment category name"
                onChange={(event) =>
                  updateCategory(category.id, (current) => ({
                    ...current,
                    name: event.target.value,
                  }))
                }
              />
              <Button
                variant="ghost"
                size="icon-sm"
                disabled={disabled || draftPresets.length <= 1}
                onClick={() => {
                  setDraftPresets((current) =>
                    current.filter((item) => item.id !== category.id),
                  );
                  setPresetsDirty(true);
                }}
                aria-label={`Remove ${category.name}`}
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
            <div className="mb-3 flex flex-wrap gap-2">
              {category.chips.map((chip) => (
                <button
                  key={chip}
                  type="button"
                  disabled={disabled}
                  className="rounded-full border bg-muted/40 px-3 py-1 text-xs hover:bg-muted disabled:opacity-60"
                  title="Remove comment chip"
                  onClick={() =>
                    updateCategory(category.id, (current) => ({
                      ...current,
                      chips: current.chips.filter((value) => value !== chip),
                    }))
                  }
                >
                  {chip} ×
                </button>
              ))}
            </div>
            <div className="flex gap-2">
              <Input
                value={newChips[category.id] ?? ""}
                maxLength={100}
                disabled={disabled || category.chips.length >= 20}
                placeholder="Add a comment chip"
                onChange={(event) =>
                  setNewChips((current) => ({
                    ...current,
                    [category.id]: event.target.value,
                  }))
                }
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    addChip(category.id);
                  }
                }}
              />
              <Button
                variant="outline"
                size="sm"
                disabled={disabled || category.chips.length >= 20}
                onClick={() => addChip(category.id)}
              >
                <Plus className="h-4 w-4" /> Add
              </Button>
            </div>
          </div>
        ))}

        <div className="flex flex-col gap-2 sm:flex-row">
          <Input
            value={newCategory}
            maxLength={50}
            disabled={disabled || draftPresets.length >= 10}
            placeholder="New comment category"
            onChange={(event) => setNewCategory(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                addCategory();
              }
            }}
          />
          <Button
            variant="outline"
            size="sm"
            disabled={disabled || draftPresets.length >= 10}
            onClick={addCategory}
          >
            <Plus className="h-4 w-4" /> Add category
          </Button>
          <Button
            size="sm"
            disabled={disabled || !presetsDirty}
            onClick={() => void save({ commentPresets: draftPresets }, "presets")}
          >
            {saving === "presets" && (
              <LoaderCircle className="h-4 w-4 animate-spin" />
            )}
            Save chip customisation
          </Button>
        </div>
      </div>
    </div>
  );
}
