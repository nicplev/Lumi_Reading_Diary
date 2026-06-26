'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { ReadingGroup, ReadingGroupStat } from '@/lib/types';

type SerializedGroup = Omit<ReadingGroup, 'createdAt'> & { createdAt: string };

export function useReadingGroups(classId: string) {
  return useQuery<SerializedGroup[]>({
    queryKey: ['reading-groups', classId],
    queryFn: async () => {
      const res = await fetch(`/api/reading-groups?classId=${classId}`);
      if (!res.ok) throw new Error('Failed to fetch reading groups');
      return res.json();
    },
    enabled: !!classId,
    staleTime: 30 * 1000,
  });
}

export function useCreateReadingGroup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: { name: string; classId: string; readingLevel?: string; color?: string; description?: string; targetMinutes?: number }) => {
      const res = await fetch('/api/reading-groups', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to create group');
      }
      return res.json();
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['reading-groups', variables.classId] });
    },
  });
}

export function useUpdateReadingGroup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ groupId, ...data }: { groupId: string; name?: string; readingLevel?: string; color?: string; description?: string; targetMinutes?: number; studentIds?: string[] }) => {
      const res = await fetch(`/api/reading-groups/${groupId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update group');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reading-groups'] });
    },
  });
}

export function useDeleteReadingGroup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ groupId }: { groupId: string }) => {
      const res = await fetch(`/api/reading-groups/${groupId}`, { method: 'DELETE' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to delete group');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reading-groups'] });
    },
  });
}

export function useReadingGroupStats(classId: string) {
  return useQuery<ReadingGroupStat[]>({
    queryKey: ['reading-group-stats', classId],
    queryFn: async () => {
      const res = await fetch(`/api/reading-groups/stats?classId=${classId}`);
      if (!res.ok) throw new Error('Failed to load reading group stats');
      return res.json();
    },
    enabled: !!classId,
    staleTime: 60 * 1000,
  });
}

export function useReorderReadingGroups() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ classId, orderedIds }: { classId: string; orderedIds: string[] }) => {
      const res = await fetch('/api/reading-groups/reorder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ classId, orderedIds }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to reorder groups');
      }
      return res.json();
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['reading-groups', variables.classId] });
    },
  });
}
