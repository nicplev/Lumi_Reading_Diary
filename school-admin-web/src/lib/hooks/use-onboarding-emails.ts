'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

export interface OnboardingEmailRecord {
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
    studentId: string;
    studentName: string;
    parentEmail: string;
    linkCode: string;
    status: 'sent' | 'failed' | 'skipped';
    error?: string;
    skippedReason?: string;
  }>;
  errorSummary?: string;
}

export function useOnboardingEmails() {
  return useQuery<OnboardingEmailRecord[]>({
    queryKey: ['onboarding-emails'],
    queryFn: async () => {
      const res = await fetch('/api/onboarding-emails');
      if (!res.ok) throw new Error('Failed to fetch onboarding emails');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export function useSendOnboardingEmails() {
  const queryClient = useQueryClient();
  return useMutation<
    { id: string; status: string },
    Error,
    {
      targetStudentIds: string[];
      emailSubject?: string;
      customMessage?: string;
      generateMissingCodes?: boolean;
    }
  >({
    mutationFn: async (data) => {
      const res = await fetch('/api/onboarding-emails/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Failed to send onboarding emails');
      }
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['onboarding-emails'] });
    },
  });
}

export function usePreviewOnboardingEmail() {
  return useMutation<
    { schoolName: string; html: string },
    Error,
    { customMessage?: string }
  >({
    mutationFn: async (data) => {
      const res = await fetch('/api/onboarding-emails/preview', {
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
