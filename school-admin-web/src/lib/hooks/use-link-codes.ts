'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { StudentLinkCode } from '@/lib/types';

type SerializedLinkCode = Omit<StudentLinkCode, 'createdAt' | 'expiresAt' | 'usedAt'> & {
  createdAt: string;
  expiresAt: string;
  usedAt: string | null;
};

export function useLinkCodes() {
  return useQuery<SerializedLinkCode[]>({
    queryKey: ['link-codes'],
    queryFn: async () => {
      const res = await fetch('/api/link-codes');
      if (!res.ok) throw new Error('Failed to fetch link codes');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useCreateLinkCode() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (studentId: string) => {
      const res = await fetch('/api/link-codes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ studentId }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to create link code');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['link-codes'] });
    },
  });
}

export function useRevokeLinkCode() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (codeId: string) => {
      const res = await fetch(`/api/link-codes/${codeId}`, { method: 'DELETE' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to revoke link code');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['link-codes'] });
    },
  });
}

export function useDeleteLinkCode() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (codeId: string) => {
      const res = await fetch(`/api/link-codes/${codeId}?permanent=true`, { method: 'DELETE' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to delete link code');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['link-codes'] });
    },
  });
}

export function useBulkCreateLinkCodes() {
  const queryClient = useQueryClient();
  return useMutation<{ count: number; codes: SerializedLinkCode[] }, Error, string[]>({
    mutationFn: async (studentIds: string[]) => {
      const res = await fetch('/api/link-codes/bulk', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ studentIds }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to bulk create codes');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['link-codes'] });
    },
  });
}
