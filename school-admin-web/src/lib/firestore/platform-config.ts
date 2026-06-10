import { adminDb } from '@/lib/firebase/admin';

/**
 * Platform-wide kill switch managed from the super-admin portal at
 * `platformConfig/comprehensionRecording`. A missing doc means enabled —
 * the per-school toggle remains the opt-in. Fail open on read errors: the
 * per-school setting and the Storage rules backstop still apply.
 */
export async function isComprehensionRecordingGloballyEnabled(): Promise<boolean> {
  try {
    const snap = await adminDb
      .collection('platformConfig')
      .doc('comprehensionRecording')
      .get();
    return (snap.data()?.enabled as boolean | undefined) ?? true;
  } catch (error) {
    console.error('Failed to read comprehension recording platform flag:', error);
    return true;
  }
}
