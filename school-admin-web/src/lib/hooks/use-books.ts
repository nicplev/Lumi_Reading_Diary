'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { Book } from '@/lib/types';

type SerializedBook = Omit<Book, 'createdAt' | 'publishedDate'> & {
  createdAt: string;
  publishedDate: string | null;
};

export function useBooks() {
  return useQuery<SerializedBook[]>({
    queryKey: ['books'],
    queryFn: async () => {
      const res = await fetch('/api/books');
      if (!res.ok) throw new Error('Failed to fetch books');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useBook(bookId: string) {
  return useQuery<SerializedBook>({
    queryKey: ['books', bookId],
    queryFn: async () => {
      const res = await fetch(`/api/books/${bookId}`);
      if (!res.ok) throw new Error('Failed to fetch book');
      return res.json();
    },
    enabled: !!bookId,
  });
}

export function useCreateBook() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (data: { title: string; author?: string; isbn?: string; readingLevel?: string; coverImageUrl?: string }) => {
      const res = await fetch('/api/books', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to create book');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['books'] });
    },
  });
}

export function useUpdateBook() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ bookId, ...data }: { bookId: string; title?: string; author?: string; isbn?: string; readingLevel?: string; coverImageUrl?: string }) => {
      const res = await fetch(`/api/books/${bookId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to update book');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['books'] });
    },
  });
}

export function useDeleteBook() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (bookId: string) => {
      const res = await fetch(`/api/books/${bookId}`, { method: 'DELETE' });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to delete book');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['books'] });
    },
  });
}

export function useLookupIsbn() {
  return useMutation<{ book: SerializedBook | null }, Error, string>({
    mutationFn: async (isbn: string) => {
      const res = await fetch('/api/books/lookup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isbn }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to lookup ISBN');
      }
      return res.json();
    },
  });
}
