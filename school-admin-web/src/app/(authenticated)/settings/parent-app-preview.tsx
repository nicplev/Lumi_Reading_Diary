'use client';

import { useState } from 'react';
import type { CommentPresetCategory } from '@/lib/types';

interface ParentAppPreviewProps {
  enabled: boolean;
  freeTextEnabled: boolean;
  presets: CommentPresetCategory[];
}

// Exact Lumi app tokens (lib/theme/lumi_tokens.dart + AppColors) so the preview
// renders pixel-faithfully against the real Flutter screen.
const NUNITO = 'var(--font-family-nunito), "Nunito", sans-serif'; // app display face
const INK = '#1A1A1A';         // LumiTokens.ink — labels, chip text
const CHARCOAL = '#121211';    // AppColors.charcoal — h2 heading
const MUTED = '#6B6B6B';       // LumiTokens.muted
const RULE = '#E5E2DC';        // LumiTokens.rule — borders
const CREAM = '#FBFAF6';       // LumiTokens.cream — body background
const PAPER = '#FFFFFF';       // LumiTokens.paper — app bar + unselected chip
const RED = '#EC4544';         // LumiTokens.red — progress + primary button
const GREEN = '#51BA65';       // LumiTokens.green — selected chip border
const TINT_GREEN = '#B5DAB8';  // LumiTokens.tintGreen — selected chip fill

// Max chips a parent may select (kMaxParentCommentChips in comment_chips.dart).
const MAX_CHIPS = 3;

/**
 * Live "iPhone 17 Pro" mockup of the parent app's reading-log comment step.
 * Rebuilt to match the real Flutter screen exactly —
 * lib/screens/parent/log_reading_screen.dart (_buildStepDetail + chrome) and
 * lib/core/widgets/lumi/comment_chips.dart — Nunito type, white/green chips,
 * the ✕-close + child-name app bar, 3-segment red progress with a step count,
 * the cream notes field, and the red primary button.
 *
 * Colors / dimensions are inline-styled (not Tailwind arbitrary values) so the
 * device renders pixel-faithfully regardless of the utility-class pipeline.
 */
export function ParentAppPreview({ enabled, freeTextEnabled, presets }: ParentAppPreviewProps) {
  // Local selection so chips feel "live" / tappable, just like the app.
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const toggle = (key: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const categories = presets.filter((c) => c.chips.length > 0);

  const SCREEN_W = 286;
  const SCREEN_H = 600;

  return (
    <div className="flex flex-col items-center">
      {/* ===== iPhone 17 Pro ===== */}
      <div
        className="relative"
        style={{
          width: SCREEN_W + 28,
          padding: 4,
          borderRadius: 64,
          // Titanium rail
          background: 'linear-gradient(145deg, #b8bcc2 0%, #8a8f96 35%, #d6d9dd 60%, #7e838a 100%)',
          boxShadow: '0 30px 60px -15px rgba(0,0,0,0.45), 0 8px 16px -6px rgba(0,0,0,0.3)',
        }}
      >
        {/* Side buttons */}
        <div style={{ position: 'absolute', left: -2, top: 120, width: 3, height: 26, borderRadius: 2, background: '#6c7177' }} />
        <div style={{ position: 'absolute', left: -2, top: 160, width: 3, height: 46, borderRadius: 2, background: '#6c7177' }} />
        <div style={{ position: 'absolute', left: -2, top: 218, width: 3, height: 46, borderRadius: 2, background: '#6c7177' }} />
        <div style={{ position: 'absolute', right: -2, top: 180, width: 3, height: 64, borderRadius: 2, background: '#6c7177' }} />

        {/* Black bezel */}
        <div style={{ borderRadius: 60, background: '#000', padding: 10 }}>
          {/* Screen */}
          <div
            style={{
              position: 'relative',
              width: SCREEN_W,
              height: SCREEN_H,
              borderRadius: 50,
              overflow: 'hidden',
              background: PAPER,
              color: INK,
              fontFamily: NUNITO,
            }}
          >
            {/* Dynamic Island */}
            <div
              style={{
                position: 'absolute',
                left: '50%',
                top: 11,
                transform: 'translateX(-50%)',
                width: 92,
                height: 26,
                borderRadius: 999,
                background: '#000',
                zIndex: 20,
              }}
            />

            {/* Status bar */}
            <div className="flex items-center justify-between" style={{ padding: '12px 24px 4px', fontSize: 11, fontWeight: 600 }}>
              <span>9:41</span>
              <div className="flex items-center" style={{ gap: 5 }}>
                <svg width="16" height="11" viewBox="0 0 16 11" fill="currentColor"><rect x="0" y="7" width="3" height="4" rx="0.5"/><rect x="4.5" y="5" width="3" height="6" rx="0.5"/><rect x="9" y="2.5" width="3" height="8.5" rx="0.5"/><rect x="13" y="0" width="3" height="11" rx="0.5"/></svg>
                <svg width="15" height="11" viewBox="0 0 15 11" fill="currentColor"><path d="M7.5 2C9.9 2 12.1 3 13.6 4.5l-1.1 1.1C11.3 4.4 9.5 3.6 7.5 3.6S3.7 4.4 2.5 5.6L1.4 4.5C2.9 3 5.1 2 7.5 2Zm0 3.2c1.4 0 2.7.6 3.6 1.5l-1.1 1.1c-.6-.6-1.5-1-2.5-1s-1.9.4-2.5 1L3.9 6.7c.9-.9 2.2-1.5 3.6-1.5Zm0 3.2c.6 0 1.1.2 1.5.6L7.5 10.6 6 9c.4-.4.9-.6 1.5-.6Z"/></svg>
                <svg width="25" height="12" viewBox="0 0 25 12" fill="none"><rect x="0.5" y="0.5" width="21" height="11" rx="3" stroke="currentColor" opacity="0.4"/><rect x="2" y="2" width="16" height="8" rx="1.5" fill="currentColor"/><rect x="23" y="4" width="1.5" height="4" rx="0.75" fill="currentColor" opacity="0.4"/></svg>
              </div>
            </div>

            {enabled ? (
              <div className="flex flex-col" style={{ height: SCREEN_H - 34 }}>
                {/* App bar (white) — ✕ close + child name, then the progress row */}
                <div style={{ background: PAPER, padding: '4px 16px 0' }}>
                  <div className="flex items-center" style={{ gap: 6, height: 38 }}>
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M6 6l12 12M18 6L6 18" stroke={INK} strokeWidth="2" strokeLinecap="round"/></svg>
                    <span style={{ fontSize: 16, fontWeight: 600, color: INK }}>Sam</span>
                  </div>
                  {/* Progress — 3 segments (done / active / upcoming) + step count */}
                  <div className="flex items-center" style={{ gap: 12, padding: '0 0 12px' }}>
                    <div className="flex" style={{ flex: 1, gap: 6 }}>
                      {[0, 1, 2].map((i) => (
                        <div
                          key={i}
                          style={{
                            height: 4,
                            flex: 1,
                            borderRadius: 2,
                            background: i < 1 ? RED : i === 1 ? 'rgba(236,69,68,0.6)' : 'rgba(26,26,26,0.1)',
                          }}
                        />
                      ))}
                    </div>
                    <span style={{ fontSize: 12, color: MUTED, whiteSpace: 'nowrap' }}>Step 2 of 3</span>
                  </div>
                </div>

                {/* Scrollable comment step (cream body) */}
                <div style={{ flex: 1, overflowY: 'auto', background: CREAM, padding: '16px 16px 8px' }}>
                  <h2 style={{ fontSize: 24, fontWeight: 600, lineHeight: 1.3, color: CHARCOAL, margin: 0 }}>How did it go?</h2>
                  <p style={{ fontSize: 14, lineHeight: 1.5, marginTop: 8, color: 'rgba(26,26,26,0.6)' }}>
                    Select up to {MAX_CHIPS} that apply (optional)
                  </p>

                  <div style={{ marginTop: 20, display: 'flex', flexDirection: 'column', gap: 16 }}>
                    {categories.map((cat) => (
                      <div key={cat.id}>
                        <p style={{ fontSize: 14, fontWeight: 600, lineHeight: 1.4, marginBottom: 8, color: 'rgba(26,26,26,0.7)' }}>{cat.name}</p>
                        <div className="flex flex-wrap" style={{ gap: 8 }}>
                          {cat.chips.map((chip) => {
                            const key = `${cat.id}::${chip}`;
                            const isSelected = selected.has(key);
                            const chipEnabled = isSelected || selected.size < MAX_CHIPS;
                            return (
                              <button
                                key={key}
                                type="button"
                                disabled={!chipEnabled}
                                onClick={() => chipEnabled && toggle(key)}
                                className="inline-flex items-center"
                                style={{
                                  gap: 4,
                                  borderRadius: 20,
                                  padding: '8px 16px',
                                  fontSize: 14,
                                  lineHeight: 1.5,
                                  fontFamily: NUNITO,
                                  transition: 'all 200ms',
                                  border: `1px solid ${isSelected ? GREEN : RULE}`,
                                  background: isSelected ? TINT_GREEN : PAPER,
                                  fontWeight: isSelected ? 600 : 400,
                                  color: INK,
                                  opacity: chipEnabled ? 1 : 0.4,
                                  cursor: chipEnabled ? 'pointer' : 'default',
                                }}
                              >
                                {isSelected && (
                                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M20 6L9 17l-5-5" stroke="rgba(26,26,26,0.8)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
                                )}
                                {chip}
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    ))}

                    {categories.length === 0 && (
                      <p style={{ fontSize: 14, fontStyle: 'italic', color: 'rgba(26,26,26,0.4)' }}>
                        No comment options configured yet.
                      </p>
                    )}
                  </div>

                  {freeTextEnabled && (
                    <div style={{ marginTop: 24 }}>
                      <p style={{ fontSize: 14, fontWeight: 600, lineHeight: 1.4, marginBottom: 8, color: INK }}>Additional notes</p>
                      <div style={{ borderRadius: 14, border: `1px solid ${RULE}`, background: CREAM, padding: 14, fontSize: 14, color: 'rgba(26,26,26,0.4)', minHeight: 58 }}>
                        Anything else to add? (optional)
                      </div>
                    </div>
                  )}
                </div>

                {/* Footer — red primary button (LumiPrimaryButton, LumiTokens.red) */}
                <div style={{ background: CREAM, padding: 16 }}>
                  <div style={{ width: '100%', borderRadius: 16, background: RED, padding: '15px 0', textAlign: 'center', fontSize: 16, fontWeight: 600, letterSpacing: 0.5, color: PAPER }}>
                    Next
                  </div>
                </div>
              </div>
            ) : (
              // Comment step disabled — mirrors the app skipping the step.
              <div className="flex flex-col items-center justify-center text-center" style={{ height: SCREEN_H - 34, background: CREAM, padding: '0 32px' }}>
                <div className="flex items-center justify-center" style={{ width: 56, height: 56, borderRadius: 999, background: 'rgba(26,26,26,0.05)' }}>
                  <svg width="26" height="26" viewBox="0 0 24 24" fill="none"><path d="M3 3l18 18M9.5 4.2A9 9 0 0121 12c0 1.1-.2 2.1-.6 3M5 7a9 9 0 00-2 5c0 5 4 9 9 9a9 9 0 005-1.5" stroke="rgba(26,26,26,0.4)" strokeWidth="1.8" strokeLinecap="round"/></svg>
                </div>
                <p style={{ fontSize: 15, fontWeight: 600, marginTop: 16, color: INK }}>Comments are turned off</p>
                <p style={{ fontSize: 13, marginTop: 6, color: 'rgba(26,26,26,0.55)' }}>
                  Parents skip the comment step and go straight to reviewing their session.
                </p>
              </div>
            )}
          </div>
        </div>
      </div>

      <p className="mt-3 text-center text-xs text-muted">
        Live preview &mdash; tap a chip to see the selected state
      </p>
    </div>
  );
}
