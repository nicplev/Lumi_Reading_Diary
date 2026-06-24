'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { httpsCallable, type HttpsCallableResult } from 'firebase/functions';
import { functions } from '@/lib/firebase/client';
import type { NotificationCampaign, NotificationAudienceType } from '@/lib/types';

export type SerializedCampaign = Omit<
  NotificationCampaign,
  'createdAt' | 'scheduledFor' | 'sentAt'
> & {
  createdAt: string;
  scheduledFor: string | null;
  sentAt: string | null;
};

export function useNotificationCampaigns() {
  return useQuery<SerializedCampaign[]>({
    queryKey: ['notification-campaigns'],
    queryFn: async () => {
      const res = await fetch('/api/notification-campaigns');
      if (!res.ok) throw new Error('Failed to fetch campaigns');
      return res.json();
    },
    staleTime: 30 * 1000,
  });
}

export interface CreateCampaignInput {
  schoolId: string;
  title: string;
  body: string;
  messageType: string;
  audienceType: NotificationAudienceType;
  classIds: string[];
  studentIds: string[];
  /** Epoch millis, or null to send immediately. */
  scheduledFor: number | null;
}

interface CreateCampaignResult {
  campaignId: string;
  status: string;
}

/**
 * Creates a campaign via the existing `createNotificationCampaign` callable —
 * the same entry point the Flutter app uses, so audience scoping, char/rate
 * limits and FCM dispatch are reused with zero logic drift. Requires the portal
 * client to be Firebase-authenticated (it already is; see auth-context).
 */
export function useCreateCampaign() {
  const queryClient = useQueryClient();
  return useMutation<CreateCampaignResult, Error, CreateCampaignInput>({
    mutationFn: async (input) => {
      const callable = httpsCallable<CreateCampaignInput, CreateCampaignResult>(
        functions,
        'createNotificationCampaign'
      );
      try {
        const result: HttpsCallableResult<CreateCampaignResult> = await callable(input);
        return result.data;
      } catch (e) {
        // FunctionsError carries the server's HttpsError message (e.g. rate limit).
        throw new Error(e instanceof Error ? e.message : 'Failed to send notification.');
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notification-campaigns'] });
    },
  });
}
