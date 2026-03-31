'use client';

import { useState, useEffect } from 'react';
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
  defaultMinutesTarget: z.coerce.number().min(1, 'Must be at least 1 minute'),
});

type ClassFormData = z.infer<typeof classFormSchema>;

interface ClassFormModalProps {
  open: boolean;
  onClose: () => void;
  onSubmit: (data: ClassFormData & { teacherIds: string[] }) => void;
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

  const { register, handleSubmit, reset, watch, setValue, formState: { errors } } = useForm<ClassFormData>({
    resolver: zodResolver(classFormSchema),
    defaultValues: {
      name: initialData?.name ?? '',
      yearLevel: initialData?.yearLevel ?? '',
      defaultMinutesTarget: initialData?.defaultMinutesTarget ?? 15,
    },
  });

  useEffect(() => {
    if (open) {
      reset({
        name: initialData?.name ?? '',
        yearLevel: initialData?.yearLevel ?? '',
        defaultMinutesTarget: initialData?.defaultMinutesTarget ?? 15,
      });
      setSelectedTeachers(initialData?.teacherIds ?? []);
    }
  }, [open, initialData, reset]);

  const handleFormSubmit = (data: ClassFormData) => {
    onSubmit({ ...data, teacherIds: selectedTeachers });
  };

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
        <Input
          label="Daily Reading Target (minutes)"
          type="number"
          min={1}
          error={errors.defaultMinutesTarget?.message}
          {...register('defaultMinutesTarget')}
        />
        {teachers.length > 0 && (
          <div>
            <label className="block text-sm font-semibold text-charcoal mb-1.5">Assigned Teachers</label>
            <div className="space-y-2 max-h-40 overflow-y-auto">
              {teachers.map((teacher) => (
                <label key={teacher.id} className="flex items-center gap-2 cursor-pointer">
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
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
}
