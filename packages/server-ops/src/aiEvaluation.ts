import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";
import {
  AI_EVAL_AUTHORITY_VERSION,
  schoolAiEvaluationEnabled,
} from "./aiEvalAuthority";

// AI comprehension-evaluation controls (super-admin portal only).
//
// Two write surfaces, both fail-closed on the reader side:
//  - platformConfig/aiEvaluation  — the global kill switch (client-readable;
//    ONLY `enabled === true` opens anything).
//  - schools/{id}.settings.aiEvaluation + deny-all
//    schools/{id}/adminMeta/aiEvaluation — per-school entitlement and
//    commercial fields (capPerDay/plan/notes are never teacher-visible).
// Every entitlement change recomputes the derived global daily cap in
// aiEvalOpsConfig/runtime: max(default, ceil(1.2 × Σ enabled capPerDay)).

const PLATFORM_FLAG_PATH = "platformConfig/aiEvaluation";
const OPS_CONFIG_PATH = "aiEvalOpsConfig/runtime";
export const AI_EVAL_DEFAULT_GLOBAL_DAILY_CAP = 1000;
export const AI_EVAL_DEFAULT_SCHOOL_CAP = 200;

export interface AiEvaluationPlatformFlag {
  enabled: boolean;
  updatedAt: string | null;
  updatedBy?: string;
  updatedByEmail?: string;
  reason?: string;
}

export interface AiEvaluationSchoolConfig {
  enabled: boolean;
  capPerDay: number;
  plan: string;
  notes: string;
  /** The version the school was last confirmed against, "" if never. */
  authorityVersion: string;
  /** The version a fresh confirmation would record. */
  currentAuthorityVersion: string;
  /**
   * True only when the entitlement actually opens the gate — i.e. what
   * functions/src/ai_evaluation/gates.ts would decide. `enabled` alone can
   * be true while this is false, for a school confirmed under superseded
   * terms or never properly confirmed at all.
   */
  authorityCurrent: boolean;
  authorityConfirmedAt: string | null;
  authorityConfirmedByEmail?: string;
  updatedAt: string | null;
  updatedByEmail?: string;
  usageMonth?: string;
  usage?: Record<string, number> | null;
}

function toISO(value: unknown): string | null {
  if (!value || typeof value !== "object") return null;
  const anyValue = value as { toDate?: () => Date };
  if (typeof anyValue.toDate === "function") {
    return anyValue.toDate().toISOString();
  }
  return null;
}

export async function getAiEvaluationPlatformFlag(
  db: Firestore
): Promise<AiEvaluationPlatformFlag> {
  const snap = await db.doc(PLATFORM_FLAG_PATH).get();
  const data = snap.data() ?? {};
  return {
    enabled: data.enabled === true,
    updatedAt: toISO(data.updatedAt),
    updatedBy: typeof data.updatedBy === "string" ? data.updatedBy : undefined,
    updatedByEmail:
      typeof data.updatedByEmail === "string" ? data.updatedByEmail : undefined,
    reason: typeof data.reason === "string" ? data.reason : undefined,
  };
}

const platformParams = z.object({
  enabled: z.boolean(),
  reason: z.string().trim().max(500).optional(),
});

export async function setAiEvaluationPlatformFlag(
  db: Firestore,
  actor: Actor,
  params: { enabled: boolean; reason?: string }
): Promise<AiEvaluationPlatformFlag> {
  const parsed = platformParams.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError("Invalid platform flag input");
  }
  if (!parsed.data.enabled && !parsed.data.reason) {
    throw new ServerOpsValidationError(
      "A reason is required when disabling AI evaluation platform-wide"
    );
  }
  // Full set (no merge) so a stale `reason` never survives a re-enable —
  // mirrors the comprehensionRecording kill-switch writer.
  await db.doc(PLATFORM_FLAG_PATH).set({
    enabled: parsed.data.enabled,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: actor.uid,
    ...(actor.email ? { updatedByEmail: actor.email } : {}),
    ...(parsed.data.reason ? { reason: parsed.data.reason } : {}),
  });
  await logAuditEvent(db, {
    action: parsed.data.enabled
      ? "ai_evaluation_platform_enabled"
      : "ai_evaluation_platform_disabled",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "platformConfig",
    targetId: "aiEvaluation",
    metadata: parsed.data.reason ? { reason: parsed.data.reason } : {},
  });
  return getAiEvaluationPlatformFlag(db);
}

export async function getAiEvaluationSchoolConfig(
  db: Firestore,
  schoolId: string
): Promise<AiEvaluationSchoolConfig> {
  if (!schoolId) throw new ServerOpsValidationError("schoolId required");
  const [schoolSnap, metaSnap, usageSnap] = await Promise.all([
    db.doc(`schools/${schoolId}`).get(),
    db.doc(`schools/${schoolId}/adminMeta/aiEvaluation`).get(),
    db.doc(`schools/${schoolId}/meta/aiEvalUsage`).get(),
  ]);
  const settings = (schoolSnap.data()?.settings ?? {}) as Record<
    string,
    unknown
  >;
  const ai = (settings.aiEvaluation ?? {}) as Record<string, unknown>;
  const meta = metaSnap.data() ?? {};
  const month = new Date().toISOString().slice(0, 7);
  const usageRaw = usageSnap.data()?.[month];
  const usage =
    usageRaw && typeof usageRaw === "object"
      ? Object.fromEntries(
          Object.entries(usageRaw as Record<string, unknown>).filter(
            (entry): entry is [string, number] => typeof entry[1] === "number"
          )
        )
      : null;
  return {
    enabled: ai.enabled === true,
    capPerDay:
      typeof meta.capPerDay === "number"
        ? meta.capPerDay
        : AI_EVAL_DEFAULT_SCHOOL_CAP,
    plan: typeof meta.plan === "string" ? meta.plan : "",
    notes: typeof meta.notes === "string" ? meta.notes : "",
    authorityVersion:
      typeof ai.authorityVersion === "string" ? ai.authorityVersion : "",
    currentAuthorityVersion: AI_EVAL_AUTHORITY_VERSION,
    authorityCurrent: schoolAiEvaluationEnabled(schoolSnap.data()),
    authorityConfirmedAt: toISO(ai.authorityConfirmedAt),
    authorityConfirmedByEmail:
      typeof ai.authorityConfirmedByEmail === "string"
        ? ai.authorityConfirmedByEmail
        : undefined,
    updatedAt: toISO(ai.updatedAt) ?? toISO(meta.updatedAt),
    updatedByEmail:
      typeof meta.updatedByEmail === "string" ? meta.updatedByEmail : undefined,
    usageMonth: month,
    usage,
  };
}

const schoolParams = z.object({
  schoolId: z.string().trim().min(1),
  enabled: z.boolean(),
  capPerDay: z.number().int().min(0).max(10000),
  plan: z.string().trim().max(100).optional().default(""),
  notes: z.string().trim().max(2000).optional().default(""),
  // An explicit attestation, not free text. The caller must send the exact
  // current authority version; the portal sources it from the same constant
  // the reader gate checks, so a stale client cannot enable a school under
  // superseded terms.
  authorityVersion: z.string().trim().max(100).optional().default(""),
});

export async function setAiEvaluationSchoolConfig(
  db: Firestore,
  actor: Actor,
  params: z.input<typeof schoolParams>
): Promise<AiEvaluationSchoolConfig> {
  const parsed = schoolParams.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError("Invalid school AI-evaluation input");
  }
  const { schoolId, enabled, capPerDay, plan, notes, authorityVersion } =
    parsed.data;
  const schoolRef = db.doc(`schools/${schoolId}`);
  const schoolSnap = await schoolRef.get();
  if (!schoolSnap.exists) {
    throw new ServerOpsValidationError("School not found");
  }
  // Must match exactly. The previous check accepted any non-empty string,
  // which let the pilot school go live with the UI label text as its
  // "accepted terms" — evidence that proved nothing.
  if (enabled && authorityVersion !== AI_EVAL_AUTHORITY_VERSION) {
    throw new ServerOpsValidationError(
      "Confirm the current AI evaluation terms before enabling this school"
    );
  }

  const batch = db.batch();
  batch.set(
    schoolRef,
    {
      settings: {
        aiEvaluation: enabled
          ? {
              enabled: true,
              authorityVersion: AI_EVAL_AUTHORITY_VERSION,
              authorityConfirmedAt: FieldValue.serverTimestamp(),
              authorityConfirmedBy: actor.uid,
              ...(actor.email
                ? { authorityConfirmedByEmail: actor.email }
                : {}),
              updatedAt: FieldValue.serverTimestamp(),
            }
          : // Disabling clears the evidence, so re-enabling requires a fresh
            // confirmation rather than silently reviving a stale one.
            {
              enabled: false,
              authorityVersion: FieldValue.delete(),
              authorityConfirmedAt: FieldValue.delete(),
              authorityConfirmedBy: FieldValue.delete(),
              authorityConfirmedByEmail: FieldValue.delete(),
              updatedAt: FieldValue.serverTimestamp(),
            },
      },
    },
    { merge: true }
  );
  batch.set(
    db.doc(`schools/${schoolId}/adminMeta/aiEvaluation`),
    {
      capPerDay,
      plan,
      notes,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: actor.uid,
      ...(actor.email ? { updatedByEmail: actor.email } : {}),
    },
    { merge: true }
  );
  await batch.commit();

  const globalDailyCap = await recomputeAiEvalGlobalDailyCap(db);
  await logAuditEvent(db, {
    action: enabled
      ? "ai_evaluation_school_enabled"
      : "ai_evaluation_school_disabled",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "school",
    targetId: schoolId,
    schoolId,
    after: { enabled, capPerDay, plan },
    metadata: { globalDailyCap },
  });
  return getAiEvaluationSchoolConfig(db, schoolId);
}

// Derived, never hand-set: max(default, ceil(1.2 × Σ enabled schools' caps)).
export async function recomputeAiEvalGlobalDailyCap(
  db: Firestore
): Promise<number> {
  const entitled = await db
    .collection("schools")
    .where("settings.aiEvaluation.enabled", "==", true)
    .get();
  let sum = 0;
  for (const doc of entitled.docs) {
    const meta = await db
      .doc(`schools/${doc.id}/adminMeta/aiEvaluation`)
      .get();
    const cap = meta.data()?.capPerDay;
    sum += typeof cap === "number" ? cap : AI_EVAL_DEFAULT_SCHOOL_CAP;
  }
  const globalDailyCap = Math.max(
    AI_EVAL_DEFAULT_GLOBAL_DAILY_CAP,
    Math.ceil(sum * 1.2)
  );
  await db
    .doc(OPS_CONFIG_PATH)
    .set(
      { globalDailyCap, globalDailyCapUpdatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  return globalDailyCap;
}
