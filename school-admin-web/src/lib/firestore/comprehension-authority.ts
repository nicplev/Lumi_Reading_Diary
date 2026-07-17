import { Timestamp } from 'firebase-admin/firestore';
import { adminDb } from '@/lib/firebase/admin';
import {
  AUDIO_AUTHORITY_VERSION,
  type AudioAuthorityDecision,
  hasCurrentAudioAuthority,
  isAllowedAudioRetentionDays,
} from '@/lib/comprehension-authority';

export class AudioAuthorityRequiredError extends Error {
  constructor() {
    super('School authority and a retention period are required before recording can be enabled.');
    this.name = 'AudioAuthorityRequiredError';
  }
}

interface AudioPreferenceUpdate {
  enabled: boolean;
  authorityDecision?: AudioAuthorityDecision;
}

interface AudioPreferenceActor {
  uid: string;
  role: 'schoolAdmin';
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? value as Record<string, unknown>
    : {};
}

export async function updateComprehensionRecordingPreference(
  schoolId: string,
  input: AudioPreferenceUpdate,
  actor: AudioPreferenceActor,
): Promise<void> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const auditRef = adminDb.collection('adminAuditLog').doc();

  await adminDb.runTransaction(async (transaction) => {
    const schoolSnap = await transaction.get(schoolRef);
    if (!schoolSnap.exists) throw new Error('School not found');

    const school = schoolSnap.data() ?? {};
    const currentSettings = asRecord(school.settings);
    const currentAudio = asRecord(currentSettings.comprehensionRecording);
    const currentAuthorityValid = hasCurrentAudioAuthority(currentAudio);
    const decision = input.authorityDecision;

    if (input.enabled && !currentAuthorityValid && !decision) {
      throw new AudioAuthorityRequiredError();
    }
    if (decision && !isAllowedAudioRetentionDays(decision.retentionDays)) {
      throw new AudioAuthorityRequiredError();
    }

    const now = Timestamp.now();
    const nextAudio: Record<string, unknown> = {
      ...currentAudio,
      enabled: input.enabled,
      updatedAt: now,
    };

    if (decision) {
      nextAudio.authorityVersion = AUDIO_AUTHORITY_VERSION;
      nextAudio.authorityConfirmedAt = now;
      nextAudio.authorityConfirmedBy = actor.uid;
      nextAudio.authorityConfirmedByRole = actor.role;
      nextAudio.authorisedBySchool = true;
      nextAudio.familyNoticeConfirmed = true;
      nextAudio.retentionDays = decision.retentionDays;
    }
    if (input.enabled && !isAllowedAudioRetentionDays(nextAudio.retentionDays)) {
      throw new AudioAuthorityRequiredError();
    }

    transaction.update(schoolRef, {
      'settings.comprehensionRecording': nextAudio,
    });
    transaction.create(auditRef, {
      action: decision
        ? 'comprehensionAudio.authorityConfirmed'
        : input.enabled
          ? 'comprehensionAudio.enabled'
          : 'comprehensionAudio.disabled',
      performedBy: actor.uid,
      performedByRole: actor.role,
      targetType: 'school',
      targetId: schoolId,
      metadata: {
        enabled: input.enabled,
        retentionDays: nextAudio.retentionDays ?? null,
        authorityVersion: nextAudio.authorityVersion ?? null,
        authorisedBySchool: decision?.authorisedBySchool ?? null,
        familyNoticeConfirmed: decision?.familyNoticeConfirmed ?? null,
      },
      createdAt: now,
    });
  });
}
