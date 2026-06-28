'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

export interface StaffOnboardingEmailRecord {
  id: string;
  status: 'queued' | 'processing' | 'sent' | 'partial' | 'failed';
  createdAt: string;
  createdBy: string;
  sentAt?: string;
  emailSubject?: string;
  customMessage?: string;
  recipientCount?: number;
  deliveryCounts?: { sent: number; failed: number; skipped: number };
  recipients?: Array<{
    userId: string;
    email: string;
    status: 'sent' | 'failed' | 'skipped';
    error?: string;
    skippedReason?: string;
  }>;
  errorSummary?: string;
}

export function useStaffOnboardingEmails() {
  return useQuery<StaffOnboardingEmailRecord[]>({
    queryKey: ['staff-onboarding-emails'],
    queryFn: async () => {
      const res = await fetch('/api/staff-onboarding-emails');
      if (!res.ok) throw new Error('Failed to fetch staff onboarding emails');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useSendStaffOnboardingEmails() {
  const queryClient = useQueryClient();
  return useMutation<
    { id: string; status: string },
    Error,
    { targetUserIds: string[]; emailSubject?: string; customMessage?: string }
  >({
    mutationFn: async (data) => {
      const res = await fetch('/api/staff-onboarding-emails/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to send staff emails');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['staff-onboarding-emails'] });
    },
  });
}

export function usePreviewStaffOnboardingEmail() {
  return useMutation<
    { schoolName: string; html: string },
    Error,
    { customMessage?: string }
  >({
    mutationFn: async (data) => {
      const res = await fetch('/api/staff-onboarding-emails/preview', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to generate preview');
      }
      return res.json();
    },
  });
}
