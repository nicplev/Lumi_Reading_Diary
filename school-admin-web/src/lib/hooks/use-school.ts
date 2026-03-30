'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { School } from '@/lib/types';

type SerializedSchool = Omit<School, 'createdAt' | 'subscriptionExpiry' | 'termDates'> & {
  createdAt: string;
  subscriptionExpiry: string | null;
  termDates: Record<string, string>;
};

export function useSchool() {
  return useQuery<SerializedSchool>({
    queryKey: ['school'],
    queryFn: async () => {
      const res = await fetch('/api/settings');
      if (!res.ok) throw new Error('Failed to fetch school settings');
      return res.json();
    },
    staleTime: 60 * 1000,
  });
}

export function useUpdateSchool() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: Record<string, unknown>) => {
      const res = await fetch('/api/settings', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update settings');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['school'] });
    },
  });
}
