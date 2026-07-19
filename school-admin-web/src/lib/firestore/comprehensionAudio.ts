import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { adminDb, adminStorage } from '@/lib/firebase/admin';
import {
  comprehensionAudioObjectPath,
  comprehensionAudioUploadObjectPath,
} from '@/lib/comprehension-audio-policy';

// Manual cleanup helpers used by Settings > Comprehension Audio in the
// school-admin portal. school-admin-web is intentionally outside the pnpm
// workspace (it deploys as its own Hosting site), so it can't share the
// `@lumi/server-ops` helpers from packages/. The logic here mirrors
// packages/server-ops/src/comprehensionAudioActions.ts — both paths delete
// Storage objects and clear the same audio fields on the log doc.

const BATCH_SIZE = 500;
const MAX_PAGES = 50;

export interface BulkComprehensionAudioFilter {
  schoolId: string;
  startDate: string; // YYYY-MM-DD inclusive
  endDate: string; // YYYY-MM-DD inclusive
  classId?: string;
}

export interface BulkComprehensionAudioActor {
  uid: string;
  email?: string;
}

export interface BulkComprehensionAudioResult {
  deletedCount: number;
  failedCount: number;
}

function validateFilter(filter: BulkComprehensionAudioFilter): void {
  const dateRe = /^\d{4}-\d{2}-\d{2}$/;
  if (!filter.schoolId) throw new Error('schoolId is required');
  if (!dateRe.test(filter.startDate)) throw new Error('startDate must be YYYY-MM-DD');
  if (!dateRe.test(filter.endDate)) throw new Error('endDate must be YYYY-MM-DD');
  if (filter.startDate > filter.endDate) {
    throw new Error('startDate must be on or before endDate');
  }
}

function buildQuery(filter: BulkComprehensionAudioFilter) {
  const startMs = Date.parse(`${filter.startDate}T00:00:00.000Z`);
  const endMs = Date.parse(`${filter.endDate}T23:59:59.999Z`);
  let q: FirebaseFirestore.Query = adminDb
    .collection('schools')
    .doc(filter.schoolId)
    .collection('readingLogs')
    .where('comprehensionAudioUploaded', '==', true)
    .where('date', '>=', Timestamp.fromMillis(startMs))
    .where('date', '<=', Timestamp.fromMillis(endMs));
  if (filter.classId) {
    q = q.where('classId', '==', filter.classId);
  }
  return q;
}

async function deleteStorageObjectIfExists(path: string): Promise<void> {
  try {
    await adminStorage.bucket().file(path).delete();
  } catch (err: unknown) {
    const code = (err as { code?: number | string }).code;
    if (code === 404 || code === '404') return;
    throw err;
  }
}

export async function previewComprehensionAudioCount(
  filter: BulkComprehensionAudioFilter
): Promise<{ count: number }> {
  validateFilter(filter);
  const agg = await buildQuery(filter).count().get();
  return { count: agg.data().count };
}

export async function bulkDeleteComprehensionAudio(
  filter: BulkComprehensionAudioFilter,
  actor: BulkComprehensionAudioActor
): Promise<BulkComprehensionAudioResult> {
  validateFilter(filter);

  let deletedCount = 0;
  let failedCount = 0;

  for (let page = 0; page < MAX_PAGES; page++) {
    const snap = await buildQuery(filter).limit(BATCH_SIZE).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const storagePath = comprehensionAudioObjectPath(filter.schoolId, doc.id);
      const uploadPath = comprehensionAudioUploadObjectPath(filter.schoolId, doc.id);
      try {
        await deleteStorageObjectIfExists(storagePath);
        await deleteStorageObjectIfExists(uploadPath);
        await doc.ref.update({
          comprehensionAudioPath: FieldValue.delete(),
          comprehensionAudioDurationSec: FieldValue.delete(),
          comprehensionAudioUploaded: false,
          comprehensionAudioUploadedAt: FieldValue.delete(),
          comprehensionAudioObjectGeneration: FieldValue.delete(),
          comprehensionAudioSourceGeneration: FieldValue.delete(),
          comprehensionAudioValidationVersion: FieldValue.delete(),
          comprehensionAudioValidatedDurationMs: FieldValue.delete(),
          comprehensionAudioSha256: FieldValue.delete(),
          comprehensionAudioDeletedAt: FieldValue.serverTimestamp(),
        });
        deletedCount++;
      } catch (err) {
        failedCount++;
        console.error('[school-admin] bulkDeleteComprehensionAudio: per-doc failure', {
          logPath: doc.ref.path,
          storagePath,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
    if (snap.size < BATCH_SIZE) break;
  }

  await adminDb.collection('adminAuditLog').add({
    action: 'comprehensionAudio.bulkDelete',
    performedBy: actor.uid,
    performedByEmail: actor.email ?? null,
    targetType: 'school',
    targetId: filter.schoolId,
    schoolId: filter.schoolId,
    metadata: {
      startDate: filter.startDate,
      endDate: filter.endDate,
      classId: filter.classId ?? null,
      deletedCount,
      failedCount,
      source: 'manualSchoolAdminBulk',
    },
    createdAt: FieldValue.serverTimestamp(),
  });

  return { deletedCount, failedCount };
}
