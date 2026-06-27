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
 * Reads campaign history.
 * - Teachers (`createdBy`) see only their own, via the existing composite index
 *   (createdBy ASC, createdAt DESC) — matches the app's `watchCampaigns` query.
 * - Admins (`createdByRole`) see only admin-sent messages; teacher-sent ones
 *   stay in each teacher's own history. There's no (createdByRole, createdAt)
 *   index and we avoid adding one (portal convention reuses the app backend with
 *   no new indexes), so the role filter runs in memory over a padded recent
 *   window so admin messages aren't crowded out by teacher traffic.
 */
export async function getNotificationCampaigns(
  schoolId: string,
  options?: { createdBy?: string; createdByRole?: string; max?: number }
): Promise<NotificationCampaign[]> {
  const base = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('notificationCampaigns');
  const max = options?.max ?? 100;

  if (options?.createdBy) {
    const snap = await base
      .where('createdBy', '==', options.createdBy)
      .orderBy('createdAt', 'desc')
      .limit(max)
      .get();
    return snap.docs.map(toCampaign);
  }

  if (options?.createdByRole) {
    const snap = await base.orderBy('createdAt', 'desc').limit(Math.max(max, 300)).get();
    return snap.docs
      .map(toCampaign)
      .filter((c) => c.createdByRole === options.createdByRole)
      .slice(0, max);
  }

  const snap = await base.orderBy('createdAt', 'desc').limit(max).get();
  return snap.docs.map(toCampaign);
}
