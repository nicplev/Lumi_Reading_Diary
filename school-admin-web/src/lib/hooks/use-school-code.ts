'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

export type SerializedSchoolCode = {
  id: string;
  code: string;
  createdAt: string;
  usageCount: number;
  /** ISO string, or null for legacy codes created without an expiry. */
  expiresAt: string | null;
  maxUsages: number | null;
};

export function useSchoolCode() {
  return useQuery<SerializedSchoolCode | null>({
    queryKey: ['school-code'],
    queryFn: async () => {
      const res = await fetch('/api/school-codes');
      if (!res.ok) throw new Error('Failed to fetch school code');
      return res.json();
    },
    // Kept short and refetched on focus so the expiry countdown can't sit
    // stale on a tab left open for days — an admin returning to the page
    // should see "expired", not yesterday's "expires in 1 day".
    staleTime: 60 * 1000,
    refetchInterval: 5 * 60 * 1000,
    refetchOnWindowFocus: true,
  });
}

export function useRotateSchoolCode() {
  const queryClient = useQueryClient();
  return useMutation<SerializedSchoolCode, Error, void>({
    mutationFn: async () => {
      const res = await fetch('/api/school-codes', { method: 'POST' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to rotate code');
      }
      return res.json();
    },
    onSuccess: (newCode) => {
      queryClient.setQueryData(['school-code'], newCode);
    },
  });
}
