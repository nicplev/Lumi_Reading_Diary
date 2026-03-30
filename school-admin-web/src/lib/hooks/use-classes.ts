'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { SchoolClass } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

export function useClasses() {
  return useQuery<SerializedClass[]>({
    queryKey: ['classes'],
    queryFn: async () => {
      const res = await fetch('/api/classes');
      if (!res.ok) throw new Error('Failed to fetch classes');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useClass(classId: string) {
  return useQuery<SerializedClass>({
    queryKey: ['classes', classId],
    queryFn: async () => {
      const res = await fetch(`/api/classes/${classId}`);
      if (!res.ok) throw new Error('Failed to fetch class');
      return res.json();
    },
    enabled: !!classId,
  });
}

export function useCreateClass() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: { name: string; yearLevel?: string; teacherIds: string[]; defaultMinutesTarget: number }) => {
      const res = await fetch('/api/classes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to create class');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['classes'] });
    },
  });
}

export function useUpdateClass() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ classId, ...data }: { classId: string; name?: string; yearLevel?: string; teacherIds?: string[]; defaultMinutesTarget?: number }) => {
      const res = await fetch(`/api/classes/${classId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update class');
      }
      return res.json();
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['classes'] });
      queryClient.invalidateQueries({ queryKey: ['classes', variables.classId] });
    },
  });
}

export function useDeleteClass() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (classId: string) => {
      const res = await fetch(`/api/classes/${classId}`, { method: 'DELETE' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to delete class');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['classes'] });
    },
  });
}
