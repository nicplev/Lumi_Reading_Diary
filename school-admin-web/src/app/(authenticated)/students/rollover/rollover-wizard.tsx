'use client';

import { useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { Select } from '@/components/lumi/select';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { parseCSV, matchHeader } from '@/lib/csv';
import type { RolloverCSVRow } from '@/lib/rollover/classify';
import type { RolloverAction, RolloverPlan, RolloverCommitResult } from '@/lib/rollover/plan';
import type { RolloverPreview, RolloverImportSummary } from '@/lib/firestore/rollover';
import { ReviewStep, type MissingDisposition, type RowResolution } from './review-step';

interface ClassOption {
  id: string;
  name: string;
  yearLevel: string | null;
}

interface RolloverWizardProps {
  classes: ClassOption[];
  currentAcademicYear: number;
  recentImports: RolloverImportSummary[];
}

type WizardStep = 'upload' | 'review' | 'confirm' | 'applying' | 'done';

const TEMPLATE_CSV = [
  'Student ID,First Name,Last Name,Class Name,Year Level,Parent Email',
  'S10001,Jane,Smith,4A,4,',
  'S10002,Tom,Brown,4A,4,',
  ',Zoe,Nguyen,Prep B,Prep,zoe.parent@email.com',
].join('\n');

export function RolloverWizard({ classes, currentAcademicYear, recentImports }: RolloverWizardProps) {
  const { toast } = useToast();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [step, setStep] = useState<WizardStep>('upload');
  // Oct–Dec: schools prepare next year's classes → default to next year.
  const defaultTarget = new Date().getMonth() >= 9 ? currentAcademicYear + 1 : currentAcademicYear;
  const [targetYear, setTargetYear] = useState(defaultTarget);
  const [preview, setPreview] = useState<RolloverPreview | null>(null);
  const [loadingPreview, setLoadingPreview] = useState(false);

  // Review-step resolutions.
  const [rowRes, setRowRes] = useState<Record<number, RowResolution>>({});
  const [missingRes, setMissingRes] = useState<Record<string, MissingDisposition>>({});
  const [deactivateIds, setDeactivateIds] = useState<Set<string>>(new Set());

  const [archiveGuardChecked, setArchiveGuardChecked] = useState(false);
  const [result, setResult] = useState<RolloverCommitResult | null>(null);
  const [showUndoConfirm, setShowUndoConfirm] = useState(false);
  const [undoTarget, setUndoTarget] = useState<string | null>(null);
  const [undoing, setUndoing] = useState(false);

  // ── Upload ─────────────────────────────────────────────────────────────────

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = async (ev) => {
      const text = ev.target?.result as string;
      const { headers, rows } = parseCSV(text);
      const mapping: Record<number, string> = {};
      headers.forEach((h, i) => {
        const field = matchHeader(h);
        if (field) mapping[i] = field;
      });
      const parsed: RolloverCSVRow[] = rows.map((r) => {
        const obj: Record<string, string> = {};
        headers.forEach((_, i) => {
          const field = mapping[i];
          if (field) obj[field] = r[i] ?? '';
        });
        return {
          studentId: obj.studentId || undefined,
          firstName: obj.firstName ?? '',
          lastName: obj.lastName ?? '',
          className: obj.className ?? '',
          yearLevel: obj.yearLevel || undefined,
          parentEmail: obj.parentEmail || undefined,
          readingLevel: obj.readingLevel || undefined,
        };
      });

      if (parsed.length === 0) {
        toast('No rows found in that file', 'error');
        return;
      }
      if (parsed.length > 2000) {
        toast('Maximum 2000 rows per import', 'error');
        return;
      }

      setLoadingPreview(true);
      try {
        const res = await fetch('/api/rollover/preview', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ rows: parsed, targetAcademicYear: targetYear }),
        });
        if (!res.ok) {
          const err = await res.json();
          throw new Error(err.error || 'Preview failed');
        }
        const data: RolloverPreview = await res.json();
        setPreview(data);
        setRowRes({});
        setMissingRes({});
        setDeactivateIds(new Set());
        setArchiveGuardChecked(false);
        setStep('review');
      } catch (error) {
        toast(error instanceof Error ? error.message : 'Preview failed', 'error');
      } finally {
        setLoadingPreview(false);
        if (fileInputRef.current) fileInputRef.current.value = '';
      }
    };
    reader.readAsText(file);
  };

  const downloadTemplate = () => {
    const blob = new Blob([TEMPLATE_CSV], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'lumi_rollover_import_template.csv';
    a.click();
    URL.revokeObjectURL(url);
  };

  // ── Plan derivation ────────────────────────────────────────────────────────

  const derived = useMemo(() => {
    if (!preview) return null;
    const actions: RolloverAction[] = [];
    const confirmedDocIds = new Set<string>();

    for (const row of preview.rows) {
      const res = rowRes[row.rowIndex] ?? {};
      if (row.bucket === 'error' || res.excluded) continue;
      const className = (res.overrideClassName ?? row.csv.className).trim();
      const base = {
        firstName: row.csv.firstName.trim(),
        lastName: row.csv.lastName.trim(),
        className,
        yearLevel: row.csv.yearLevel?.trim() || undefined,
        parentEmail: row.csv.parentEmail?.trim() || undefined,
      };
      const asCreate = (): RolloverAction => ({
        action: 'create',
        externalId: row.csv.studentId?.trim() || undefined,
        ...base,
        readingLevel: row.csv.readingLevel?.trim() || undefined,
      });

      if (row.bucket === 'match') {
        actions.push({ action: 'move', studentDocId: row.matchedStudentDocId!, ...base });
      } else if (row.bucket === 'match_archived') {
        if (res.rejectRestore) actions.push(asCreate());
        else actions.push({ action: 'restore_move', studentDocId: row.matchedStudentDocId!, ...base });
      } else if (row.bucket === 'name_suggest') {
        if (res.confirmedCandidateDocId) {
          confirmedDocIds.add(res.confirmedCandidateDocId);
          const ext = row.csv.studentId?.trim();
          if (ext) {
            actions.push({ action: 'backfill_move', studentDocId: res.confirmedCandidateDocId, externalId: ext, ...base });
          } else {
            actions.push({ action: 'move', studentDocId: res.confirmedCandidateDocId, ...base });
          }
        } else {
          actions.push(asCreate());
        }
      } else {
        actions.push(asCreate());
      }
    }

    let archiveGraduates = 0;
    let archiveLeavers = 0;
    for (const m of preview.missing) {
      if (confirmedDocIds.has(m.docId)) continue;
      const dis = missingRes[m.docId] ?? m.disposition;
      if (dis === 'keep') continue;
      actions.push({
        action: 'archive',
        studentDocId: m.docId,
        reason: dis === 'graduating' ? 'graduated' : 'left',
      });
      if (dis === 'graduating') archiveGraduates++;
      else archiveLeavers++;
    }

    const plan: RolloverPlan = {
      targetAcademicYear: preview.targetAcademicYear,
      actions,
      classesToDeactivate: Array.from(deactivateIds),
    };

    const counts = {
      moves: actions.filter((a) => a.action === 'move' || a.action === 'backfill_move').length,
      restores: actions.filter((a) => a.action === 'restore_move').length,
      creates: actions.filter((a) => a.action === 'create').length,
      backfills: actions.filter((a) => a.action === 'backfill_move').length,
      archives: archiveGraduates + archiveLeavers,
      archiveGraduates,
      archiveLeavers,
      classesToCreate: preview.classes.toCreate.length,
      classesToDeactivate: deactivateIds.size,
    };
    const bigArchive =
      counts.archives > 20 && counts.archives > 0.3 * Math.max(1, preview.stats.activeStudentCount);
    return { plan, counts, bigArchive };
  }, [preview, rowRes, missingRes, deactivateIds]);

  // ── Commit / undo ──────────────────────────────────────────────────────────

  const handleApply = async () => {
    if (!derived) return;
    setStep('applying');
    try {
      const importId = crypto.randomUUID();
      const res = await fetch('/api/rollover/commit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ importId, plan: derived.plan }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Import failed');
      }
      const data: RolloverCommitResult = await res.json();
      setResult(data);
      setStep('done');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Import failed — nothing may have been applied. Try again.', 'error');
      setStep('confirm');
    }
  };

  const handleUndo = async () => {
    const importId = undoTarget ?? result?.importId;
    if (!importId) return;
    setUndoing(true);
    try {
      const res = await fetch('/api/rollover/undo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ importId }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Undo failed');
      }
      const data = await res.json();
      toast(`Undo complete — ${data.reverted} students restored, ${data.createdDeleted} created students removed`, 'success');
      setShowUndoConfirm(false);
      setUndoTarget(null);
      setStep('upload');
      setPreview(null);
      setResult(null);
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Undo failed', 'error');
    } finally {
      setUndoing(false);
    }
  };

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div>
      <PageHeader
        eyebrow="Students"
        title="Annual Rollover Import"
        description="Upload your school system's class lists to move every student to their new class for the year"
        action={
          step !== 'upload' && step !== 'applying' ? (
            <Button variant="outline" onClick={() => { setStep('upload'); setPreview(null); }}>
              Start over
            </Button>
          ) : undefined
        }
      />

      {step === 'upload' && (
        <div className="max-w-2xl">
          <div className="bg-paper rounded-[var(--radius-lg)] shadow-card p-6 mb-6">
            <h3 className="font-bold text-ink mb-2">How it works</h3>
            <ol className="text-sm text-muted space-y-1.5 list-decimal ml-4 mb-4">
              <li>Export class lists from your school system (CASES21, Compass…) with student IDs.</li>
              <li>Paste them into the Lumi template — one row per student, returning and new.</li>
              <li>Returning students are matched by Student ID and moved to their new class — parent accounts stay linked.</li>
              <li>Students not in the file are flagged as graduated or left, for you to confirm.</li>
            </ol>
            <div className="bg-lumi-blue/10 border border-lumi-blue/20 rounded-[var(--radius-md)] px-4 py-3 mb-4 text-sm text-ink">
              <p className="mb-1"><strong>This does not grant next year&apos;s access</strong> — after importing, confirm the year on the{' '}
                <Link href="/settings?tab=renewals" className="text-section font-semibold hover:underline">Rollover page</Link>.</p>
              <p>Run it outside class time if you can — classes re-organise live.</p>
            </div>

            <div className="flex items-center gap-3 mb-4">
              <span className="text-sm font-semibold text-ink">School year:</span>
              <div className="w-32">
                <Select
                  options={[
                    { value: String(currentAcademicYear), label: String(currentAcademicYear) },
                    { value: String(currentAcademicYear + 1), label: String(currentAcademicYear + 1) },
                  ]}
                  value={String(targetYear)}
                  onChange={(v) => setTargetYear(Number(v))}
                />
              </div>
            </div>

            <input ref={fileInputRef} type="file" accept=".csv,.tsv,.txt" onChange={handleFileSelect} className="hidden" />
            <div className="flex items-center gap-4">
              <Button onClick={() => fileInputRef.current?.click()} disabled={loadingPreview}>
                {loadingPreview ? 'Analysing…' : 'Choose CSV File'}
              </Button>
              <button type="button" onClick={downloadTemplate} className="text-sm text-section hover:underline font-semibold">
                Download CSV Template
              </button>
            </div>
          </div>

          {recentImports.length > 0 && (
            <div className="bg-paper rounded-[var(--radius-lg)] shadow-card p-6">
              <h3 className="font-bold text-ink mb-3">Recent imports</h3>
              <div className="space-y-2">
                {recentImports.map((imp) => (
                  <div key={imp.id} className="flex items-center gap-3 text-sm">
                    <Badge variant={imp.status === 'applied' ? 'success' : imp.status === 'undone' ? 'default' : 'error'}>
                      {imp.status}
                    </Badge>
                    <span className="text-ink">
                      {imp.targetAcademicYear}
                      {imp.counts ? ` — moved ${imp.counts.moved}, created ${imp.counts.created}, archived ${imp.counts.archivedGraduates + imp.counts.archivedLeavers}` : ''}
                    </span>
                    <span className="text-muted">
                      {imp.performedAtIso ? new Date(imp.performedAtIso).toLocaleDateString('en-AU') : ''}
                      {imp.performedByName ? ` · ${imp.performedByName}` : ''}
                    </span>
                    {imp.status === 'applied' && (
                      <button
                        type="button"
                        onClick={() => { setUndoTarget(imp.id); setShowUndoConfirm(true); }}
                        className="ml-auto text-sm text-section hover:underline font-semibold"
                      >
                        Undo
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {step === 'review' && preview && derived && (
        <>
          {preview.outsideRenewalWindow && (
            <div className="flex items-center gap-2 mb-4 p-3 bg-lumi-orange/10 border border-lumi-orange/30 rounded-[var(--radius-lg)] text-sm text-ink">
              <Icon name="info" size={18} />
              It&apos;s outside the usual rollover window (October–February) — double-check the school year is right: {preview.targetAcademicYear}.
            </div>
          )}
          <ReviewStep
            preview={preview}
            classes={classes}
            rowRes={rowRes}
            setRowRes={setRowRes}
            missingRes={missingRes}
            setMissingRes={setMissingRes}
            deactivateIds={deactivateIds}
            setDeactivateIds={setDeactivateIds}
          />
          <div className="flex justify-end gap-3 mt-6">
            <Button variant="outline" onClick={() => { setStep('upload'); setPreview(null); }}>Back</Button>
            <Button onClick={() => setStep('confirm')}>Continue</Button>
          </div>
        </>
      )}

      {step === 'confirm' && preview && derived && (
        <div className="max-w-2xl">
          <div className="bg-paper rounded-[var(--radius-lg)] shadow-card p-6 mb-4">
            <h3 className="font-bold text-ink mb-4">Ready to apply</h3>
            <ul className="space-y-2 text-sm text-ink mb-5">
              <li className="flex items-center gap-2"><Icon name="swap_horiz" size={18} /> Move <strong>{derived.counts.moves}</strong> returning students to their new classes{derived.counts.backfills > 0 ? ` (${derived.counts.backfills} with Student IDs backfilled)` : ''}</li>
              <li className="flex items-center gap-2"><Icon name="person_add" size={18} /> Create <strong>{derived.counts.creates}</strong> new students</li>
              {derived.counts.restores > 0 && (
                <li className="flex items-center gap-2"><Icon name="restore" size={18} /> Restore <strong>{derived.counts.restores}</strong> archived students</li>
              )}
              <li className="flex items-center gap-2"><Icon name="inventory_2" size={18} /> Archive <strong>{derived.counts.archives}</strong> students ({derived.counts.archiveGraduates} graduating, {derived.counts.archiveLeavers} leaving)</li>
              {derived.counts.classesToCreate > 0 && (
                <li className="flex items-center gap-2"><Icon name="add_box" size={18} /> Create <strong>{derived.counts.classesToCreate}</strong> new classes</li>
              )}
              {derived.counts.classesToDeactivate > 0 && (
                <li className="flex items-center gap-2"><Icon name="visibility_off" size={18} /> Deactivate <strong>{derived.counts.classesToDeactivate}</strong> empty classes</li>
              )}
            </ul>

            <div className="bg-cream rounded-[var(--radius-md)] p-4 text-sm text-muted space-y-1.5 mb-4">
              <p>• Year levels come from your CSV — the Rollover (renewals) page won&apos;t bump them again for {preview.targetAcademicYear}.</p>
              <p>• This does <strong>not</strong> grant {preview.targetAcademicYear} access — confirm that on the Rollover page next.</p>
              <p>• Archived students keep their reading history and can be restored; parent accounts stay linked.</p>
              <p>• You can undo this import afterwards.</p>
            </div>

            {derived.bigArchive && (
              <label className="flex items-start gap-2.5 p-3 bg-error/5 border border-error/30 rounded-[var(--radius-md)] text-sm text-ink mb-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={archiveGuardChecked}
                  onChange={(e) => setArchiveGuardChecked(e.target.checked)}
                  className="mt-0.5 accent-section"
                />
                <span>
                  This will archive <strong>{derived.counts.archives}</strong> of your {preview.stats.activeStudentCount} active students.
                  I confirm these students have left the school — this isn&apos;t an incomplete export.
                </span>
              </label>
            )}
          </div>

          <div className="flex justify-end gap-3">
            <Button variant="outline" onClick={() => setStep('review')}>Back</Button>
            <Button onClick={handleApply} disabled={derived.bigArchive && !archiveGuardChecked}>
              Apply Rollover
            </Button>
          </div>
        </div>
      )}

      {step === 'applying' && (
        <div className="text-center py-16">
          <svg className="animate-spin mx-auto h-8 w-8 text-section mb-4" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <p className="text-sm text-muted">Applying the rollover — moving, creating and archiving students…</p>
        </div>
      )}

      {step === 'done' && result && (
        <div className="max-w-2xl">
          <div className="bg-paper rounded-[var(--radius-lg)] shadow-card p-6 text-center">
            <span className="inline-flex items-center justify-center text-success animate-success-pop mb-3">
              <Icon name="task_alt" size={56} />
            </span>
            <h3 className="text-lg font-bold text-ink mb-3">Rollover complete</h3>
            <div className="flex flex-wrap justify-center gap-2 mb-4">
              <Badge variant="success">{result.counts.moved} moved</Badge>
              <Badge variant="success">{result.counts.created} created</Badge>
              {result.counts.restored > 0 && <Badge variant="success">{result.counts.restored} restored</Badge>}
              <Badge>{result.counts.archivedGraduates + result.counts.archivedLeavers} archived</Badge>
              {result.counts.classesCreated > 0 && <Badge>{result.counts.classesCreated} classes created</Badge>}
              {result.counts.idBackfills > 0 && <Badge>{result.counts.idBackfills} IDs backfilled</Badge>}
            </div>

            {result.skipped.length > 0 && (
              <div className="text-left max-h-40 overflow-y-auto bg-cream rounded-[var(--radius-md)] p-3 mb-4">
                <p className="text-xs font-bold text-ink mb-1.5">{result.skipped.length} rows were skipped (data changed since the preview):</p>
                {result.skipped.map((s, i) => (
                  <p key={i} className="text-xs text-muted">Row {s.index + 1}: {s.note}</p>
                ))}
              </div>
            )}

            <div className="flex justify-center gap-3">
              <Button variant="outline" onClick={() => setShowUndoConfirm(true)}>Undo this import</Button>
              <Link href="/settings?tab=renewals">
                <Button>Next: grant {result ? preview?.targetAcademicYear ?? '' : ''} access →</Button>
              </Link>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={showUndoConfirm}
        onClose={() => { setShowUndoConfirm(false); setUndoTarget(null); }}
        onConfirm={handleUndo}
        title="Undo rollover import"
        description="This restores every student to their previous class, year level and status, removes students the import created, and re-activates archived students. Anything teachers changed after the import is left alone."
        confirmLabel="Undo import"
        variant="danger"
        loading={undoing}
      />
    </div>
  );
}
