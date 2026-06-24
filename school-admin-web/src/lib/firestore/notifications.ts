import { adminDb } from '@/lib/firebase/admin';
import type { NotificationCampaign } from '@/lib/types';

function toCampaign(doc: FirebaseFirestore.DocumentSnapshot): NotificationCampaign {
  const data = doc.data()!;
  return {
    id: doc.id,
    schoolId: data.schoolId ?? '',
    title: data.title ?? '',
    body: data.body ?? '',
    messageType: data.messageType ?? 'general',
    audienceType: data.audienceType ?? 'classes',
    targetClassIds: data.targetClassIds ?? [],
    targetStudentIds: data.targetStudentIds ?? [],
    status: data.status ?? 'queued',
    scheduledFor: data.scheduledFor?.toDate() ?? null,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    createdBy: data.createdBy ?? '',
    createdByRole: data.createdByRole ?? '',
    createdByName: data.createdByName ?? '',
    recipientCounts: {
      parents: data.recipientCounts?.parents ?? 0,
      students: data.recipientCounts?.students ?? 0,
    },
    deliveryCounts: {
      inboxWritten: data.deliveryCounts?.inboxWritten ?? 0,
      pushSent: data.deliveryCounts?.pushSent ?? 0,
      pushFailed: data.deliveryCounts?.pushFailed ?? 0,
      pushSkipped: data.deliveryCounts?.pushSkipped,
    },
    errorSummary: data.errorSummary ?? null,
    sentAt: data.sentAt?.toDate() ?? null,
  };
}

/**
 * Reads campaign history. Teachers see only their own (filtered by `createdBy`),
 * matching the app's `watchCampaigns` query — the composite index
 * (createdBy ASC, createdAt DESC) already exists in firestore.indexes.json.
 */
export async function getNotificationCampaigns(
  schoolId: string,
  options?: { createdBy?: string; max?: number }
): Promise<NotificationCampaign[]> {
  const base = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('notificationCampaigns');

  const query: FirebaseFirestore.Query = options?.createdBy
    ? base.where('createdBy', '==', options.createdBy).orderBy('createdAt', 'desc')
    : base.orderBy('createdAt', 'desc');

  const snap = await query.limit(options?.max ?? 100).get();
  return snap.docs.map(toCampaign);
}
