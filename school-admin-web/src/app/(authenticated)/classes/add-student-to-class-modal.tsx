'use client';

import { useState, useMemo } from 'react';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { SearchInput } from '@/components/lumi/search-input';
import { Avatar } from '@/components/lumi/avatar';
import { Badge } from '@/components/lumi/badge';

interface AddStudentToClassModalProps {
  open: boolean;
  onClose: () => void;
  targetClassId: string | null;
  targetClassName: string;
  students: Array<{
    id: string;
    firstName: string;
    lastName: string;
    classId: string;
    currentReadingLevel?: string;
  }>;
  classMap: Map<string, string>;
  onMove: (studentId: string) => void;
  loading: boolean;
}

export function AddStudentToClassModal({
  open,
  onClose,
  targetClassId,
  targetClassName,
  students,
  classMap,
  onMove,
  loading,
}: AddStudentToClassModalProps) {
  const [search, setSearch] = useState('');

  const filteredStudents = useMemo(() => {
    // Exclude students already in the target class
    const eligible = students.filter((s) => {
      if (targetClassId === null) {
        // Adding to unassigned: exclude students already unassigned
        return !!s.classId;
      }
      return s.classId !== targetClassId;
    });

    if (!search) return eligible;

    const term = search.toLowerCase();
    return eligible.filter(
      (s) =>
        s.firstName.toLowerCase().includes(term) ||
        s.lastName.toLowerCase().includes(term),
    );
  }, [students, targetClassId, search]);

  const getClassLabel = (classId: string) => {
    if (!classId) return 'Unassigned';
    return classMap.get(classId) ?? 'Unassigned';
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`Add Student to ${targetClassName}`}
      footer={
        <Button variant="outline" onClick={onClose}>
          Cancel
        </Button>
      }
    >
      <div className="space-y-3">
        <SearchInput
          value={search}
          onChange={setSearch}
          placeholder="Search students by name..."
          debounceMs={200}
        />

        <div className="max-h-64 overflow-y-auto space-y-1">
          {filteredStudents.length === 0 ? (
            <div className="py-8 text-center text-sm text-text-secondary">
              No students available
            </div>
          ) : (
            filteredStudents.map((student) => {
              const fullName = `${student.firstName} ${student.lastName}`;
              return (
                <button
                  key={student.id}
                  onClick={() => onMove(student.id)}
                  disabled={loading}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-[var(--radius-md)] hover:bg-background transition-colors text-left disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Avatar name={fullName} size="sm" />
                  <span className="text-sm font-semibold text-charcoal truncate flex-1">
                    {fullName}
                  </span>
                  <Badge variant={student.classId ? 'default' : 'warning'}>
                    {getClassLabel(student.classId)}
                  </Badge>
                </button>
              );
            })
          )}
        </div>
      </div>
    </Modal>
  );
}
