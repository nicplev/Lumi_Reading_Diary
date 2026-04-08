'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { ParentWithStudents } from '@/lib/types';

type SerializedParent = Omit<ParentWithStudents, 'createdAt' | 'lastLoginAt'> & {
  createdAt: string;
  lastLoginAt: string | null;
};

export function useParents() {
  return useQuery<SerializedParent[]>({
    queryKey: ['parents'],
    queryFn: async () => {
      const res = await fetch('/api/parents');
      if (!res.ok) throw new Error('Failed to fetch parents');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useSyncParentLinks() {
  const queryClient = useQueryClient();
  return useMutation<{ updatedCount: number }>({
    mutationFn: async () => {
      const res = await fetch('/api/parents/sync', { method: 'POST' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to sync parent links');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parents'] });
    },
  });
}
