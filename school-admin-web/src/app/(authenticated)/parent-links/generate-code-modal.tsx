'use client';

import { useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Select } from '@/components/lumi/select';
import { Badge } from '@/components/lumi/badge';
import { useToast } from '@/components/lumi/toast';
import { useStudents } from '@/lib/hooks/use-students';
import { useClasses } from '@/lib/hooks/use-classes';
import { useCreateLinkCode, useBulkCreateLinkCodes } from '@/lib/hooks/use-link-codes';

interface GenerateCodeModalProps {
  open: boolean;
  onClose: () => void;
}

export function GenerateCodeModal({ open, onClose }: GenerateCodeModalProps) {
  const { toast } = useToast();
  const { data: classes } = useClasses();
  const { data: students } = useStudents();
  const createCode = useCreateLinkCode();
  const bulkCreate = useBulkCreateLinkCodes();

  const [mode, setMode] = useState<'single' | 'bulk'>('single');
  const [selectedStudent, setSelectedStudent] = useState('');
  const [selectedClass, setSelectedClass] = useState('');
  const [generatedCode, setGeneratedCode] = useState('');

  const reset = () => {
    setMode('single');
    setSelectedStudent('');
    setSelectedClass('');
    setGeneratedCode('');
  };

  const handleClose = () => {
    reset();
    onClose();
  };

  const handleGenerateSingle = async () => {
    if (!selectedStudent) return;
    try {
      const result = await createCode.mutateAsync(selectedStudent);
      setGeneratedCode(result.code);
      toast('Link code generated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to generate code', 'error');
    }
  };

  const handleGenerateBulk = async () => {
    if (!selectedClass) return;
    const classStudents = students?.filter((s) => s.classId === selectedClass) ?? [];
    if (classStudents.length === 0) {
      toast('No students in this class', 'error');
      return;
    }
    try {
      const result = await bulkCreate.mutateAsync(classStudents.map((s) => s.id));
      toast(`${result.count} codes generated`, 'success');
      handleClose();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to generate codes', 'error');
    }
  };

  const studentOptions = (students ?? [])
    .filter((s) => s.isActive)
    .map((s) => ({ value: s.id, label: `${s.firstName} ${s.lastName}` }))
    .sort((a, b) => a.label.localeCompare(b.label));

  const classOptions = (classes ?? []).map((c) => ({ value: c.id, label: c.name }));

  const classStudentCount = selectedClass
    ? students?.filter((s) => s.classId === selectedClass && s.isActive).length ?? 0
    : 0;

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Generate Link Code"
      description="Create codes for parents to link to their children."
      size="md"
      footer={
        generatedCode ? (
          <Button onClick={handleClose}>Done</Button>
        ) : (
          <>
            <Button variant="outline" onClick={handleClose}>Cancel</Button>
            {mode === 'single' ? (
              <Button
                onClick={handleGenerateSingle}
                loading={createCode.isPending}
                disabled={!selectedStudent}
              >
                Generate
              </Button>
            ) : (
              <Button
                onClick={handleGenerateBulk}
                loading={bulkCreate.isPending}
                disabled={!selectedClass || classStudentCount === 0}
              >
                Generate {classStudentCount} Codes
              </Button>
            )}
          </>
        )
      }
    >
      {generatedCode ? (
        <div className="text-center py-4">
          <p className="text-sm text-text-secondary mb-3">Share this code with the parent:</p>
          <code className="inline-block bg-background px-6 py-3 rounded-[var(--radius-md)] text-2xl font-mono font-bold text-charcoal tracking-widest">
            {generatedCode}
          </code>
          <button
            onClick={() => {
              navigator.clipboard.writeText(generatedCode);
              toast('Copied to clipboard', 'success');
            }}
            className="block mx-auto mt-3 text-sm text-rose-pink hover:underline"
          >
            Copy to clipboard
          </button>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="flex gap-2">
            <Button
              variant={mode === 'single' ? 'primary' : 'outline'}
              size="sm"
              onClick={() => setMode('single')}
            >
              Single Student
            </Button>
            <Button
              variant={mode === 'bulk' ? 'primary' : 'outline'}
              size="sm"
              onClick={() => setMode('bulk')}
            >
              Bulk (by Class)
            </Button>
          </div>

          {mode === 'single' ? (
            <Select
              label="Select Student"
              options={studentOptions}
              value={selectedStudent}
              onChange={setSelectedStudent}
              placeholder="Choose a student..."
            />
          ) : (
            <div className="space-y-3">
              <Select
                label="Select Class"
                options={classOptions}
                value={selectedClass}
                onChange={setSelectedClass}
                placeholder="Choose a class..."
              />
              {selectedClass && (
                <div className="flex items-center gap-2">
                  <Badge variant="info">{classStudentCount} student{classStudentCount !== 1 ? 's' : ''}</Badge>
                  <span className="text-xs text-text-secondary">will receive new link codes</span>
                </div>
              )}
            </div>
          )}

          <p className="text-xs text-text-secondary">
            Generating a new code for a student will revoke any existing active codes.
            Codes are valid for 1 year.
          </p>
        </div>
      )}
    </Modal>
  );
}
