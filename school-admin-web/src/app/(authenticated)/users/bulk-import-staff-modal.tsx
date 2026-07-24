'use client';

import { useState, useRef } from 'react';
import { toCsv } from '@/lib/csv-export';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { useImportStaff, type StaffImportResult } from '@/lib/hooks/use-users';
import { useToast } from '@/components/lumi/toast';

interface BulkImportStaffModalProps {
  open: boolean;
  onClose: () => void;
}

interface ParsedRow {
  fullName: string;
  email: string;
  role: string;
  roleLabel: string;
  error?: string;
}

type Step = 'upload' | 'preview' | 'importing' | 'done';

const HEADER_ALIASES: Record<string, string[]> = {
  fullName: ['name', 'full name', 'fullname', 'full_name', 'staff name', 'teacher name'],
  email: ['email', 'e-mail', 'email address', 'email_address', 'mail'],
  role: ['role', 'type', 'position', 'access', 'access level'],
};

function matchHeader(header: string): string | null {
  const normalized = header.toLowerCase().trim();
  for (const [field, aliases] of Object.entries(HEADER_ALIASES)) {
    if (aliases.includes(normalized)) return field;
  }
  return null;
}

function parseCSV(text: string): { headers: string[]; rows: string[][] } {
  const lines = text.split(/\r?\n/).filter((line) => line.trim());
  if (lines.length === 0) return { headers: [], rows: [] };

  const delimiter = lines[0].includes('\t') ? '\t' : ',';
  const headers = lines[0].split(delimiter).map((h) => h.trim().replace(/^["']|["']$/g, ''));
  const rows = lines.slice(1).map((line) =>
    line.split(delimiter).map((cell) => cell.trim().replace(/^["']|["']$/g, ''))
  );

  return { headers, rows };
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Mirror of the server's parseRole for client-side preview validation. */
function normaliseRole(raw: string): { value: string; label: string } | null {
  const v = raw.toLowerCase().trim();
  if (!v) return { value: 'teacher', label: 'Teacher' };
  if (['teacher', 'teach', 'staff'].includes(v)) return { value: 'teacher', label: 'Teacher' };
  if (['admin', 'administrator', 'school admin', 'schooladmin'].includes(v)) {
    return { value: 'admin', label: 'Admin' };
  }
  return null;
}

export function BulkImportStaffModal({ open, onClose }: BulkImportStaffModalProps) {
  const { toast } = useToast();
  const importStaff = useImportStaff();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [step, setStep] = useState<Step>('upload');
  const [parsedRows, setParsedRows] = useState<ParsedRow[]>([]);
  const [customMessage, setCustomMessage] = useState('');
  const [result, setResult] = useState<StaffImportResult | null>(null);

  const handleClose = () => {
    setStep('upload');
    setParsedRows([]);
    setCustomMessage('');
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

      const mapping: Record<string, string> = {};
      headers.forEach((h, i) => {
        const field = matchHeader(h);
        if (field) mapping[String(i)] = field;
      });

      const parsed: ParsedRow[] = rows.map((row) => {
        const obj: Record<string, string> = {};
        headers.forEach((_, i) => {
          const field = mapping[String(i)];
          if (field) obj[field] = row[i] ?? '';
        });

        const fullName = (obj.fullName ?? '').trim();
        const email = (obj.email ?? '').trim();
        const rawRole = (obj.role ?? '').trim();
        const role = normaliseRole(rawRole);

        const parsedRow: ParsedRow = {
          fullName,
          email,
          role: role?.value ?? rawRole,
          roleLabel: role?.label ?? rawRole,
        };

        if (!fullName || !email) {
          parsedRow.error = 'Missing name or email';
        } else if (!EMAIL_RE.test(email)) {
          parsedRow.error = 'Invalid email';
        } else if (!role) {
          parsedRow.error = `Invalid role "${rawRole}"`;
        }

        return parsedRow;
      });

      setParsedRows(parsed);
      setStep('preview');
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  const handleImport = async () => {
    const validRows = parsedRows.filter((r) => !r.error);
    if (validRows.length === 0) {
      toast('No valid rows to import', 'error');
      return;
    }

    setStep('importing');
    try {
      const importResult = await importStaff.mutateAsync({
        rows: validRows.map((r) => ({ fullName: r.fullName, email: r.email, role: r.role })),
        customMessage: customMessage.trim() || undefined,
      });
      setResult(importResult);
      setStep('done');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Import failed', 'error');
      setStep('preview');
    }
  };

  const copy = async (text: string, label: string) => {
    try {
      await navigator.clipboard.writeText(text);
      toast(`${label} copied`, 'success');
    } catch {
      toast('Failed to copy', 'error');
    }
  };

  const downloadCredentialsCSV = () => {
    if (!result) return;
    // Formula-safe: this file carries temporary passwords, so a formula
    // smuggled in via a staff name must never be able to read the password
    // column out to an attacker when an admin opens it.
    const rows = toCsv([
      ['Name', 'Email', 'Role', 'Temporary Password'],
      ...result.created.map((c) => [
        c.fullName,
        c.email,
        c.role === 'schoolAdmin' ? 'Admin' : 'Teacher',
        c.tempPassword,
      ]),
    ]);
    const blob = new Blob([rows], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'lumi_staff_credentials.csv';
    a.click();
    URL.revokeObjectURL(url);
  };

  const errorCount = parsedRows.filter((r) => r.error).length;
  const validCount = parsedRows.length - errorCount;

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Import Staff from CSV"
      size="lg"
      footer={
        step === 'upload' ? (
          <Button variant="outline" onClick={handleClose}>Cancel</Button>
        ) : step === 'preview' ? (
          <>
            <Button variant="outline" onClick={() => { setStep('upload'); setParsedRows([]); }}>Back</Button>
            <Button onClick={handleImport} disabled={validCount === 0}>
              Import {validCount} Staff Member{validCount !== 1 ? 's' : ''}
            </Button>
          </>
        ) : step === 'done' ? (
          <Button onClick={handleClose}>Done</Button>
        ) : undefined
      }
    >
      {step === 'upload' && (
        <div className="py-2">
          <div className="text-center mb-4">
            <div className="flex justify-center mb-3 text-muted/50"><Icon name="group" size={48} /></div>
            <p className="text-sm text-muted">
              Upload a CSV with columns: <strong>Name, Email, Role</strong>.
            </p>
          </div>
          <div className="bg-lumi-blue/10 border border-lumi-blue/20 rounded-[var(--radius-md)] px-4 py-3 mb-4 text-sm text-ink">
            <p className="mb-1"><strong>Role</strong> must be <code>teacher</code> or <code>admin</code> (blank defaults to teacher).</p>
            <p>Each staff member gets an auto-generated temporary password and an email with login instructions. You can view or re-send these from the Users list.</p>
          </div>

          <label className="block text-xs font-semibold uppercase tracking-wide text-muted mb-1">
            Optional note to include in the email
          </label>
          <textarea
            value={customMessage}
            onChange={(e) => setCustomMessage(e.target.value)}
            rows={2}
            maxLength={2000}
            placeholder="e.g. Welcome to the team! Reach out to the office if you need help logging in."
            className="w-full rounded-[var(--radius-md)] border border-rule px-3 py-2 text-sm text-ink focus:outline-none focus:ring-2 focus:ring-section/40 mb-4"
          />

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
                  'Name,Email,Role',
                  'Jane Smith,jane.smith@school.edu,teacher',
                  'Tom Brown,tom.brown@school.edu,teacher',
                  'Alex Lee,alex.lee@school.edu,admin',
                ].join('\n');
                const blob = new Blob([csv], { type: 'text/csv' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'lumi_staff_import_template.csv';
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
                  <th className="px-2 py-2 text-left text-xs text-muted">Name</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Email</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Role</th>
                  <th className="px-2 py-2 text-left text-xs text-muted">Status</th>
                </tr>
              </thead>
              <tbody>
                {parsedRows.map((row, i) => (
                  <tr key={i} className={`border-b border-rule/50 ${row.error ? 'bg-error/5' : ''}`}>
                    <td className="px-2 py-1.5 text-muted">{i + 1}</td>
                    <td className="px-2 py-1.5">{row.fullName || <span className="text-error">missing</span>}</td>
                    <td className="px-2 py-1.5">{row.email || <span className="text-error">missing</span>}</td>
                    <td className="px-2 py-1.5 text-muted">{row.roleLabel || '-'}</td>
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
          <p className="text-sm text-muted">Creating staff accounts…</p>
        </div>
      )}

      {step === 'done' && result && (
        <div className="py-2">
          <div className="text-center mb-4">
            <div className="mb-3 flex justify-center">
              {result.errorCount === 0 ? (
                <span className="inline-flex items-center justify-center text-success animate-success-pop">
                  <Icon name="task_alt" size={56} />
                </span>
              ) : (
                <span className="inline-flex items-center justify-center text-lumi-orange"><Icon name="warning" size={56} /></span>
              )}
            </div>
            <h3 className="text-lg font-bold text-ink mb-2">Import Complete</h3>
            <div className="flex justify-center gap-4 mb-2">
              <Badge variant="success">{result.successCount} created</Badge>
              {result.errorCount > 0 && <Badge variant="error">{result.errorCount} failed</Badge>}
            </div>
            {result.created.length > 0 && (
              <p className="text-sm text-muted">
                Login emails sent to {result.created.length} staff member{result.created.length !== 1 ? 's' : ''}.
              </p>
            )}
          </div>

          {result.created.length > 0 && (
            <div className="mb-4">
              <div className="flex items-center justify-between mb-2">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted">Temporary passwords</p>
                <button onClick={downloadCredentialsCSV} className="text-sm text-section hover:underline font-semibold">
                  Download credentials CSV
                </button>
              </div>
              <div className="bg-warning/5 border border-warning/20 rounded-[var(--radius-md)] px-3 py-2 mb-3 text-xs text-ink">
                Save or send these now — for security, temporary passwords are hidden once a staff member logs in.
              </div>
              <div className="overflow-x-auto max-h-56 border border-rule rounded-[var(--radius-md)]">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-rule bg-cream/50">
                      <th className="px-3 py-2 text-left text-xs text-muted">Email</th>
                      <th className="px-3 py-2 text-left text-xs text-muted">Temp Password</th>
                      <th className="px-2 py-2"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {result.created.map((c) => (
                      <tr key={c.uid} className="border-b border-rule/50">
                        <td className="px-3 py-1.5">{c.email}</td>
                        <td className="px-3 py-1.5 font-mono">{c.tempPassword}</td>
                        <td className="px-2 py-1.5 text-right">
                          <button
                            onClick={() => copy(c.tempPassword, 'Password')}
                            className="text-xs text-section hover:underline"
                          >
                            Copy
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {result.errors.length > 0 && (
            <div className="text-left max-h-32 overflow-y-auto">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted mb-1">Errors</p>
              {result.errors.map((err, i) => (
                <p key={i} className="text-xs text-error">Row {err.row}: {err.message}</p>
              ))}
            </div>
          )}
        </div>
      )}
    </Modal>
  );
}
