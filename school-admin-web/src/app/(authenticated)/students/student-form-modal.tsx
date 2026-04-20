'use client';

import { useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Modal } from '@/components/lumi/modal';
import { Button } from '@/components/lumi/button';
import { Input } from '@/components/lumi/input';
import { Select } from '@/components/lumi/select';
import type { SchoolClass, ReadingLevelOption } from '@/lib/types';

const studentFormSchema = z.object({
  studentId: z.string().optional(),
  firstName: z.string().min(1, 'First name is required'),
  lastName: z.string().min(1, 'Last name is required'),
  classId: z.string().min(1, 'Class is required'),
  dateOfBirth: z.string().optional(),
  currentReadingLevel: z.string().optional(),
  parentEmail: z
    .string()
    .optional()
    .refine((v) => !v || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Enter a valid email address'),
});

type StudentFormData = z.infer<typeof studentFormSchema>;

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface StudentFormModalProps {
  open: boolean;
  onClose: () => void;
  onSubmit: (data: StudentFormData) => void;
  loading?: boolean;
  initialData?: Partial<StudentFormData>;
  classes: SerializedClass[];
  levelOptions: ReadingLevelOption[];
  title?: string;
}

export function StudentFormModal({
  open,
  onClose,
  onSubmit,
  loading,
  initialData,
  classes,
  levelOptions,
  title,
}: StudentFormModalProps) {
  const {
    register,
    handleSubmit,
    reset,
    watch,
    setValue,
    formState: { errors },
  } = useForm<StudentFormData>({
    resolver: zodResolver(studentFormSchema),
    defaultValues: {
      studentId: initialData?.studentId ?? '',
      firstName: initialData?.firstName ?? '',
      lastName: initialData?.lastName ?? '',
      classId: initialData?.classId ?? '',
      dateOfBirth: initialData?.dateOfBirth ?? '',
      currentReadingLevel: initialData?.currentReadingLevel ?? '',
      parentEmail: initialData?.parentEmail ?? '',
    },
  });

  useEffect(() => {
    if (open) {
      reset({
        studentId: initialData?.studentId ?? '',
        firstName: initialData?.firstName ?? '',
        lastName: initialData?.lastName ?? '',
        classId: initialData?.classId ?? '',
        dateOfBirth: initialData?.dateOfBirth ?? '',
        currentReadingLevel: initialData?.currentReadingLevel ?? '',
        parentEmail: initialData?.parentEmail ?? '',
      });
    }
  }, [open, initialData, reset]);

  const classId = watch('classId');
  const currentLevel = watch('currentReadingLevel');

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title ?? (initialData ? 'Edit Student' : 'Add Student')}
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button onClick={handleSubmit(onSubmit)} loading={loading}>
            {initialData ? 'Save Changes' : 'Add Student'}
          </Button>
        </>
      }
    >
      <form className="space-y-4" onSubmit={(e) => e.preventDefault()}>
        <Input
          label="Student ID (optional)"
          placeholder="e.g. STU001"
          error={errors.studentId?.message}
          {...register('studentId')}
        />
        <div className="grid grid-cols-2 gap-4">
          <Input
            label="First Name"
            error={errors.firstName?.message}
            {...register('firstName')}
          />
          <Input
            label="Last Name"
            error={errors.lastName?.message}
            {...register('lastName')}
          />
        </div>
        <Select
          label="Class"
          options={classes.map((c) => ({ value: c.id, label: c.name }))}
          value={classId}
          onChange={(v) => setValue('classId', v)}
          placeholder="Select class"
          error={errors.classId?.message}
        />
        <Input
          label="Date of Birth (optional)"
          type="date"
          {...register('dateOfBirth')}
        />
        <Input
          label="Parent/Guardian Email (optional)"
          type="email"
          placeholder="parent@example.com"
          error={errors.parentEmail?.message}
          {...register('parentEmail')}
        />
        {levelOptions.length > 0 && (
          <Select
            label="Reading Level (optional)"
            options={[
              { value: '', label: 'No level' },
              ...levelOptions.map((l) => ({ value: l.value, label: l.displayLabel })),
            ]}
            value={currentLevel ?? ''}
            onChange={(v) => setValue('currentReadingLevel', v)}
          />
        )}
      </form>
    </Modal>
  );
}
