'use client';

import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';

export interface SerializedReadingLog {
  id: string;
  studentId: string;
  classId: string;
  date: string;
  minutesRead: number;
  targetMinutes: number | null;
  status: string;
  bookTitles: string[];
  notes: string | null;
  childFeeling: string | null;
  loggedByRole: string | null;
  loggedByName: string | null;
  loggedByLabel: string | null;
  allocationId: string | null;
  hasComprehensionAudio: boolean;
  comprehensionAudioDurationSec: number | null;
  lastCommentPreview: string | null;
  lastCommentAt: string | null;
  lastCommentByRole: string | null;
  hasUnread: boolean;
  createdAt: string | null;
}

export interface SerializedLogComment {
  id: string;
  authorId: string;
  authorRole: string;
  authorName: string;
  body: string;
  createdAt: string | null;
}

export function useReadingLogs(studentId: string, range?: { from: string; to: string }) {
  return useQuery<SerializedReadingLog[]>({
    // Range is part of the key so widening the window refetches rather than
    // serving the narrower cached set. Partial-match invalidation by
    // ['reading-logs'] still catches every windowed query.
    queryKey: ['reading-logs', studentId, range?.from ?? null, range?.to ?? null],
    queryFn: async () => {
      const params = new URLSearchParams({ studentId });
      if (range) {
        params.set('from', range.from);
        params.set('to', range.to);
      }
      const res = await fetch(`/api/reading-logs?${params.toString()}`);
      if (!res.ok) throw new Error('Failed to fetch reading logs');
      return res.json();
    },
    enabled: !!studentId,
    staleTime: 30 * 1000,
    // Keep the prior window visible while a wider one loads, so switching presets
    // shows an "Updating…" hint instead of flashing the list empty.
    placeholderData: keepPreviousData,
  });
}

export function useLogComments(logId: string | null) {
  return useQuery<SerializedLogComment[]>({
    queryKey: ['log-comments', logId],
    queryFn: async () => {
      const res = await fetch(`/api/reading-logs/${logId}/comments`);
      if (!res.ok) throw new Error('Failed to fetch comments');
      return res.json();
    },
    enabled: !!logId,
    staleTime: 15 * 1000,
  });
}

export function usePostComment(logId: string) {
  const qc = useQueryClient();
  return useMutation<{ id: string }, Error, { body: string }>({
    mutationFn: async ({ body }) => {
      const res = await fetch(`/api/reading-logs/${logId}/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body }),
      });
      if (!res.ok) {
        const e = await res.json();
        throw new Error(e.error || 'Failed to post comment');
      }
      return res.json();
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['log-comments', logId] });
      // The post denormalizes lastComment* onto the log → refresh the feed.
      qc.invalidateQueries({ queryKey: ['reading-logs'] });
    },
  });
}

export function useCreateTeacherLog() {
  const qc = useQueryClient();
  return useMutation<
    { id: string },
    Error,
    { studentId: string; date: string; minutesRead: number; bookTitles: string[]; notes?: string }
  >({
    mutationFn: async (input) => {
      const res = await fetch('/api/reading-logs', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(input),
      });
      if (!res.ok) {
        const e = await res.json();
        throw new Error(e.error || 'Failed to log reading');
      }
      return res.json();
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['reading-logs'] });
      qc.invalidateQueries({ queryKey: ['students'] });
    },
  });
}

export function useMarkCommentsRead(logId: string) {
  const qc = useQueryClient();
  return useMutation<{ ok: boolean }, Error, void>({
    mutationFn: async () => {
      const res = await fetch(`/api/reading-logs/${logId}/mark-read`, { method: 'POST' });
      if (!res.ok) throw new Error('Failed to mark read');
      return res.json();
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['reading-logs'] });
    },
  });
}
