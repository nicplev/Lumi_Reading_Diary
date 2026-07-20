'use client';

import { useState, useRef } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { useImportStudents } from '@/lib/hooks/use-students';
import { useToast } from '@/components/lumi/toast';
import { parseCSV, matchHeader } from '@/lib/csv';

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
  parentEmail?: string;
  readingLevel?: string;
  error?: string;
}

type Step = 'upload' | 'preview' | 'importing' | 'done';

export function CSVImportDialog({ open, onClose, embedded }: CSVImportDialogProps) {
  const { toast } = useToast();
  const importStudents = useImportStudents();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [step, setStep] = useState<Step>('upload');
  const [parsedRows, setParsedRows] = useState<ParsedRow[]>([]);
  const [headerMapping, setHeaderMapping] = useState<Record<string, string>>({});
  const [result, setResult] = useState<{ successCount: number; errorCount: number; errors: { row: number; message: string }[]; createdClassNames: string[] } | null>(null);

  const handleClose = () => {
    setStep('upload');
    setParsedRows([]);
    setHeaderMapping({});
    setResult(null);
    onClose();
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (ev) => {
      const text = ev.target?.result as string;
      const { headers, rows } = parseCSV(text);

      // Map headers
      const mapping: Record<string, string> = {};
      headers.forEach((h, i) => {
        const field = matchHeader(h);
        if (field) mapping[String(i)] = field;
      });
      setHeaderMapping(mapping);

      // Parse rows
      const parsed: ParsedRow[] = rows.map((row) => {
        const obj: Record<string, string> = {};
        headers.forEach((_, i) => {
          const field = mapping[String(i)];
          if (field) obj[field] = row[i] ?? '';
        });

        const parsed: ParsedRow = {
          studentId: obj.studentId || undefined,
          firstName: obj.firstName ?? '',
          lastName: obj.lastName ?? '',
          className: obj.className ?? '',
          parentEmail: obj.parentEmail || undefined,
          readingLevel: obj.readingLevel || undefined,
        };

        // Validate
        if (!parsed.firstName || !parsed.lastName || !parsed.className) {
          parsed.error = 'Missing required fields';
        }

        return parsed;
      });

      setParsedRows(parsed);
      setStep('preview');
    };
    reader.readAsText(file);
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
        <Button variant="outline" onClick={() => { setStep('upload'); setParsedRows([]); }}>Back</Button>
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
        <div className="text-center py-8">
          <div className="flex justify-center mb-4 text-muted/50"><Icon name="upload_file" size={48} /></div>
          <p className="text-sm text-muted mb-3">
            Upload a CSV file with columns: Student ID, First Name, Last Name, Class Name, Parent Email, Reading Level.
          </p>
          <div className="bg-lumi-blue/10 border border-lumi-blue/20 rounded-[var(--radius-md)] px-4 py-3 mb-4 text-sm text-ink">
            <p className="mb-1"><strong>Required columns:</strong> First Name, Last Name, Class Name</p>
            <p><strong>Reading Level</strong> is optional and can match any format your school uses (e.g. A-Z, PM Benchmark, colours, numbered levels).</p>
          </div>
          <input
            ref={fileInputRef}
            type="file"
            accept=".csv,.tsv,.txt"
            onChange={handleFileSelect}
            className="hidden"
          />
          <div className="flex flex-col items-center gap-3">
            <Button onClick={() => fileInputRef.current?.click()}>Choose File</Button>
            <button
              type="button"
              onClick={() => {
                const csv = [
                  'Student ID,First Name,Last Name,Class Name,Parent Email,Reading Level',
                  'S10001,Jane,Smith,3A,jane.parent@email.com,Level 12',
                  'S10002,Tom,Brown,3A,tom.parent@email.com,',
                  'S10003,Mia,Johnson,3B,mia.parent@email.com,Gold',
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
              Download CSV Template
            </button>
          </div>
        </div>
      )}

      {step === 'preview' && (
        <div>
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
