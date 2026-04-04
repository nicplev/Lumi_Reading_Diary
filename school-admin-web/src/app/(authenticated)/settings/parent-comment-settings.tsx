'use client';

import { useState, useEffect } from 'react';
import { Card } from '@/components/lumi/card';
import { Input } from '@/components/lumi/input';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import type { CommentPresetCategory, ParentCommentSettings } from '@/lib/types';

const DEFAULT_PRESETS: CommentPresetCategory[] = [
  { id: 'default-1', name: 'Encouragement', chips: ['Great job!', 'Keep it up!', 'Loved hearing you read!', 'So proud of you!'] },
  { id: 'default-2', name: 'Reading Skills', chips: ['Sounded out words well', 'Good finger tracking', 'Read with expression', 'Used picture clues'] },
  { id: 'default-3', name: 'Comprehension', chips: ['Understood the story well', 'Asked great questions', 'Made predictions', 'Retold the story'] },
];

interface ParentCommentSettingsSectionProps {
  settings: ParentCommentSettings | undefined;
  isAdmin: boolean;
  onSave: (settings: ParentCommentSettings) => Promise<void>;
  saving: boolean;
}

export function ParentCommentSettingsSection({
  settings,
  isAdmin,
  onSave,
  saving,
}: ParentCommentSettingsSectionProps) {
  const [enabled, setEnabled] = useState(true);
  const [freeTextEnabled, setFreeTextEnabled] = useState(true);
  const [customPresets, setCustomPresets] = useState<CommentPresetCategory[]>([]);
  const [newChipInputs, setNewChipInputs] = useState<Record<string, string>>({});
  const [newCategoryName, setNewCategoryName] = useState('');
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);

  useEffect(() => {
    if (settings) {
      setEnabled(settings.enabled);
      setFreeTextEnabled(settings.freeTextEnabled);
      setCustomPresets(settings.customPresets ?? []);
    }
  }, [settings]);

  const handleSave = () => {
    onSave({ enabled, freeTextEnabled, customPresets });
  };

  const addCategory = () => {
    const name = newCategoryName.trim();
    if (!name || customPresets.length >= 10) return;
    setCustomPresets([...customPresets, { id: crypto.randomUUID(), name, chips: [] }]);
    setNewCategoryName('');
  };

  const removeCategory = (id: string) => {
    setCustomPresets(customPresets.filter((c) => c.id !== id));
    setDeleteTarget(null);
  };

  const updateCategoryName = (id: string, name: string) => {
    setCustomPresets(customPresets.map((c) => (c.id === id ? { ...c, name } : c)));
  };

  const addChip = (categoryId: string) => {
    const chipText = (newChipInputs[categoryId] ?? '').trim();
    if (!chipText) return;
    setCustomPresets(
      customPresets.map((c) => {
        if (c.id !== categoryId) return c;
        if (c.chips.length >= 20) return c;
        if (c.chips.includes(chipText)) return c;
        return { ...c, chips: [...c.chips, chipText] };
      })
    );
    setNewChipInputs({ ...newChipInputs, [categoryId]: '' });
  };

  const removeChip = (categoryId: string, chip: string) => {
    setCustomPresets(
      customPresets.map((c) =>
        c.id === categoryId ? { ...c, chips: c.chips.filter((ch) => ch !== chip) } : c
      )
    );
  };

  const moveCategory = (index: number, direction: 'up' | 'down') => {
    const newIndex = direction === 'up' ? index - 1 : index + 1;
    if (newIndex < 0 || newIndex >= customPresets.length) return;
    const updated = [...customPresets];
    [updated[index], updated[newIndex]] = [updated[newIndex], updated[index]];
    setCustomPresets(updated);
  };

  const previewPresets = customPresets.length > 0 ? customPresets : DEFAULT_PRESETS;

  return (
    <>
      <Card>
        <h2 className="text-lg font-bold text-charcoal mb-1">Parent Comments</h2>
        <p className="text-sm text-text-secondary mb-4">
          Control how parents leave feedback when logging reading sessions.
        </p>

        <div className={`space-y-6 ${!enabled ? 'opacity-50 pointer-events-none' : ''}`} style={!enabled ? { pointerEvents: 'none' } : undefined}>
          {/* This toggle is always interactive */}
        </div>

        {/* Enable toggle - always interactive */}
        <label className="flex items-center gap-3 mb-6 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => setEnabled(e.target.checked)}
            disabled={!isAdmin}
            className="w-5 h-5 rounded border-gray-300 text-rose-400 focus:ring-rose-400 cursor-pointer"
          />
          <div>
            <span className="text-sm font-semibold text-charcoal">Enable parent comments</span>
            <p className="text-xs text-text-secondary">When disabled, the comment step is hidden from parents entirely.</p>
          </div>
        </label>

        <div className={enabled ? '' : 'opacity-40 pointer-events-none'}>
          {/* Free-text toggle */}
          <label className="flex items-center gap-3 mb-6 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={freeTextEnabled}
              onChange={(e) => setFreeTextEnabled(e.target.checked)}
              disabled={!isAdmin}
              className="w-5 h-5 rounded border-gray-300 text-rose-400 focus:ring-rose-400 cursor-pointer"
            />
            <div>
              <span className="text-sm font-semibold text-charcoal">Allow free-text comments</span>
              <p className="text-xs text-text-secondary">When disabled, parents can only select from preset options (no typed comments).</p>
            </div>
          </label>

          {/* Custom Presets */}
          <div className="border-t border-border pt-4">
            <h3 className="text-sm font-bold text-charcoal mb-1">Custom Comment Presets</h3>
            <p className="text-xs text-text-secondary mb-4">
              Add custom categories and comment options. When no custom presets are configured, default comments are shown to parents.
            </p>

            {customPresets.map((category, index) => (
              <div key={category.id} className="mb-4 p-4 bg-gray-50 rounded-lg border border-border">
                <div className="flex items-center gap-2 mb-3">
                  {/* Reorder buttons */}
                  <div className="flex flex-col gap-0.5">
                    <button
                      type="button"
                      onClick={() => moveCategory(index, 'up')}
                      disabled={index === 0 || !isAdmin}
                      className="text-xs text-text-secondary hover:text-charcoal disabled:opacity-30 p-0.5"
                      title="Move up"
                    >
                      &#9650;
                    </button>
                    <button
                      type="button"
                      onClick={() => moveCategory(index, 'down')}
                      disabled={index === customPresets.length - 1 || !isAdmin}
                      className="text-xs text-text-secondary hover:text-charcoal disabled:opacity-30 p-0.5"
                      title="Move down"
                    >
                      &#9660;
                    </button>
                  </div>

                  <Input
                    value={category.name}
                    onChange={(e) => updateCategoryName(category.id, e.target.value)}
                    disabled={!isAdmin}
                    placeholder="Category name"
                    className="flex-1"
                    maxLength={50}
                  />

                  <Button
                    variant="danger"
                    size="sm"
                    onClick={() => setDeleteTarget(category.id)}
                    disabled={!isAdmin}
                  >
                    Remove
                  </Button>
                </div>

                {/* Chips */}
                <div className="flex flex-wrap gap-1.5 mb-3">
                  {category.chips.map((chip) => (
                    <span
                      key={chip}
                      className="inline-flex items-center gap-1 px-2.5 py-1 bg-white border border-border rounded-full text-sm text-charcoal"
                    >
                      {chip}
                      {isAdmin && (
                        <button
                          type="button"
                          onClick={() => removeChip(category.id, chip)}
                          className="text-text-secondary hover:text-red-500 text-xs ml-0.5"
                          title="Remove chip"
                        >
                          &times;
                        </button>
                      )}
                    </span>
                  ))}
                  {category.chips.length === 0 && (
                    <span className="text-xs text-text-secondary italic">No comment options yet</span>
                  )}
                </div>

                {/* Add chip input */}
                {isAdmin && category.chips.length < 20 && (
                  <div className="flex gap-2">
                    <Input
                      value={newChipInputs[category.id] ?? ''}
                      onChange={(e) =>
                        setNewChipInputs({ ...newChipInputs, [category.id]: e.target.value })
                      }
                      placeholder="Add a comment option..."
                      maxLength={100}
                      className="flex-1"
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          e.preventDefault();
                          addChip(category.id);
                        }
                      }}
                    />
                    <Button variant="outline" size="sm" onClick={() => addChip(category.id)}>
                      Add
                    </Button>
                  </div>
                )}
              </div>
            ))}

            {/* Add category */}
            {isAdmin && customPresets.length < 10 && (
              <div className="flex gap-2 mt-2">
                <Input
                  value={newCategoryName}
                  onChange={(e) => setNewCategoryName(e.target.value)}
                  placeholder="New category name..."
                  maxLength={50}
                  className="flex-1"
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      addCategory();
                    }
                  }}
                />
                <Button variant="outline" onClick={addCategory} disabled={!newCategoryName.trim()}>
                  Add Category
                </Button>
              </div>
            )}
          </div>

          {/* Preview */}
          <div className="border-t border-border pt-4 mt-4">
            <h3 className="text-sm font-bold text-charcoal mb-1">Preview</h3>
            <p className="text-xs text-text-secondary mb-3">
              {customPresets.length > 0
                ? 'Parents will see your custom presets below.'
                : 'No custom presets configured \u2014 parents will see these defaults.'}
            </p>
            <div className="space-y-3">
              {previewPresets.map((cat) => (
                <div key={cat.id}>
                  <p className="text-xs font-semibold text-text-secondary mb-1.5">{cat.name}</p>
                  <div className="flex flex-wrap gap-1.5">
                    {cat.chips.map((chip) => (
                      <Badge key={chip} variant="default">{chip}</Badge>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            {freeTextEnabled && (
              <div className="mt-3 p-3 bg-gray-50 rounded-lg border border-dashed border-border">
                <p className="text-xs text-text-secondary italic">+ Free-text comment field will be shown</p>
              </div>
            )}
          </div>
        </div>

        {isAdmin && (
          <div className="flex justify-end mt-6">
            <Button onClick={handleSave} loading={saving}>
              Save Parent Comments
            </Button>
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={deleteTarget !== null}
        onClose={() => setDeleteTarget(null)}
        onConfirm={() => deleteTarget && removeCategory(deleteTarget)}
        title="Remove Category?"
        description="This will remove the category and all its comment options. Parents will no longer see these options."
        confirmLabel="Remove"
        variant="danger"
      />
    </>
  );
}
