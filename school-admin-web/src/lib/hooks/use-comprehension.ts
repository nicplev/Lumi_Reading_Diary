'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

interface ComprehensionQuestion {
  question: string | null; // null = using the default
  default: string;
}

export function useComprehensionQuestion(classId: string) {
  return useQuery<ComprehensionQuestion>({
    queryKey: ['comprehension-question', classId],
    queryFn: async () => {
      const res = await fetch(`/api/classes/${classId}/comprehension-question`);
      if (!res.ok) throw new Error('Failed to load comprehension question');
      return res.json();
    },
    enabled: !!classId,
    staleTime: 60 * 1000,
  });
}

export function useSetComprehensionQuestion(classId: string) {
  const qc = useQueryClient();
  return useMutation<ComprehensionQuestion, Error, string>({
    mutationFn: async (question) => {
      const res = await fetch(`/api/classes/${classId}/comprehension-question`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question }),
      });
      if (!res.ok) {
        const e = await res.json();
        throw new Error(e.error || 'Failed to save');
      }
      return res.json();
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['comprehension-question', classId] });
    },
  });
}
