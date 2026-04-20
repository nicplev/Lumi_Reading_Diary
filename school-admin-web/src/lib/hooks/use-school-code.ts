'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

export type SerializedSchoolCode = {
  id: string;
  code: string;
  createdAt: string;
  usageCount: number;
};

export function useSchoolCode() {
  return useQuery<SerializedSchoolCode | null>({
    queryKey: ['school-code'],
    queryFn: async () => {
      const res = await fetch('/api/school-codes');
      if (!res.ok) throw new Error('Failed to fetch school code');
      return res.json();
    },
    staleTime: 60 * 1000,
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
