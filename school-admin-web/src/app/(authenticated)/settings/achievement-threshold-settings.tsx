'use client';

import { useState, useEffect } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { Icon } from '@/components/lumi/icon';
import type { AchievementThresholds, AchievementCustomization, AchievementTierCustomization } from '@/lib/types';
import { DEFAULT_ACHIEVEMENT_THRESHOLDS } from '@/lib/types';

interface AchievementThresholdSettingsProps {
  thresholds?: AchievementThresholds;
  customization?: AchievementCustomization;
  isAdmin: boolean;
  onSave: (thresholds: AchievementThresholds, customization: AchievementCustomization) => Promise<void>;
  saving: boolean;
}

// Per-tier display metadata — names and colors are the app defaults (used as placeholders/reset targets)
const TIER_META = {
  streak: [
    { name: 'Weekly Winner',    rarity: 'Common',    color: '#CD7F32' },
    { name: 'Fortnight Fan',    rarity: 'Uncommon',  color: '#C0C0C0' },
    { name: 'Month Warrior',    rarity: 'Rare',      color: '#FFD700' },
    { name: 'Season Streak',    rarity: 'Epic',      color: '#A855F7' },
    { name: 'Century Champion', rarity: 'Legendary', color: '#FF1493' },
  ],
  books: [
    { name: 'Book Beginner',  rarity: 'Common',    color: '#CD7F32' },
    { name: 'Book Collector', rarity: 'Uncommon',  color: '#C0C0C0' },
    { name: 'Avid Reader',    rarity: 'Rare',      color: '#FFD700' },
    { name: 'Bookworm',       rarity: 'Epic',      color: '#A855F7' },
    { name: 'Reading Legend', rarity: 'Legendary', color: '#FF1493' },
  ],
  minutes: [
    { name: 'Hour Hand',       rarity: 'Common',    color: '#CD7F32' },
    { name: 'Time Traveler',   rarity: 'Uncommon',  color: '#C0C0C0' },
    { name: 'Marathon Reader', rarity: 'Rare',      color: '#FFD700' },
    { name: 'Time Master',     rarity: 'Epic',      color: '#A855F7' },
    { name: 'Eternal Reader',  rarity: 'Legendary', color: '#FF1493' },
  ],
  readingDays: [
    { name: 'Decade Reader',    rarity: 'Common',   color: '#CD7F32' },
    { name: 'Monthly Reader',   rarity: 'Uncommon', color: '#C0C0C0' },
    { name: 'Consistent Reader',rarity: 'Rare',     color: '#FFD700' },
    { name: 'Century Reader',   rarity: 'Epic',     color: '#A855F7' },
  ],
} as const;

type Category = 'streak' | 'books' | 'minutes' | 'readingDays';

const CATEGORY_CONFIG: { key: Category; label: string; icon: string; unit: string; hint: (v: number) => string }[] = [
  { key: 'streak',      label: 'Streak Days',   icon: 'local_fire_department', unit: 'days',  hint: (v) => `${v} school days in a row` },
  { key: 'books',       label: 'Books Read',    icon: 'menu_book', unit: 'books', hint: (v) => `${v} books read` },
  { key: 'minutes',     label: 'Reading Time',  icon: 'schedule', unit: 'min',   hint: (v) => `${v} min (${Math.round(v / 60 * 10) / 10}h)` },
  { key: 'readingDays', label: 'Reading Days',  icon: 'calendar_month', unit: 'days',  hint: (v) => `${v} unique reading days` },
];

function emptyCustomization(): AchievementCustomization {
  return {
    streak:      Array(5).fill({}) as AchievementCustomization['streak'],
    books:       Array(5).fill({}) as AchievementCustomization['books'],
    minutes:     Array(5).fill({}) as AchievementCustomization['minutes'],
    readingDays: Array(4).fill({}) as AchievementCustomization['readingDays'],
  };
}

function validateAscending(values: number[]): string | null {
  for (let i = 1; i < values.length; i++) {
    if (values[i] <= values[i - 1]) {
      return `Tier ${i + 1} must be greater than Tier ${i}`;
    }
  }
  return null;
}

export function AchievementThresholdSettings({
  thresholds,
  customization: customizationProp,
  isAdmin,
  onSave,
  saving,
}: AchievementThresholdSettingsProps) {
  const [values, setValues] = useState<AchievementThresholds>(
    thresholds ?? DEFAULT_ACHIEVEMENT_THRESHOLDS
  );
  const [customization, setCustomization] = useState<AchievementCustomization>(
    customizationProp ?? emptyCustomization()
  );
  const [errors, setErrors] = useState<Partial<Record<Category, string>>>({});

  useEffect(() => {
    if (thresholds) setValues(thresholds);
  }, [thresholds]);

  useEffect(() => {
    if (customizationProp) setCustomization(customizationProp);
  }, [customizationProp]);

  function updateTier(category: Category, tierIndex: number, raw: string) {
    const num = parseInt(raw, 10);
    setValues((prev) => {
      const updated = [...prev[category]] as number[];
      updated[tierIndex] = isNaN(num) ? 0 : num;
      return { ...prev, [category]: updated as AchievementThresholds[typeof category] };
    });
    setErrors((prev) => ({ ...prev, [category]: undefined }));
  }

  function updateTierName(category: Category, tierIndex: number, name: string) {
    setCustomization((prev) => {
      const tiers = [...(prev[category] ?? Array(TIER_META[category].length).fill({}))] as AchievementTierCustomization[];
      tiers[tierIndex] = { ...tiers[tierIndex], name };
      return { ...prev, [category]: tiers } as AchievementCustomization;
    });
  }

  function updateTierColor(category: Category, tierIndex: number, color: string) {
    setCustomization((prev) => {
      const tiers = [...(prev[category] ?? Array(TIER_META[category].length).fill({}))] as AchievementTierCustomization[];
      tiers[tierIndex] = { ...tiers[tierIndex], color };
      return { ...prev, [category]: tiers } as AchievementCustomization;
    });
  }

  function resetCategory(category: Category) {
    setValues((prev) => ({
      ...prev,
      [category]: [...DEFAULT_ACHIEVEMENT_THRESHOLDS[category]],
    }));
    const defaultEmpty = Array(TIER_META[category].length).fill({}) as AchievementTierCustomization[];
    setCustomization((prev) => ({ ...prev, [category]: defaultEmpty } as AchievementCustomization));
    setErrors((prev) => ({ ...prev, [category]: undefined }));
  }

  async function handleSave() {
    const newErrors: Partial<Record<Category, string>> = {};
    for (const { key } of CATEGORY_CONFIG) {
      const err = validateAscending(values[key] as number[]);
      if (err) newErrors[key] = err;
    }
    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      return;
    }

    // Strip blank names before saving — treat empty string as "use default"
    const cleanedCustomization: AchievementCustomization = {} as AchievementCustomization;
    for (const { key } of CATEGORY_CONFIG) {
      const tiers = customization[key] as AchievementTierCustomization[] | undefined;
      if (tiers) {
        (cleanedCustomization as Record<string, unknown>)[key] = tiers.map((t) => ({
          ...(t.name?.trim() ? { name: t.name.trim() } : {}),
          ...(t.color ? { color: t.color } : {}),
        }));
      }
    }

    await onSave(values, cleanedCustomization);
  }

  return (
    <Card>
      <div className="mb-5">
        <h2 className="text-lg font-bold text-charcoal">Achievement Milestones</h2>
        <p className="text-sm text-text-secondary mt-0.5">
          Customise when each badge is earned, its name, and its colour. Values must increase across tiers. Changes take effect for new achievements only.
        </p>
      </div>

      <div className="space-y-6">
        {CATEGORY_CONFIG.map(({ key, label, icon, hint }) => {
          const tiers = TIER_META[key];
          const tierValues = values[key] as number[];
          const error = errors[key];

          return (
            <div key={key} className="border border-divider rounded-[var(--radius-md)] p-4">
              {/* Category header */}
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <Icon name={icon} size={20} className="text-text-secondary" />
                  <span className="font-semibold text-charcoal text-sm">{label}</span>
                </div>
                {isAdmin && (
                  <button
                    type="button"
                    onClick={() => resetCategory(key)}
                    className="text-xs text-text-secondary hover:text-charcoal transition-colors flex items-center gap-1"
                  >
                    <Icon name="restart_alt" size={14} />
                    Reset to defaults
                  </button>
                )}
              </div>

              {/* Column headers */}
              <div className="flex items-center gap-3 mb-1.5 px-0.5">
                <span className="text-[11px] text-text-secondary w-28 flex-shrink-0">Colour</span>
                <span className="text-[11px] text-text-secondary w-36 flex-shrink-0">Name</span>
                <span className="text-[11px] text-text-secondary w-20 flex-shrink-0">Threshold</span>
                <span className="text-[11px] text-text-secondary flex-1">Hint</span>
              </div>

              {/* Tier rows */}
              <div className="space-y-2">
                {tiers.map((tier, i) => {
                  const customTier = (customization[key] as AchievementTierCustomization[] | undefined)?.[i] ?? {};
                  const displayColor = customTier.color ?? tier.color;
                  const displayName  = customTier.name  ?? '';

                  return (
                    <div key={i} className="flex items-center gap-3">
                      {/* Colour swatch + rarity label */}
                      <div className="flex items-center gap-1.5 flex-shrink-0 w-28">
                        {isAdmin ? (
                          <label className="flex items-center gap-1.5 cursor-pointer group">
                            <span className="relative">
                              <input
                                type="color"
                                value={displayColor}
                                onChange={(e) => updateTierColor(key, i, e.target.value)}
                                className="opacity-0 absolute inset-0 w-full h-full cursor-pointer"
                                title="Change colour"
                              />
                              <span
                                className="block w-6 h-6 rounded border border-black/10 shadow-sm group-hover:scale-105 transition-transform"
                                style={{ backgroundColor: displayColor }}
                              />
                            </span>
                            <span
                              className="text-xs font-semibold"
                              style={{ color: displayColor }}
                            >
                              {tier.rarity}
                            </span>
                          </label>
                        ) : (
                          <div className="flex items-center gap-1.5">
                            <span
                              className="block w-6 h-6 rounded border border-black/10"
                              style={{ backgroundColor: displayColor }}
                            />
                            <span className="text-xs font-semibold" style={{ color: displayColor }}>
                              {tier.rarity}
                            </span>
                          </div>
                        )}
                      </div>

                      {/* Editable achievement name */}
                      <input
                        type="text"
                        value={displayName}
                        placeholder={tier.name}
                        maxLength={40}
                        onChange={(e) => updateTierName(key, i, e.target.value)}
                        disabled={!isAdmin}
                        className="w-36 flex-shrink-0 px-2 py-1.5 text-sm border border-divider rounded-[var(--radius-sm)] bg-surface text-charcoal placeholder:text-text-secondary/60 focus:outline-none focus:ring-2 focus:ring-brand/30 disabled:opacity-50 disabled:cursor-not-allowed"
                      />

                      {/* Number input */}
                      <div className="flex items-center gap-2 flex-1">
                        <input
                          type="number"
                          min={1}
                          value={tierValues[i] ?? ''}
                          onChange={(e) => updateTier(key, i, e.target.value)}
                          disabled={!isAdmin}
                          className="w-20 px-2 py-1.5 text-sm border border-divider rounded-[var(--radius-sm)] bg-surface text-charcoal focus:outline-none focus:ring-2 focus:ring-brand/30 disabled:opacity-50 disabled:cursor-not-allowed"
                        />
                        <span className="text-xs text-text-secondary whitespace-nowrap">
                          {hint(tierValues[i] ?? 0)}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Validation error */}
              {error && (
                <p className="text-xs text-red-500 mt-2 flex items-center gap-1">
                  <Icon name="error" size={14} />
                  {error}
                </p>
              )}
            </div>
          );
        })}
      </div>

      {isAdmin && (
        <div className="flex justify-end mt-5">
          <Button onClick={handleSave} loading={saving}>
            Save Achievement Settings
          </Button>
        </div>
      )}
    </Card>
  );
}
