'use client';

import { useMemo, useState } from 'react';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { Select } from '@/components/lumi/select';
import { Tabs } from '@/components/lumi/tabs';
import type { ClassifiedRow, MissingStudent } from '@/lib/rollover/classify';
import type { RolloverPreview } from '@/lib/firestore/rollover';

export interface RowResolution {
  excluded?: boolean;
  overrideClassName?: string;
  /** name_suggest: confirmed existing student docId; undefined = create new. */
  confirmedCandidateDocId?: string;
  /** match_archived: create a new student instead of restoring. */
  rejectRestore?: boolean;
}

export type MissingDisposition = 'graduating' | 'leaver' | 'keep';

interface ClassOption {
  id: string;
  name: string;
  yearLevel: string | null;
}

interface ReviewStepProps {
  preview: RolloverPreview;
  classes: ClassOption[];
  rowRes: Record<number, RowResolution>;
  setRowRes: React.Dispatch<React.SetStateAction<Record<number, RowResolution>>>;
  missingRes: Record<string, MissingDisposition>;
  setMissingRes: React.Dispatch<React.SetStateAction<Record<string, MissingDisposition>>>;
  deactivateIds: Set<string>;
  setDeactivateIds: React.Dispatch<React.SetStateAction<Set<string>>>;
}

export function ReviewStep({
  preview, classes, rowRes, setRowRes, missingRes, setMissingRes, deactivateIds, setDeactivateIds,
}: ReviewStepProps) {
  const [tab, setTab] = useState('returning');

  const returning = useMemo(() => preview.rows.filter((r) => r.bucket === 'match' || r.bucket === 'match_archived'), [preview]);
  const needsReview = useMemo(() => preview.rows.filter((r) => r.bucket === 'name_suggest' || r.bucket === 'error'), [preview]);
  const newRows = useMemo(() => preview.rows.filter((r) => r.bucket === 'new'), [preview]);

  // Confirmed suggestions pull students off the missing list live.
  const confirmedDocIds = useMemo(() => {
    const set = new Set<string>();
    for (const r of Object.values(rowRes)) {
      if (r.confirmedCandidateDocId) set.add(r.confirmedCandidateDocId);
    }
    return set;
  }, [rowRes]);
  const missing = useMemo(
    () => preview.missing.filter((m) => !confirmedDocIds.has(m.docId)),
    [preview, confirmedDocIds]
  );

  const updateRow = (rowIndex: number, patch: Partial<RowResolution>) =>
    setRowRes((prev) => ({ ...prev, [rowIndex]: { ...prev[rowIndex], ...patch } }));

  // Class override options: every active class + every class the CSV creates.
  const classNameOptions = useMemo(() => {
    const names = new Map<string, string>(); // key → display
    for (const c of classes) names.set(c.name.trim().toLowerCase(), c.name);
    for (const c of preview.classes.toCreate) {
      const key = c.name.trim().toLowerCase();
      if (!names.has(key)) names.set(key, `${c.name} (new)`);
    }
    return Array.from(names.entries()).map(([key, label]) => ({ value: key, label }));
  }, [classes, preview]);
  const classValueFor = (row: ClassifiedRow) =>
    (rowRes[row.rowIndex]?.overrideClassName ?? row.csv.className).trim().toLowerCase();
  const displayNameFor = (key: string) =>
    classNameOptions.find((o) => o.value === key)?.label.replace(' (new)', '') ?? key;

  const rowFlags = (row: ClassifiedRow) => (
    <div className="flex flex-wrap gap-1">
      {row.bucket === 'match_archived' && !rowRes[row.rowIndex]?.rejectRestore && (
        <Badge variant="info">Will be restored</Badge>
      )}
      {row.classChanged && (
        <Badge>{row.classChanged.fromClassName ?? 'Unassigned'} → {row.classChanged.toClassName}</Badge>
      )}
      {row.yearLevelChanged && (
        <Badge>{row.yearLevelChanged.from ?? '—'} → {row.yearLevelChanged.to}</Badge>
      )}
      {row.offLadder && <Badge variant="warning">Off-pattern year</Badge>}
      {row.unknownYearLevel && <Badge variant="warning">Unusual year label</Badge>}
      {row.nameMismatch && <Badge variant="warning">Was &quot;{row.nameMismatch.storedName}&quot;</Badge>}
    </div>
  );

  const excludedClass = (excluded?: boolean) => (excluded ? 'opacity-40' : '');

  return (
    <div>
      {/* Guard banners */}
      {preview.classes.wholeClassMissing.length > 0 && (
        <div className="flex items-start gap-2 mb-4 p-3 bg-error/5 border border-error/30 rounded-[var(--radius-lg)] text-sm text-ink">
          <Icon name="warning" size={18} />
          <div>
            <strong>Whole classes are missing from your file:</strong>{' '}
            {preview.classes.wholeClassMissing.map((c) => `${c.name} (${c.memberCount} students)`).join(', ')}.
            If they should stay, check the export before continuing — otherwise all their students will be archived.
          </div>
        </div>
      )}
      {preview.stats.idlessRows > 0 && (
        <div className="flex items-start gap-2 mb-4 p-3 bg-lumi-orange/10 border border-lumi-orange/30 rounded-[var(--radius-lg)] text-sm text-ink">
          <Icon name="info" size={18} />
          <div>
            <strong>{preview.stats.idlessRows} rows have no Student ID.</strong> They can only be matched by
            name — add IDs from your school system where possible so future rollovers match automatically.
          </div>
        </div>
      )}

      <Tabs
        tabs={[
          { id: 'returning', label: 'Returning', count: returning.length },
          { id: 'review', label: 'Needs review', count: needsReview.length },
          { id: 'new', label: 'New students', count: newRows.length },
          { id: 'missing', label: 'Missing', count: missing.length },
          { id: 'classes', label: 'Classes', count: preview.classes.toCreate.length + preview.classes.emptyAfterImport.length },
        ]}
        activeTab={tab}
        onChange={setTab}
      />

      {tab === 'returning' && (
        <ReviewTable
          headers={['Student', 'ID', 'Class', 'Year', 'Changes', 'Include']}
          empty="No returning students matched — check that your CSV has Student IDs."
        >
          {returning.map((row) => {
            const res = rowRes[row.rowIndex] ?? {};
            return (
              <tr key={row.rowIndex} className={`border-b border-rule/50 ${excludedClass(res.excluded)}`}>
                <td className="p-2.5 font-medium text-ink">
                  {row.csv.firstName} {row.csv.lastName}
                  {row.bucket === 'match_archived' && res.rejectRestore && (
                    <span className="block text-xs text-muted">Will be created as a new student</span>
                  )}
                </td>
                <td className="p-2.5 text-muted">{row.csv.studentId ?? '—'}</td>
                <td className="p-2.5 min-w-40">
                  <Select
                    options={classNameOptions}
                    value={classValueFor(row)}
                    onChange={(v) => updateRow(row.rowIndex, { overrideClassName: displayNameFor(v) })}
                  />
                </td>
                <td className="p-2.5 text-ink">{row.csv.yearLevel ?? '—'}</td>
                <td className="p-2.5">
                  {rowFlags(row)}
                  {row.bucket === 'match_archived' && (
                    <button
                      type="button"
                      className="block mt-1 text-xs text-section hover:underline font-semibold"
                      onClick={() => updateRow(row.rowIndex, { rejectRestore: !res.rejectRestore })}
                    >
                      {res.rejectRestore ? 'Restore the archived student instead' : 'Different child? Create new instead'}
                    </button>
                  )}
                </td>
                <td className="p-2.5 text-center">
                  <input
                    type="checkbox"
                    checked={!res.excluded}
                    onChange={(e) => updateRow(row.rowIndex, { excluded: !e.target.checked })}
                    className="accent-section"
                  />
                </td>
              </tr>
            );
          })}
        </ReviewTable>
      )}

      {tab === 'review' && (
        <div className="space-y-3">
          {needsReview.length === 0 && (
            <p className="text-sm text-muted py-8 text-center">Nothing needs review — every row matched cleanly.</p>
          )}
          {needsReview.map((row) => {
            const res = rowRes[row.rowIndex] ?? {};
            if (row.bucket === 'error') {
              return (
                <div key={row.rowIndex} className="p-4 bg-error/5 border border-error/30 rounded-[var(--radius-lg)]">
                  <div className="flex items-center gap-2 text-sm">
                    <Badge variant="error">Row {row.rowIndex}</Badge>
                    <span className="font-medium text-ink">{row.csv.firstName} {row.csv.lastName}</span>
                    <span className="text-muted">{row.error}</span>
                  </div>
                  <p className="text-xs text-muted mt-1">This row is excluded — fix the CSV and re-upload, or continue without it.</p>
                </div>
              );
            }
            return (
              <div key={row.rowIndex} className={`p-4 bg-paper rounded-[var(--radius-lg)] shadow-card ${excludedClass(res.excluded)}`}>
                <div className="flex flex-wrap items-center gap-2 mb-2">
                  <span className="font-semibold text-ink">{row.csv.firstName} {row.csv.lastName}</span>
                  <span className="text-sm text-muted">→ {row.csv.className}{row.csv.yearLevel ? `, Year ${row.csv.yearLevel}` : ''}</span>
                  {row.csv.studentId && <Badge>ID {row.csv.studentId}</Badge>}
                  <label className="ml-auto text-xs text-muted flex items-center gap-1.5 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={!res.excluded}
                      onChange={(e) => updateRow(row.rowIndex, { excluded: !e.target.checked })}
                      className="accent-section"
                    />
                    Include
                  </label>
                </div>
                {row.warnings.length > 0 && (
                  <div className="mb-2">
                    {row.warnings.map((w, i) => (
                      <p key={i} className="text-xs text-muted flex items-center gap-1"><Icon name="info" size={13} /> {w}</p>
                    ))}
                  </div>
                )}
                <p className="text-sm text-ink mb-2">
                  Is this an existing student? Confirming links their reading history{row.csv.studentId ? ' and saves the Student ID for future rollovers' : ''}.
                </p>
                <div className="flex flex-wrap gap-2">
                  {(row.candidates ?? []).map((cand) => (
                    <button
                      key={cand.docId}
                      type="button"
                      onClick={() =>
                        updateRow(row.rowIndex, {
                          confirmedCandidateDocId: res.confirmedCandidateDocId === cand.docId ? undefined : cand.docId,
                        })
                      }
                      className={`px-3 py-2 rounded-[var(--radius-md)] border text-sm text-left transition-colors ${
                        res.confirmedCandidateDocId === cand.docId
                          ? 'border-section bg-section/10 text-ink font-semibold'
                          : 'border-rule bg-paper text-ink hover:bg-cream'
                      }`}
                    >
                      <span className="block font-semibold">
                        {res.confirmedCandidateDocId === cand.docId ? '✓ ' : ''}{cand.name}
                      </span>
                      <span className="block text-xs text-muted">
                        {cand.className ?? 'Unassigned'}{cand.yearLevel ? ` · Year ${cand.yearLevel}` : ''} · no Student ID on file
                        {cand.sharedName ? ' · shares this name' : ''}
                      </span>
                    </button>
                  ))}
                  <button
                    type="button"
                    onClick={() => updateRow(row.rowIndex, { confirmedCandidateDocId: undefined })}
                    className={`px-3 py-2 rounded-[var(--radius-md)] border text-sm transition-colors ${
                      !res.confirmedCandidateDocId
                        ? 'border-section bg-section/10 text-ink font-semibold'
                        : 'border-rule bg-paper text-ink hover:bg-cream'
                    }`}
                  >
                    {!res.confirmedCandidateDocId ? '✓ ' : ''}Create as new student
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {tab === 'new' && (
        <ReviewTable
          headers={['Student', 'ID', 'Class', 'Year', 'Parent Email', 'Include']}
          empty="No new students in this file."
        >
          {newRows.map((row) => {
            const res = rowRes[row.rowIndex] ?? {};
            return (
              <tr key={row.rowIndex} className={`border-b border-rule/50 ${excludedClass(res.excluded)}`}>
                <td className="p-2.5 font-medium text-ink">{row.csv.firstName} {row.csv.lastName}</td>
                <td className="p-2.5 text-muted">{row.csv.studentId ?? '—'}</td>
                <td className="p-2.5 text-ink">{row.csv.className}</td>
                <td className="p-2.5 text-ink">{row.csv.yearLevel ?? '—'}</td>
                <td className="p-2.5 text-muted">{row.csv.parentEmail ?? '—'}</td>
                <td className="p-2.5 text-center">
                  <input
                    type="checkbox"
                    checked={!res.excluded}
                    onChange={(e) => updateRow(row.rowIndex, { excluded: !e.target.checked })}
                    className="accent-section"
                  />
                </td>
              </tr>
            );
          })}
        </ReviewTable>
      )}

      {tab === 'missing' && (
        <>
          <p className="text-sm text-muted mb-3">
            These active students aren&apos;t in your file. Graduating and leaving students are archived —
            hidden from classes and the app, reading history kept, restorable any time.
          </p>
          <ReviewTable headers={['Student', 'ID', 'Class', 'Year', 'What happened?']} empty="Everyone is accounted for — no students missing from the file.">
            {missing.map((m) => (
              <MissingRow key={m.docId} m={m} value={missingRes[m.docId] ?? m.disposition} onChange={(v) => setMissingRes((prev) => ({ ...prev, [m.docId]: v }))} />
            ))}
          </ReviewTable>
        </>
      )}

      {tab === 'classes' && (
        <div className="space-y-5">
          {preview.classes.toCreate.length > 0 && (
            <div>
              <h4 className="font-bold text-ink mb-2">Will be created</h4>
              <div className="flex flex-wrap gap-2">
                {preview.classes.toCreate.map((c) => (
                  <Badge key={c.name}>
                    {c.name}{c.yearLevel ? ` (Year ${c.yearLevel})` : ''} · {c.rowCount} students
                    {c.yearLevelConflict ? ' · mixed year levels' : ''}
                  </Badge>
                ))}
              </div>
              {preview.classes.inactiveNameClash.length > 0 && (
                <p className="text-xs text-muted mt-2">
                  Note: {preview.classes.inactiveNameClash.map((c) => c.name).join(', ')} previously existed and
                  {preview.classes.inactiveNameClash.length === 1 ? ' was' : ' were'} deactivated — a fresh class will be created.
                </p>
              )}
            </div>
          )}

          {preview.classes.emptyAfterImport.length > 0 && (
            <div>
              <h4 className="font-bold text-ink mb-1">Empty after this import</h4>
              <p className="text-sm text-muted mb-2">
                Every student moves out of these classes and nobody new joins them — usually a renamed class.
                Tick to deactivate (history is kept; this can be undone).
              </p>
              <div className="space-y-1.5">
                {preview.classes.emptyAfterImport.map((c) => (
                  <label key={c.docId} className="flex items-center gap-2.5 text-sm text-ink cursor-pointer">
                    <input
                      type="checkbox"
                      checked={deactivateIds.has(c.docId)}
                      onChange={(e) =>
                        setDeactivateIds((prev) => {
                          const next = new Set(prev);
                          if (e.target.checked) next.add(c.docId);
                          else next.delete(c.docId);
                          return next;
                        })
                      }
                      className="accent-section"
                    />
                    Deactivate <strong>{c.name}</strong> ({c.memberCount} students currently)
                  </label>
                ))}
              </div>
            </div>
          )}

          {preview.classes.toCreate.length === 0 && preview.classes.emptyAfterImport.length === 0 && (
            <p className="text-sm text-muted py-8 text-center">No class changes — every class in the file already exists.</p>
          )}
        </div>
      )}
    </div>
  );
}

function ReviewTable({ headers, empty, children }: { headers: string[]; empty: string; children: React.ReactNode }) {
  const hasRows = Array.isArray(children) ? children.length > 0 : !!children;
  if (!hasRows) return <p className="text-sm text-muted py-8 text-center">{empty}</p>;
  return (
    <div className="overflow-x-auto max-h-[32rem] overflow-y-auto bg-paper rounded-[var(--radius-lg)] shadow-card">
      <table className="w-full text-sm">
        <thead className="sticky top-0 bg-paper">
          <tr className="border-b border-rule">
            {headers.map((h) => (
              <th key={h} className="p-2.5 text-left text-xs font-bold text-muted uppercase tracking-wide">{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

function MissingRow({ m, value, onChange }: { m: MissingStudent; value: MissingDisposition; onChange: (v: MissingDisposition) => void }) {
  return (
    <tr className={`border-b border-rule/50 ${value === 'keep' ? 'opacity-60' : ''}`}>
      <td className="p-2.5 font-medium text-ink">
        {m.name}
        {m.suggestedInRows.length > 0 && (
          <span className="block text-xs text-muted">
            May match row {m.suggestedInRows.join(', ')} — confirm on the &quot;Needs review&quot; tab instead
          </span>
        )}
      </td>
      <td className="p-2.5 text-muted">{m.externalId ?? '—'}</td>
      <td className="p-2.5 text-ink">{m.className ?? 'Unassigned'}</td>
      <td className="p-2.5 text-ink">{m.effectiveYearLevel ?? '—'}</td>
      <td className="p-2.5 min-w-44">
        <Select
          options={[
            { value: 'graduating', label: 'Graduated (archive)' },
            { value: 'leaver', label: 'Left school (archive)' },
            { value: 'keep', label: 'Keep active' },
          ]}
          value={value}
          onChange={(v) => onChange(v as MissingDisposition)}
        />
      </td>
    </tr>
  );
}
