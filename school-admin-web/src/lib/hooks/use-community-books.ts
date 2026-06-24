'use client';

import { useMutation } from '@tanstack/react-query';

export interface ContributeBookInput {
  isbn: string;
  title: string;
  author?: string;
  readingLevel?: string;
  description?: string;
  /** data:image/jpeg;base64,… (resized client-side); omitted if no cover. */
  coverDataUrl?: string;
}

export interface ContributeBookResult {
  isbn: string;
  created: boolean;
  coverUpdated: boolean;
}

export function useContributeCommunityBook() {
  return useMutation<ContributeBookResult, Error, ContributeBookInput>({
    mutationFn: async (input) => {
      const res = await fetch('/api/community-books', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(input),
      });
      if (!res.ok) {
        const e = await res.json();
        throw new Error(e.error || 'Failed to contribute book');
      }
      return res.json();
    },
  });
}
