'use client';

import { useEffect, useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Tabs } from '@/components/lumi/tabs';
import { StudentFormModal, type StudentFormData } from './student-form-modal';
import { CSVImportDialog } from './csv-import-dialog';
import type { SchoolClass, ReadingLevelOption } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface AddStudentsModalProps {
  open: boolean;
  onClose: () => void;
  /** Manual single-student create handler. */
  onSubmitManual: (data: StudentFormData) => void;
  creating?: boolean;
  classes: SerializedClass[];
  levelOptions: ReadingLevelOption[];
}

const TABS = [
  { id: 'manual', label: 'Add a student' },
  { id: 'csv', label: 'Import from CSV' },
];

/**
 * Single entry point for adding students: a manual single-student form and the
 * bulk CSV import, tabbed inside one modal. Replaces the separate "Add Student"
 * and "Import CSV" buttons/modals — the user picks the path inside.
 */
export function AddStudentsModal({
  open,
  onClose,
  onSubmitManual,
  creating,
  classes,
  levelOptions,
}: AddStudentsModalProps) {
  const [mode, setMode] = useState<'manual' | 'csv'>('manual');

  // Always reopen on the manual tab — the common path.
  useEffect(() => {
    if (open) setMode('manual');
  }, [open]);

  return (
    <Modal open={open} onClose={onClose} title="Add students" size={mode === 'csv' ? 'lg' : 'md'}>
      <div className="mb-5">
        <Tabs tabs={TABS} activeTab={mode} onChange={(t) => setMode(t as 'manual' | 'csv')} />
      </div>
      {mode === 'manual' ? (
        <StudentFormModal
          embedded
          open={open}
          onClose={onClose}
          onSubmit={onSubmitManual}
          loading={creating}
          classes={classes}
          levelOptions={levelOptions}
        />
      ) : (
        <CSVImportDialog embedded open={open} onClose={onClose} />
      )}
    </Modal>
  );
}
