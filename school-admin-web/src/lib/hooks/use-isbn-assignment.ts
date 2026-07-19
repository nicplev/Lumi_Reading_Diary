'use client';

import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/lib/auth/auth-context';

export interface AssignIsbnsResult {
  allocationId: string;
  assigned: { isbn: string; title: string }[];
  duplicates: string[];
  invalid: string[];
}

export interface AssignIsbnsInput {
  studentId: string;
  isbns: string[];
  weekStart: string; // 'YYYY-MM-DD' (Monday, local)
}

export function useAssignIsbns() {
  const qc = useQueryClient();
  const { user } = useAuth();
  return useMutation<AssignIsbnsResult, Error, AssignIsbnsInput>({
    mutationFn: async (input) => {
      const endpoint = user?.demoAllocationMutations
        ? '/api/demo/isbn-assignment'
        : '/api/isbn-assignment';
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(input),
      });
      if (!res.ok) {
        const e = await res.json();
        throw new Error(e.error || 'Failed to assign books');
      }
      return res.json();
    },
    onSuccess: () => {
      // The weekly allocation drives the student's Assigned Books view.
      qc.invalidateQueries({ queryKey: ['allocations'] });
    },
  });
}
