'use client';

import { useState, useEffect, useMemo } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';

const classFormSchema = z.object({
  name: z.string().min(1, 'Class name is required'),
  yearLevel: z.string().optional(),
});

type ClassFormData = z.infer<typeof classFormSchema>;

interface ClassFormModalProps {
  open: boolean;
  onClose: () => void;
  onSubmit: (data: ClassFormData & { teacherIds: string[]; defaultMinutesTarget: number }) => void;
  loading?: boolean;
  initialData?: {
    name?: string;
    yearLevel?: string;
    teacherIds?: string[];
    defaultMinutesTarget?: number;
  };
  teachers: { id: string; fullName: string }[];
  title?: string;
}

const yearLevelOptions = [
  { value: '', label: 'No year level' },
  { value: 'Prep', label: 'Prep' },
  { value: 'Year 1', label: 'Year 1' },
  { value: 'Year 2', label: 'Year 2' },
  { value: 'Year 3', label: 'Year 3' },
  { value: 'Year 4', label: 'Year 4' },
  { value: 'Year 5', label: 'Year 5' },
  { value: 'Year 6', label: 'Year 6' },
  { value: 'Year 7', label: 'Year 7' },
  { value: 'Year 8', label: 'Year 8' },
];

export function ClassFormModal({ open, onClose, onSubmit, loading, initialData, teachers, title }: ClassFormModalProps) {
  const [selectedTeachers, setSelectedTeachers] = useState<string[]>(initialData?.teacherIds ?? []);
  const [teacherSearch, setTeacherSearch] = useState('');

  const { register, handleSubmit, reset, watch, setValue, formState: { errors } } = useForm<ClassFormData>({
    resolver: zodResolver(classFormSchema),
    defaultValues: {
      name: initialData?.name ?? '',
      yearLevel: initialData?.yearLevel ?? '',
    },
  });

  useEffect(() => {
    if (open) {
      reset({
        name: initialData?.name ?? '',
        yearLevel: initialData?.yearLevel ?? '',
      });
      setSelectedTeachers(initialData?.teacherIds ?? []);
      setTeacherSearch('');
    }
  }, [open, initialData, reset]);

  const handleFormSubmit = (data: ClassFormData) => {
    onSubmit({ ...data, teacherIds: selectedTeachers, defaultMinutesTarget: initialData?.defaultMinutesTarget ?? 15 });
  };

  const filteredTeachers = useMemo(() => {
    if (!teacherSearch) return teachers;
    const q = teacherSearch.toLowerCase();
    return teachers.filter((t) => t.fullName.toLowerCase().includes(q));
  }, [teachers, teacherSearch]);

  const toggleTeacher = (id: string) => {
    setSelectedTeachers((prev) =>
      prev.includes(id) ? prev.filter((t) => t !== id) : [...prev, id]
    );
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title ?? (initialData ? 'Edit Class' : 'Add Class')}
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button onClick={handleSubmit(handleFormSubmit)} loading={loading}>
            {initialData ? 'Save Changes' : 'Create Class'}
          </Button>
        </>
      }
    >
      <form className="space-y-4" onSubmit={(e) => e.preventDefault()}>
        <Input
          label="Class Name"
          placeholder="e.g. Room 12, 3B"
          error={errors.name?.message}
          {...register('name')}
        />
        <Select
          label="Year Level"
          options={yearLevelOptions}
          value={watch('yearLevel') ?? ''}
          onChange={(v) => setValue('yearLevel', v)}
          placeholder="Select year level"
        />
        {teachers.length > 0 && (
          <div>
            <label className="block text-sm font-semibold text-charcoal mb-1.5">Assigned Teachers</label>
            {selectedTeachers.length > 0 && (
              <div className="flex flex-wrap gap-1.5 mb-2">
                {selectedTeachers.map((id) => {
                  const t = teachers.find((t) => t.id === id);
                  return (
                    <span key={id} className="inline-flex items-center gap-1 px-2 py-0.5 rounded-[var(--radius-pill)] bg-brand-primary/10 text-xs font-semibold text-charcoal">
                      {t?.fullName.includes('@') ? t.fullName.split('@')[0] : t?.fullName ?? id}
                      <button type="button" onClick={() => toggleTeacher(id)} className="text-text-secondary hover:text-error ml-0.5">&times;</button>
                    </span>
                  );
                })}
              </div>
            )}
            <input
              type="text"
              value={teacherSearch}
              onChange={(e) => setTeacherSearch(e.target.value)}
              placeholder="Search teachers..."
              className="w-full px-3 py-2 text-sm border border-divider rounded-[var(--radius-md)] bg-surface text-charcoal placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-brand-primary/20 mb-2"
            />
            <div className="space-y-1 max-h-40 overflow-y-auto">
              {filteredTeachers.map((teacher) => (
                <label key={teacher.id} className="flex items-center gap-2 cursor-pointer px-1 py-1 rounded-[var(--radius-sm)] hover:bg-background">
                  <input
                    type="checkbox"
                    checked={selectedTeachers.includes(teacher.id)}
                    onChange={() => toggleTeacher(teacher.id)}
                    className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
                  />
                  <span className="text-sm text-charcoal">
                    {teacher.fullName.includes('@')
                      ? <><span className="text-text-secondary">{teacher.fullName}</span> <span className="text-xs text-text-secondary/60">(no name set)</span></>
                      : teacher.fullName
                    }
                  </span>
                </label>
              ))}
              {filteredTeachers.length === 0 && (
                <p className="text-xs text-text-secondary py-2 text-center">No teachers match your search</p>
              )}
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
}
