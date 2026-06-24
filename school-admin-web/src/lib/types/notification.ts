export type CampaignStatus =
  | 'queued'
  | 'scheduled'
  | 'processing'
  | 'sent'
  | 'partial'
  | 'failed';

export type NotificationAudienceType = 'students' | 'classes' | 'school';

/**
 * A staff broadcast to parents. Created by the `createNotificationCampaign`
 * Cloud Function (callable) and dispatched by `processQueuedNotificationCampaign`
 * — the portal only ever reads these for history. Shape mirrors the doc written
 * in functions/src/index.ts so the app and portal stay interoperable.
 */
export interface NotificationCampaign {
  id: string;
  schoolId: string;
  title: string;
  body: string;
  messageType: string;
  audienceType: NotificationAudienceType;
  targetClassIds: string[];
  targetStudentIds: string[];
  status: CampaignStatus;
  scheduledFor: Date | null;
  createdAt: Date;
  createdBy: string;
  createdByRole: string;
  createdByName: string;
  recipientCounts: { parents: number; students: number };
  deliveryCounts: {
    inboxWritten: number;
    pushSent: number;
    pushFailed: number;
    pushSkipped?: number;
  };
  errorSummary: string | null;
  sentAt: Date | null;
}
