'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { Allocation, AllocationBookItem } from '@/lib/types';

type SerializedAllocation = Omit<Allocation, 'createdAt' | 'startDate' | 'endDate' | 'assignmentItems' | 'studentOverrides'> & {
  createdAt: string;
  startDate: string;
  endDate: string;
  assignmentItems: (Omit<AllocationBookItem, 'addedAt'> & { addedAt: string | null })[];
  studentOverrides: Record<string, {
    studentId: string;
    removedItemIds: string[];
    addedItems: (Omit<AllocationBookItem, 'addedAt'> & { addedAt: string | null })[];
    updatedAt: string | null;
    updatedBy?: string;
  }>;
};

export function useAllocations(filters?: { classId?: string; isActive?: boolean }) {
  const params = new URLSearchParams();
  if (filters?.classId) params.set('classId', filters.classId);
  if (filters?.isActive !== undefined) params.set('isActive', String(filters.isActive));

  return useQuery<SerializedAllocation[]>({
    queryKey: ['allocations', filters],
    queryFn: async () => {
      const res = await fetch(`/api/allocations?${params}`);
      if (!res.ok) throw new Error('Failed to fetch allocations');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useAllocation(allocationId: string) {
  return useQuery<SerializedAllocation>({
    queryKey: ['allocations', allocationId],
    queryFn: async () => {
      const res = await fetch(`/api/allocations/${allocationId}`);
      if (!res.ok) throw new Error('Failed to fetch allocation');
      return res.json();
    },
    enabled: !!allocationId,
  });
}

export function useCreateAllocation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: {
      classId: string;
      type: string;
      cadence: string;
      targetMinutes: number;
      startDate: string;
      endDate: string;
      levelStart?: string;
      levelEnd?: string;
      studentIds?: string[];
      assignmentItems?: { title: string; bookId?: string; isbn?: string }[];
    }) => {
      const res = await fetch('/api/allocations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to create allocation');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['allocations'] });
    },
  });
}

export function useUpdateAllocation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ allocationId, ...data }: {
      allocationId: string;
      cadence?: string;
      targetMinutes?: number;
      startDate?: string;
      endDate?: string;
      studentIds?: string[];
    }) => {
      const res = await fetch(`/api/allocations/${allocationId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update allocation');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['allocations'] });
    },
  });
}

export function useDeactivateAllocation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (allocationId: string) => {
      const res = await fetch(`/api/allocations/${allocationId}`, { method: 'DELETE' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to deactivate allocation');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['allocations'] });
    },
  });
}

export function useAddBookToAllocation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ allocationId, ...item }: { allocationId: string; title: string; bookId?: string; isbn?: string }) => {
      const res = await fetch(`/api/allocations/${allocationId}/items`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(item),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to add book');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['allocations'] });
    },
  });
}

export function useRemoveBookFromAllocation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ allocationId, itemId }: { allocationId: string; itemId: string }) => {
      const res = await fetch(`/api/allocations/${allocationId}/items`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ itemId }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to remove book');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['allocations'] });
    },
  });
}

export function useStudentAllocations(studentId: string, classId: string) {
  const params = new URLSearchParams();
  if (classId) params.set('classId', classId);
  params.set('isActive', 'true');

  return useQuery<SerializedAllocation[]>({
    queryKey: ['allocations', 'student', studentId, classId],
    queryFn: async () => {
      const res = await fetch(`/api/allocations?${params}`);
      if (!res.ok) throw new Error('Failed to fetch student allocations');
      const allocations: SerializedAllocation[] = await res.json();
      const now = new Date().toISOString();
      return allocations.filter((a) => {
        const isTargeted = a.studentIds.length === 0 || a.studentIds.includes(studentId);
        const inRange = a.startDate <= now && a.endDate >= now;
        return isTargeted && inRange;
      });
    },
    enabled: !!studentId && !!classId,
    staleTime: 30 * 1000,
  });
}
