'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { httpsCallable } from 'firebase/functions';
import { functions } from '@/lib/firebase/client';
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

interface UnlinkParentStudentInput {
  schoolId: string;
  parentUserId: string;
  studentId: string;
  reason?: string;
}

interface UnlinkParentStudentResult {
  schoolId: string;
  studentId: string;
  removedParentUid: string;
}

/**
 * Removes one guardian↔student relationship through the trusted callable.
 * The function verifies the actor's school role and updates both denormalized
 * link arrays plus the audit record in a single Firestore transaction.
 */
export function useUnlinkParentStudent() {
  const queryClient = useQueryClient();
  return useMutation<UnlinkParentStudentResult, Error, UnlinkParentStudentInput>({
    mutationFn: async (input) => {
      const callable = httpsCallable<
        UnlinkParentStudentInput,
        UnlinkParentStudentResult
      >(functions, 'unlinkParentFromStudent');
      try {
        const result = await callable(input);
        return result.data;
      } catch (error) {
        throw new Error(
          error instanceof Error
            ? error.message
            : 'Failed to unlink this guardian and student.',
        );
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parents'] });
      queryClient.invalidateQueries({ queryKey: ['students'] });
    },
  });
}
