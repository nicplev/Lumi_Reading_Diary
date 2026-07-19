import "server-only";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  DEMO_SCHOOL_ID_DEFAULT,
  readDemoAccessConfig,
  sydneyDayKey,
} from "@/lib/firestore/demo-access";
import {
  assertDemoControlTargetFacts,
  buildDemoControlUpdate,
  DemoControlModelError,
  readDemoControlValues,
  type DemoControlPatch,
  type DemoControlValues,
} from "@/lib/demo/control-model";

const PRODUCTION_PROJECT_ID = "lumi-ninc-au";

export class DemoControlServiceError extends Error {
  status: number;

  constructor(message: string, status = 409) {
    super(message);
    this.name = "DemoControlServiceError";
    this.status = status;
  }
}

export interface DemoControlUpdateResult extends DemoControlValues {
  updatedAtISO: string;
  updatedByEmail: string | null;
}

export async function updateLiveDemoControls(
  actor: { uid: string; email?: string },
  patch: DemoControlPatch,
  context: { onboardingId?: string } = {},
): Promise<DemoControlUpdateResult> {
  const configuredProject =
    process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? PRODUCTION_PROJECT_ID;
  const config = await readDemoAccessConfig();
  const db = getAdminDb();
  const onboardingRef = context.onboardingId
    ? db.collection("schoolOnboarding").doc(context.onboardingId)
    : null;
  const schoolRef = db.collection("schools").doc(DEMO_SCHOOL_ID_DEFAULT);
  const stateRef = db.doc("demoAccess/state");
  const platformAudioRef = db.doc("platformConfig/comprehensionRecording");
  const statusRef = db.doc("demoAccess/controlStatus");
  const auditRef = db.collection("adminAuditLog").doc();
  const now = new Date();
  const today = sydneyDayKey(now);

  try {
    return await db.runTransaction(async (transaction) => {
      const snapshots = onboardingRef
        ? await transaction.getAll(
            onboardingRef,
            schoolRef,
            stateRef,
            platformAudioRef,
          )
        : await transaction.getAll(schoolRef, stateRef, platformAudioRef);
      const onboardingSnap = onboardingRef ? snapshots[0] : null;
      const schoolSnap = snapshots[onboardingRef ? 1 : 0];
      const stateSnap = snapshots[onboardingRef ? 2 : 1];
      const platformAudioSnap = snapshots[onboardingRef ? 3 : 2];
      const state = stateSnap.data();
      assertDemoControlTargetFacts({
        projectId: configuredProject,
        configuredSchoolId: config.schoolId,
        immutableSchoolId: DEMO_SCHOOL_ID_DEFAULT,
        onboardingRequired: onboardingRef !== null,
        onboardingExists: onboardingSnap?.exists ?? false,
        onboardingStatus: onboardingSnap?.data()?.status,
        schoolExists: schoolSnap.exists,
        schoolIsDemo: schoolSnap.data()?.isDemo,
        credentialIsActiveToday:
          stateSnap.exists &&
          state?.dayKey === today &&
          state?.scrambledAt == null &&
          typeof state?.password === "string",
      });

      const before = readDemoControlValues(
        schoolSnap.data(),
        platformAudioSnap.data(),
      );
      const update = buildDemoControlUpdate(
        schoolSnap.data(),
        platformAudioSnap.data(),
        patch,
        now,
      );

      transaction.update(schoolRef, update.fields);
      transaction.set(statusRef, {
        schoolId: DEMO_SCHOOL_ID_DEFAULT,
        dayKey: today,
        controls: update.audit,
        updatedAt: now,
        updatedBy: { uid: actor.uid, email: actor.email ?? null },
      });
      transaction.set(auditRef, {
        action: "demo.controls.update",
        performedBy: actor.uid,
        performedByEmail: actor.email ?? null,
        targetType: "school",
        targetId: DEMO_SCHOOL_ID_DEFAULT,
        onboardingId: context.onboardingId ?? null,
        before: {
          audioRecordingEnabled: before.audioRecordingEnabled,
          parentCommentsEnabled: before.parentCommentsEnabled,
          freeTextCommentsEnabled: before.freeTextCommentsEnabled,
          messagingEnabled: before.messagingEnabled,
          quickLoggingEnabled: before.quickLoggingEnabled,
          commentCategoryCount: before.commentPresets.length,
          commentChipCount: before.commentPresets.reduce(
            (total, preset) => total + preset.chips.length,
            0,
          ),
        },
        after: update.audit,
        changedFields: Object.keys(patch),
        createdAt: FieldValue.serverTimestamp(),
      });

      return {
        ...update.next,
        updatedAtISO: now.toISOString(),
        updatedByEmail: actor.email ?? null,
      };
    });
  } catch (error) {
    if (error instanceof DemoControlModelError) {
      throw new DemoControlServiceError(error.message, 409);
    }
    throw error;
  }
}
