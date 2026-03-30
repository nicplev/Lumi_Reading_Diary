'use client';

import { useState } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { useToast } from '@/components/lumi/toast';
import { useCreateAllocation } from '@/lib/hooks/use-allocations';
import { useStudents } from '@/lib/hooks/use-students';
import { BookSearchInput } from './book-search-input';
import { Icon } from '@/components/lumi/icon';
import type { ReadingLevelOption } from '@/lib/types';

interface AllocationFormModalProps {
  open: boolean;
  onClose: () => void;
  classId: string;
  levelOptions: ReadingLevelOption[];
}

type BookItem = { title: string; bookId?: string; isbn?: string };

export function AllocationFormModal({ open, onClose, classId, levelOptions }: AllocationFormModalProps) {
  const { toast } = useToast();
  const createAllocation = useCreateAllocation();
  const { data: students } = useStudents({ classId });

  const [step, setStep] = useState(1);
  const [type, setType] = useState('byTitle');
  const [cadence, setCadence] = useState('weekly');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [targetMinutes, setTargetMinutes] = useState('15');
  const [levelStart, setLevelStart] = useState('');
  const [levelEnd, setLevelEnd] = useState('');
  const [books, setBooks] = useState<BookItem[]>([]);
  const [wholeClass, setWholeClass] = useState(true);
  const [selectedStudents, setSelectedStudents] = useState<string[]>([]);

  const reset = () => {
    setStep(1);
    setType('byTitle');
    setCadence('weekly');
    setStartDate('');
    setEndDate('');
    setTargetMinutes('15');
    setLevelStart('');
    setLevelEnd('');
    setBooks([]);
    setWholeClass(true);
    setSelectedStudents([]);
  };

  const handleClose = () => {
    reset();
    onClose();
  };

  const handleCreate = async () => {
    try {
      await createAllocation.mutateAsync({
        classId,
        type,
        cadence,
        targetMinutes: parseInt(targetMinutes) || 15,
        startDate,
        endDate,
        levelStart: type === 'byLevel' ? levelStart : undefined,
        levelEnd: type === 'byLevel' ? levelEnd : undefined,
        studentIds: wholeClass ? [] : selectedStudents,
        assignmentItems: type === 'byTitle' ? books : [],
      });
      toast('Allocation created', 'success');
      handleClose();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to create allocation', 'error');
    }
  };

  const canProceedStep1 = startDate && endDate && parseInt(targetMinutes) > 0;
  const canProceedStep2 = type !== 'byTitle' || books.length > 0;
  const canCreate = canProceedStep1 && canProceedStep2 && (wholeClass || selectedStudents.length > 0);

  const toggleStudent = (studentId: string) => {
    setSelectedStudents((prev) =>
      prev.includes(studentId) ? prev.filter((id) => id !== studentId) : [...prev, studentId]
    );
  };

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Create Allocation"
      description={`Step ${step} of 3`}
      size="lg"
      footer={
        <>
          {step > 1 && (
            <Button variant="outline" onClick={() => setStep(step - 1)}>
              Back
            </Button>
          )}
          <Button variant="outline" onClick={handleClose}>
            Cancel
          </Button>
          {step < 3 ? (
            <Button
              onClick={() => setStep(step + 1)}
              disabled={step === 1 ? !canProceedStep1 : !canProceedStep2}
            >
              Next
            </Button>
          ) : (
            <Button onClick={handleCreate} loading={createAllocation.isPending} disabled={!canCreate}>
              Create
            </Button>
          )}
        </>
      }
    >
      {step === 1 && (
        <div className="space-y-4">
          <Select
            label="Allocation Type"
            options={[
              { value: 'byTitle', label: 'By Title — Assign specific books' },
              { value: 'byLevel', label: 'By Level — Assign level range' },
              { value: 'freeChoice', label: 'Free Choice — Student picks' },
            ]}
            value={type}
            onChange={setType}
          />
          <Select
            label="Cadence"
            options={[
              { value: 'daily', label: 'Daily' },
              { value: 'weekly', label: 'Weekly' },
              { value: 'fortnightly', label: 'Fortnightly' },
              { value: 'custom', label: 'Custom' },
            ]}
            value={cadence}
            onChange={setCadence}
          />
          <div className="grid grid-cols-2 gap-4">
            <Input
              label="Start Date"
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
            />
            <Input
              label="End Date"
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
            />
          </div>
          <Input
            label="Target Minutes"
            type="number"
            value={targetMinutes}
            onChange={(e) => setTargetMinutes(e.target.value)}
            min={1}
          />
        </div>
      )}

      {step === 2 && (
        <div className="space-y-4">
          {type === 'byTitle' && (
            <>
              <p className="text-sm text-text-secondary">Search your library and add books to this allocation.</p>
              <BookSearchInput
                onAdd={(book) => {
                  if (!books.some((b) => b.title === book.title && b.bookId === book.bookId)) {
                    setBooks([...books, book]);
                  }
                }}
              />
              {books.length > 0 && (
                <div className="space-y-2">
                  <p className="text-sm font-semibold text-charcoal">{books.length} book{books.length !== 1 ? 's' : ''} added</p>
                  {books.map((book, i) => (
                    <div key={i} className="flex items-center justify-between p-2 rounded-[var(--radius-md)] bg-background">
                      <span className="text-sm text-charcoal">{book.title}</span>
                      <button
                        onClick={() => setBooks(books.filter((_, j) => j !== i))}
                        className="text-text-secondary hover:text-error transition-colors"
                      >
                        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                          <path d="M11 3L3 11M3 3l8 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                        </svg>
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
          {type === 'byLevel' && (
            <div className="space-y-4">
              <p className="text-sm text-text-secondary">Select the reading level range for this allocation.</p>
              <div className="grid grid-cols-2 gap-4">
                <Select
                  label="Level Start"
                  options={levelOptions.map((l) => ({ value: l.value, label: l.displayLabel }))}
                  value={levelStart}
                  onChange={setLevelStart}
                  placeholder="From level"
                />
                <Select
                  label="Level End"
                  options={levelOptions.map((l) => ({ value: l.value, label: l.displayLabel }))}
                  value={levelEnd}
                  onChange={setLevelEnd}
                  placeholder="To level"
                />
              </div>
            </div>
          )}
          {type === 'freeChoice' && (
            <div className="text-center py-6">
              <span className="text-text-secondary/40 mb-2 block"><Icon name="auto_stories" size={36} /></span>
              <p className="text-sm text-text-secondary">Students will choose their own books within the target minutes.</p>
            </div>
          )}
        </div>
      )}

      {step === 3 && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={wholeClass}
                onChange={(e) => setWholeClass(e.target.checked)}
                className="rounded border-divider text-rose-pink focus:ring-rose-pink"
              />
              <span className="text-sm font-semibold text-charcoal">Whole Class</span>
            </label>
          </div>
          {!wholeClass && (
            <div className="space-y-2 max-h-64 overflow-y-auto">
              {students?.map((student) => (
                <label
                  key={student.id}
                  className="flex items-center gap-3 p-2 rounded-[var(--radius-md)] hover:bg-background cursor-pointer"
                >
                  <input
                    type="checkbox"
                    checked={selectedStudents.includes(student.id)}
                    onChange={() => toggleStudent(student.id)}
                    className="rounded border-divider text-rose-pink focus:ring-rose-pink"
                  />
                  <span className="text-sm text-charcoal">{student.firstName} {student.lastName}</span>
                  {student.currentReadingLevel && (
                    <Badge variant="default">{student.currentReadingLevel}</Badge>
                  )}
                </label>
              ))}
            </div>
          )}
        </div>
      )}
    </Modal>
  );
}
