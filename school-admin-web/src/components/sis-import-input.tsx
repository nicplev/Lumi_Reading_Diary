'use client';

import { useRef, useState } from 'react';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import {
  ACCEPTED_IMPORT_EXTENSIONS,
  ImportInputError,
  readImportFile,
  readPastedText,
} from '@/lib/sis/read-input';
import type { SisParseResult } from '@/lib/sis/detect';

interface SisImportInputProps {
  /** Called with the shaped rows once a file or paste parses successfully. */
  onParsed: (result: SisParseResult) => void | Promise<void>;
  /** Parent-owned busy state (e.g. while the preview API runs). */
  busy?: boolean;
  busyLabel?: string;
  fileButtonLabel?: string;
  /** Rendered under the input — template download links etc. */
  children?: React.ReactNode;
}

type Mode = 'file' | 'paste';

/**
 * The single entry point for roster data across both import flows.
 *
 * Admins get whatever their SIS gave them: a CSV, the .xlsx CASES21 writes when
 * you "export to Excel", or a selection pasted straight out of a spreadsheet
 * (which arrives tab-separated). All three land in the same
 * detect → adapt pipeline, so the review steps downstream see one shape.
 */
export function SisImportInput({
  onParsed,
  busy,
  busyLabel = 'Analysing…',
  fileButtonLabel = 'Choose file',
  children,
}: SisImportInputProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [mode, setMode] = useState<Mode>('file');
  const [pasted, setPasted] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [reading, setReading] = useState(false);

  const disabled = busy || reading;

  const handle = async (read: () => SisParseResult | Promise<SisParseResult>) => {
    setError(null);
    setReading(true);
    try {
      const result = await read();
      if (result.rows.length === 0) {
        throw new ImportInputError(
          'No student rows were found. Check the file still has its heading row (Student ID, First Name, Last Name, Class Name, Year Level, Parent Email).'
        );
      }
      await onParsed(result);
    } catch (e) {
      setError(
        e instanceof ImportInputError
          ? e.message
          : e instanceof Error
            ? e.message
            : 'That file could not be read'
      );
    } finally {
      setReading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  return (
    <div>
      <div className="flex gap-1 mb-4 p-1 bg-cream rounded-[var(--radius-md)] w-fit">
        {(['file', 'paste'] as Mode[]).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => { setMode(m); setError(null); }}
            className={`px-3 py-1.5 text-[13px] font-display font-bold rounded-[var(--radius-sm)] transition ${
              mode === m ? 'bg-paper text-ink shadow-card' : 'text-muted hover:text-ink'
            }`}
          >
            {m === 'file' ? 'Upload a file' : 'Paste from Excel'}
          </button>
        ))}
      </div>

      {mode === 'file' && (
        <div>
          <input
            ref={fileInputRef}
            type="file"
            accept={ACCEPTED_IMPORT_EXTENSIONS}
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) void handle(() => readImportFile(file));
            }}
          />
          <div className="flex items-center gap-4 flex-wrap">
            <Button onClick={() => fileInputRef.current?.click()} disabled={disabled} loading={disabled}>
              {disabled ? busyLabel : fileButtonLabel}
            </Button>
            <p className="text-sm text-muted">Excel (.xlsx), CSV, TSV or plain text.</p>
          </div>
        </div>
      )}

      {mode === 'paste' && (
        <div>
          <textarea
            value={pasted}
            onChange={(e) => setPasted(e.target.value)}
            rows={6}
            spellCheck={false}
            placeholder={
              'Select the rows in Excel (including the heading row), copy, and paste here.\n\nSTUDENT ID\tFIRST NAME\tLAST NAME\tCLASS NAME\tYEAR LEVEL\tPARENT EMAIL'
            }
            className="w-full font-mono text-[13px] border border-rule rounded-[var(--radius-md)] bg-paper p-3 text-ink placeholder:text-muted/70 focus:outline-none focus:ring-2 focus:ring-section/40"
          />
          <div className="flex items-center gap-4 mt-3 flex-wrap">
            <Button
              onClick={() => void handle(() => readPastedText(pasted))}
              disabled={disabled || pasted.trim() === ''}
              loading={disabled}
            >
              {disabled ? busyLabel : 'Read pasted rows'}
            </Button>
            {pasted.trim() !== '' && (
              <button
                type="button"
                onClick={() => { setPasted(''); setError(null); }}
                className="text-sm text-muted hover:text-ink"
              >
                Clear
              </button>
            )}
          </div>
        </div>
      )}

      {error && (
        <div className="flex items-start gap-2 mt-4 p-3 bg-error/5 border border-error/30 rounded-[var(--radius-md)] text-sm text-ink">
          <span className="text-error shrink-0 mt-0.5"><Icon name="error" size={18} /></span>
          <span>{error}</span>
        </div>
      )}

      {children}
    </div>
  );
}

/**
 * What we made of the file — shown after parsing so the admin can see the
 * format was understood and, crucially, what was skipped before they commit.
 */
export function SisDetectionSummary({ result }: { result: SisParseResult }) {
  const { detection, rows, notes } = result;
  const unrecognised = detection.format === 'unknown' || detection.format === 'generic';

  return (
    <div className="bg-cream rounded-[var(--radius-md)] p-4 text-sm">
      <div className="flex items-center gap-2 flex-wrap mb-1">
        <Badge variant={unrecognised ? 'default' : 'success'}>{detection.label}</Badge>
        <span className="text-ink font-semibold">
          {rows.length} student{rows.length === 1 ? '' : 's'} read
        </span>
      </div>

      {detection.missingFields.length > 0 && (
        <p className="text-muted mt-1.5">
          No column found for: {detection.missingFields.map(fieldLabel).join(', ')}.
          {detection.missingFields.some((f) => f === 'firstName' || f === 'lastName' || f === 'className')
            ? ' First Name, Last Name and Class Name are required.'
            : ' Those values will be left blank.'}
        </p>
      )}

      {notes.length > 0 && (
        <ul className="mt-2 space-y-1">
          {notes.map((note) => (
            <li key={note.code} className="flex items-start gap-1.5 text-muted">
              <span className="shrink-0 mt-0.5"><Icon name="info" size={14} /></span>
              <span>{note.message}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function fieldLabel(field: string): string {
  switch (field) {
    case 'studentId': return 'Student ID';
    case 'firstName': return 'First Name';
    case 'lastName': return 'Last Name';
    case 'className': return 'Class Name';
    case 'yearLevel': return 'Year Level';
    case 'parentEmail': return 'Parent Email';
    case 'readingLevel': return 'Reading Level';
    default: return field;
  }
}
