'use client';

import { useQuery } from '@tanstack/react-query';
import type { LibraryAssignmentSnapshot } from '@/lib/types';

/** "Who has this book" snapshot for the library — powers the assigned-count
 *  badges and the assignees modal. One cached query drives both. */
export function useLibraryAssignments() {
  return useQuery<LibraryAssignmentSnapshot>({
    queryKey: ['library-assignments'],
    queryFn: async () => {
      const res = await fetch('/api/library/assignments');
      if (!res.ok) throw new Error('Failed to fetch library assignments');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}
