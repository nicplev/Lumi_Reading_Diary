'use client';

import { useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { useImportStudents } from '@/lib/hooks/use-students';
import { useToast } from '@/components/lumi/toast';
import { SisImportInput, SisDetectionSummary } from '@/components/sis-import-input';
import { CASES21KitPanel } from '@/components/cases21-kit-panel';
import type { SisParseResult } from '@/lib/sis/detect';

interface CSVImportDialogProps {
  open: boolean;
  onClose: () => void;
  /** Render just the content + inline actions (no Modal shell), for hosting inside another modal. */
  embedded?: boolean;
}

interface ParsedRow {
  studentId?: string;
  firstName: string;
  lastName: string;
  className: string;
  yearLevel?: string;
  parentEmail?: string;
  readingLevel?: string;
  error?: string;
}

type Step = 'upload' | 'preview' | 'importing' | 'done';

export function CSVImportDialog({ open, onClose, embedded }: CSVImportDialogProps) {
  const { toast } = useToast();
  const importStudents = useImportStudents();

  const [step, setStep] = useState<Step>('upload');
  const [parsedRows, setParsedRows] = useState<ParsedRow[]>([]);
  const [parseResult, setParseResult] = useState<SisParseResult | null>(null);
  const [result, setResult] = useState<{ successCount: number; errorCount: number; errors: { row: number; message: string }[]; createdClassNames: string[] } | null>(null);

  const handleClose = () => {
    setStep('upload');
    setParsedRows([]);
    setParseResult(null);
    setResult(null);
    onClose();
  };

  const handleParsed = (result: SisParseResult) => {
    // Mirrors the API's cap — a whole-school roster belongs in the rollover
    // wizard, which is reviewable and undoable.
    if (result.rows.length > 500) {
      throw new Error(
        `Import at most 500 students at a time — that file has ${result.rows.length}. Split it, or use School Year Transition for a whole-school roster.`
      );
    }
    setParsedRows(
      result.rows.map((row) => ({
        ...row,
        error:
          !row.firstName || !row.lastName || !row.className
            ? 'Missing required fields'
            : undefined,
      }))
    );
    setParseResult(result);
    setStep('preview');
  };

  const handleImport = async () => {
    const validRows = parsedRows.filter((r) => !r.error);
    if (validRows.length === 0) {
      toast('No valid rows to import', 'error');
      return;
    }

    setStep('importing');
    try {
      const importResult = await importStudents.mutateAsync({
        rows: validRows.map(({ error: _, ...row }) => row as Record<string, string>),
      });
      setResult(importResult);
      setStep('done');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Import failed', 'error');
      setStep('preview');
    }
  };

  const errorCount = parsedRows.filter((r) => r.error).length;
  const validCount = parsedRows.length - errorCount;

  const footer =
    step === 'upload' ? (
      <Button variant="outline" onClick={handleClose}>Cancel</Button>
    ) : step === 'preview' ? (
      <>
        <Button variant="outline" onClick={() => { setStep('upload'); setParsedRows([]); setParseResult(null); }}>Back</Button>
        <Button onClick={handleImport} disabled={validCount === 0}>
          Import {validCount} Student{validCount !== 1 ? 's' : ''}
        </Button>
      </>
    ) : step === 'done' ? (
      <Button onClick={handleClose}>Done</Button>
    ) : undefined;

  const body = (
    <>
      {step === 'upload' && (
        <div className="py-2">
          <p className="text-sm text-muted mb-3">
            Upload the export from your school system, or paste it straight out of Excel. Lumi reads
            these columns: Student ID, First Name, Last Name, Class Name, Year Level, Parent Email,
            Reading Level.
          </p>
          <div className="bg-lumi-blue/10 border border-lumi-blue/20 rounded-[var(--radius-md)] px-4 py-3 mb-4 text-sm text-ink">
            <p className="mb-1"><strong>Required columns:</strong> First Name, Last Name, Class Name</p>
            <p><strong>Reading Level</strong> is optional and can match any format your school uses (e.g. A-Z, PM Benchmark, colours, numbered levels).</p>
          </div>

          <SisImportInput onParsed={handleParsed} fileButtonLabel="Choose file">
            <div className="mt-4">
              <button
                type="button"
                onClick={() => {
                  const csv = [
                    'Student ID,First Name,Last Name,Class Name,Year Level,Parent Email,Reading Level',
                    'S10001,Jane,Smith,3A,3,jane.parent@email.com,Level 12',
                    'S10002,Tom,Brown,3A,3,tom.parent@email.com,',
                    'S10003,Mia,Johnson,Prep B,Prep,mia.parent@email.com,Gold',
                  ].join('\n');
                  const blob = new Blob([csv], { type: 'text/csv' });
                  const url = URL.createObjectURL(blob);
                  const a = document.createElement('a');
                  a.href = url;
                  a.download = 'lumi_student_import_template.csv';
                  a.click();
                  URL.revokeObjectURL(url);
                }}
                className="text-sm text-section hover:underline font-semibold"
              >
                Download CSV template
              </button>
            </div>
          </SisImportInput>

          <div className="mt-5 pt-5 border-t border-rule">
            <CASES21KitPanel />
          </div>
        </div>
      )}

      {step === 'preview' && (
        <div>
          {parseResult && (
            <div className="mb-4">
              <SisDetectionSummary result={parseResult} />
            </div>
          )}
          <div className="flex items-center gap-3 mb-4">
            <Badge variant="success">{validCount} valid</Badge>
            {errorCount > 0 && <Badge variant="error">{errorCount} errors</Badge>}
          </div>
          <div className="overflow-x-auto max-h-80">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-rule">
                  <th className="px-2 py-2 text-left text-xs text-muted">#</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">First Name</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Last Name</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Class</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Year</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">ID</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Level</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Status</th>
                </tr>
              </thead>
              <tbody>
                {parsedRows.map((row, i) => (
                  <tr key={i} className={`border-b border-rule/50 ${row.error ? 'bg-error/5' : ''}`}>
                    <td className="px-2 py-1.5 text-muted">{i + 1}</td>
                    <td className="px-2 py-1.5">{row.firstName || <span className="text-error">missing</span>}</td>
                    <td className="px-2 py-1.5">{row.lastName || <span className="text-error">missing</span>}</td>
                    <td className="px-2 py-1.5">{row.className || <span className="text-error">missing</span>}</td>
                    <td className="px-2 py-1.5 text-muted">{row.yearLevel || '-'}</td>
                    <td className="px-2 py-1.5 text-muted">{row.studentId || '-'}</td>
                    <td className="px-2 py-1.5 text-muted">{row.readingLevel || '-'}</td>
                    <td className="px-2 py-1.5">
                      {row.error ? (
                        <Badge variant="error">{row.error}</Badge>
                      ) : (
                        <Badge variant="success">OK</Badge>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {step === 'importing' && (
        <div className="text-center py-8">
          <svg className="animate-spin mx-auto h-8 w-8 text-section mb-4" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <p className="text-sm text-muted">Importing students...</p>
        </div>
      )}

      {step === 'done' && result && (
        <div className="text-center py-6">
          <div className="mb-4 flex justify-center">
            {result.errorCount === 0 ? (
              <span className="inline-flex items-center justify-center text-success animate-success-pop">
                <Icon name="task_alt" size={56} />
              </span>
            ) : (
              <span className="inline-flex items-center justify-center text-lumi-orange"><Icon name="warning" size={56} /></span>
            )}
          </div>
          <h3 className="text-lg font-bold text-ink mb-2">Import Complete</h3>
          <div className="flex justify-center gap-4 mb-4">
            <Badge variant="success">{result.successCount} imported</Badge>
            {result.errorCount > 0 && <Badge variant="error">{result.errorCount} failed</Badge>}
          </div>
          {result.createdClassNames.length > 0 && (
            <p className="text-sm text-muted mb-2">
              Created new classes: {result.createdClassNames.join(', ')}
            </p>
          )}
          {result.errors.length > 0 && (
            <div className="mt-4 text-left max-h-32 overflow-y-auto">
              {result.errors.map((err, i) => (
                <p key={i} className="text-xs text-error">Row {err.row}: {err.message}</p>
              ))}
            </div>
          )}
        </div>
      )}
    </>
  );

  if (embedded) {
    return (
      <div>
        {body}
        {footer && (
          <div className="mt-5 pt-4 border-t border-rule flex justify-end gap-3">{footer}</div>
        )}
      </div>
    );
  }

  return (
    <Modal open={open} onClose={handleClose} title="Import Students from CSV" size="lg" footer={footer}>
      {body}
    </Modal>
  );
}
