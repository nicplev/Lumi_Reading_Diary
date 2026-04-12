'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { Student, ReadingLevelEvent, EnrollmentStatus } from '@/lib/types';
import type { ImportResult } from '@/lib/firestore/students';

type SerializedStudent = Omit<Student, 'createdAt' | 'dateOfBirth' | 'enrolledAt' | 'readingLevelUpdatedAt' | 'levelHistory' | 'stats'> & {
  createdAt: string;
  dateOfBirth: string | null;
  enrolledAt: string | null;
  readingLevelUpdatedAt: string | null;
  levelHistory: Array<Omit<Student['levelHistory'][0], 'changedAt'> & { changedAt: string }>;
  stats: (Omit<NonNullable<Student['stats']>, 'lastReadingDate'> & { lastReadingDate: string | null }) | null;
};

type SerializedEvent = Omit<ReadingLevelEvent, 'createdAt'> & { createdAt: string };

export function useStudents(filters?: { classId?: string }) {
  const params = new URLSearchParams();
  if (filters?.classId) params.set('classId', filters.classId);

  return useQuery<SerializedStudent[]>({
    queryKey: ['students', filters],
    queryFn: async () => {
      const res = await fetch(`/api/students?${params}`);
      if (!res.ok) throw new Error('Failed to fetch students');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useStudent(studentId: string) {
  return useQuery<SerializedStudent>({
    queryKey: ['students', studentId],
    queryFn: async () => {
      const res = await fetch(`/api/students/${studentId}`);
      if (!res.ok) throw new Error('Failed to fetch student');
      return res.json();
    },
    enabled: !!studentId,
  });
}

export function useCreateStudent() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: { studentId?: string; firstName: string; lastName: string; classId: string; dateOfBirth?: string; currentReadingLevel?: string }) => {
      const res = await fetch('/api/students', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to create student');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      queryClient.invalidateQueries({ queryKey: ['classes'] });
    },
  });
}

export function useUpdateStudent() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ studentId, ...data }: { studentId: string; firstName?: string; lastName?: string; classId?: string; currentReadingLevel?: string }) => {
      const res = await fetch(`/api/students/${studentId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update student');
      }
      return res.json();
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      queryClient.invalidateQueries({ queryKey: ['students', variables.studentId] });
    },
  });
}

export function useDeactivateStudent() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (studentId: string) => {
      const res = await fetch(`/api/students/${studentId}`, { method: 'DELETE' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to deactivate student');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      queryClient.invalidateQueries({ queryKey: ['classes'] });
    },
  });
}

export function useImportStudents() {
  const queryClient = useQueryClient();
  return useMutation<ImportResult, Error, { rows: Array<Record<string, string>> }>({
    mutationFn: async (data) => {
      const res = await fetch('/api/students/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to import students');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      queryClient.invalidateQueries({ queryKey: ['classes'] });
    },
  });
}

export function useUpdateStudentLevel(studentId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: { toLevel: string; reason?: string; fromLevel?: string; toLevelIndex?: number }) => {
      const res = await fetch(`/api/students/${studentId}/level`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update level');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      queryClient.invalidateQueries({ queryKey: ['students', studentId] });
      queryClient.invalidateQueries({ queryKey: ['level-history', studentId] });
    },
  });
}

export function useBulkUpdateLevel() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: { studentIds: string[]; toLevel: string; toLevelIndex?: number; reason?: string }) => {
      const res = await fetch('/api/students/bulk-level', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to bulk update levels');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
    },
  });
}

export function useReadingLevelHistory(studentId: string) {
  return useQuery<SerializedEvent[]>({
    queryKey: ['level-history', studentId],
    queryFn: async () => {
      const res = await fetch(`/api/students/${studentId}/level`);
      if (!res.ok) throw new Error('Failed to fetch level history');
      return res.json();
    },
    enabled: !!studentId,
  });
}

export function useUpdateEnrollmentStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ studentId, enrollmentStatus }: { studentId: string; enrollmentStatus: EnrollmentStatus }) => {
      const res = await fetch(`/api/students/${studentId}/enrollment`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ enrollmentStatus }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update enrollment status');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
    },
  });
}

export function useBulkUpdateEnrollmentStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ studentIds, enrollmentStatus }: { studentIds: string[]; enrollmentStatus: EnrollmentStatus }) => {
      const res = await fetch('/api/students/bulk-enrollment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ studentIds, enrollmentStatus }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to bulk update enrollment');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
    },
  });
}
