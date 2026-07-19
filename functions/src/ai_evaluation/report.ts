// Student comprehension report core (Phase 7 — server slice, ships dark).
//
// Aggregation is pure and shared by the (future) app/portal PDF surfaces;
// the narrative callable is teacher-invoked, consumes AGGREGATES ONLY
// (never transcripts, never names) and is metered + daily-capped per
// school. Trend segments break at promptVersion/rubricVersion/model
// boundaries so cohorts are never silently compared across rubric changes.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {assertNotReadOnly} from "../read_only_guard";
import {errorCodeForLog} from "../log_safety";
import {
  AI_EVALUATION_FLAG_DOC,
  platformAiEvaluationEnabled,
  schoolAiEvaluationEnabled,
} from "./gates";
import {readAiEvalOpsConfig} from "./config";
import {classifyProviderResponse} from "./evaluation";
import {vertexGenerateContent} from "./vertex_rest";
import {recordSchoolMonthlyUsage} from "./metrics";

export const MIN_ASSESSABLE_FOR_REPORT = 3;
export const NARRATIVE_DAILY_CAP_PER_SCHOOL = 50;

export interface EvalForReport {
  logDate: Date | null;
  status: string;
  overallLevel: string | null;
  assessable: boolean;
  flags: string[];
  summary: string | null;
  questionCategories: string[];
  criterionScores: Array<{criterionId: string, score: number}>;
  promptVersion: number;
  rubricVersion: number;
  model: string | null;
}

export interface ReportSegment {
  promptVersion: number;
  rubricVersion: number;
  model: string | null;
  weeks: Array<{weekStart: string, levels: string[]}>;
}

export interface StudentEvalAggregates {
  evaluatedCount: number;
  assessableCount: number;
  flaggedCount: number;
  levelCounts: Record<string, number>;
  categoryAverages: Record<string, {average: number, count: number}>;
  flagCounts: Record<string, number>;
  quotes: string[];
  segments: ReportSegment[];
  insufficientData: boolean;
}

function isoWeekStart(date: Date): string {
  const d = new Date(Date.UTC(
    date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()
  ));
  const day = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  d.setUTCDate(d.getUTCDate() - (day - 1));
  return d.toISOString().slice(0, 10);
}

// Pure aggregation over a student's evals within a report period.
export function buildStudentEvalAggregates(
  evals: EvalForReport[]
): StudentEvalAggregates {
  const levelCounts: Record<string, number> = {};
  const flagCounts: Record<string, number> = {};
  const categoryTotals: Record<string, {total: number, count: number}> = {};
  const quotes: string[] = [];
  const segmentMap = new Map<string, ReportSegment>();
  let assessableCount = 0;
  let flaggedCount = 0;

  for (const item of evals) {
    if (item.flags.length > 0) flaggedCount++;
    for (const flag of item.flags) {
      flagCounts[flag] = (flagCounts[flag] ?? 0) + 1;
    }
    if (!item.assessable || !item.overallLevel) continue;
    assessableCount++;
    levelCounts[item.overallLevel] =
      (levelCounts[item.overallLevel] ?? 0) + 1;

    for (const category of item.questionCategories) {
      const bucket = categoryTotals[category] ?? {total: 0, count: 0};
      const scores = item.criterionScores;
      if (scores.length > 0) {
        const mean =
          scores.reduce((sum, c) => sum + c.score, 0) / scores.length;
        bucket.total += mean;
        bucket.count += 1;
        categoryTotals[category] = bucket;
      }
    }
    if (
      quotes.length < 3 &&
      item.summary &&
      item.summary.length >= 30
    ) {
      quotes.push(item.summary);
    }

    // Version-boundary segmentation for trend rendering.
    const key = `${item.promptVersion}|${item.rubricVersion}|${item.model}`;
    let segment = segmentMap.get(key);
    if (!segment) {
      segment = {
        promptVersion: item.promptVersion,
        rubricVersion: item.rubricVersion,
        model: item.model,
        weeks: [],
      };
      segmentMap.set(key, segment);
    }
    if (item.logDate) {
      const weekStart = isoWeekStart(item.logDate);
      let week = segment.weeks.find((w) => w.weekStart === weekStart);
      if (!week) {
        week = {weekStart, levels: []};
        segment.weeks.push(week);
      }
      week.levels.push(item.overallLevel);
    }
  }

  // Per-category averages only where >= 2 data points exist (plan rule).
  const categoryAverages: Record<string, {average: number, count: number}> = {};
  for (const [category, bucket] of Object.entries(categoryTotals)) {
    if (bucket.count >= 2) {
      categoryAverages[category] = {
        average: Math.round((bucket.total / bucket.count) * 100) / 100,
        count: bucket.count,
      };
    }
  }
  for (const segment of segmentMap.values()) {
    segment.weeks.sort((a, b) => a.weekStart.localeCompare(b.weekStart));
  }

  return {
    evaluatedCount: evals.length,
    assessableCount,
    flaggedCount,
    levelCounts,
    categoryAverages,
    flagCounts,
    quotes,
    segments: [...segmentMap.values()],
    insufficientData: assessableCount < MIN_ASSESSABLE_FOR_REPORT,
  };
}

export const NARRATIVE_RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    paragraphs: {type: "ARRAY", items: {type: "STRING"}},
  },
  required: ["paragraphs"],
};

// Aggregates-only narrative prompt — no names, no transcripts, no quotes
// beyond AI summaries the teacher already sees.
export function buildNarrativePrompt(
  aggregates: StudentEvalAggregates,
  periodLabel: string
): string {
  const data = {
    period: periodLabel,
    evaluated: aggregates.evaluatedCount,
    assessable: aggregates.assessableCount,
    levelCounts: aggregates.levelCounts,
    categoryAverages: aggregates.categoryAverages,
    commonFlags: aggregates.flagCounts,
  };
  return [
    "Write 2-3 short paragraphs for a teacher's reading report about one",
    "student's comprehension over the period, based ONLY on the JSON",
    "aggregates below. Refer to the child as \"the student\". Supportive,",
    "professional, specific; note growth areas gently. Never invent",
    "events, never mention AI mechanics, never output numbers as grades.",
    "",
    JSON.stringify(data),
  ].join("\n");
}

async function reserveNarrativeBudget(
  db: FirebaseFirestore.Firestore,
  schoolId: string
): Promise<boolean> {
  const ref = db.doc(`schools/${schoolId}/meta/aiEvalNarrativeBudget`);
  const today = new Date().toISOString().slice(0, 10);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const data = snap.data() ?? {};
    const used = data.date === today ? Number(data.count ?? 0) : 0;
    if (used + 1 > NARRATIVE_DAILY_CAP_PER_SCHOOL) return false;
    transaction.set(ref, {
      date: today,
      count: used + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

function toEvalForReport(data: Record<string, unknown>): EvalForReport {
  return {
    logDate:
      data.logDate instanceof Timestamp ? data.logDate.toDate() : null,
    status: typeof data.status === "string" ? data.status : "failed",
    overallLevel:
      typeof data.overallLevel === "string" ? data.overallLevel : null,
    assessable: data.assessable === true,
    flags: Array.isArray(data.flags) ?
      data.flags.filter((f): f is string => typeof f === "string") :
      [],
    summary: typeof data.summary === "string" ? data.summary : null,
    questionCategories: Array.isArray(data.questionCategories) ?
      data.questionCategories
        .filter((c): c is string => typeof c === "string") :
      [],
    criterionScores: Array.isArray(data.criterionScores) ?
      data.criterionScores
        .filter((c): c is Record<string, unknown> =>
          !!c && typeof c === "object")
        .map((c) => ({
          criterionId:
            typeof c.criterionId === "string" ? c.criterionId : "",
          score: typeof c.score === "number" ? c.score : 0,
        })) :
      [],
    promptVersion: Number(data.promptVersion ?? 1),
    rubricVersion: Number(data.rubricVersion ?? 1),
    model: typeof data.model === "string" ? data.model : null,
  };
}

// Teacher-invoked narrative generation. Dark: both gates fail closed.
export const generateStudentReportNarrative = onCall(
  {timeoutSeconds: 120, memory: "512MiB", maxInstances: 5},
  async (request) => {
    assertNotReadOnly(request);
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

    const data = request.data ?? {};
    const schoolId =
      typeof data.schoolId === "string" ? data.schoolId.trim() : "";
    const classId =
      typeof data.classId === "string" ? data.classId.trim() : "";
    const studentId =
      typeof data.studentId === "string" ? data.studentId.trim() : "";
    const fromMs = Number(data.fromMs);
    const toMs = Number(data.toMs);
    const periodLabel =
      typeof data.periodLabel === "string" ?
        data.periodLabel.slice(0, 60) :
        "the period";
    if (
      !schoolId || !classId || !studentId ||
      !Number.isFinite(fromMs) || !Number.isFinite(toMs) || fromMs >= toMs
    ) {
      throw new HttpsError(
        "invalid-argument",
        "schoolId, classId, studentId and a valid period are required"
      );
    }

    const db = admin.firestore();
    const [flagSnap, schoolSnap, userSnap, classSnap] = await Promise.all([
      db.doc(AI_EVALUATION_FLAG_DOC).get(),
      db.doc(`schools/${schoolId}`).get(),
      db.doc(`schools/${schoolId}/users/${uid}`).get(),
      db.doc(`schools/${schoolId}/classes/${classId}`).get(),
    ]);
    if (
      !flagSnap.exists ||
      !platformAiEvaluationEnabled(flagSnap.data()) ||
      !schoolSnap.exists ||
      !schoolAiEvaluationEnabled(schoolSnap.data())
    ) {
      throw new HttpsError(
        "failed-precondition", "AI evaluation is not enabled"
      );
    }
    const role = userSnap.data()?.role;
    const teacherIds = classSnap.data()?.teacherIds;
    const isTeacherOfClass =
      role === "teacher" &&
      Array.isArray(teacherIds) && teacherIds.includes(uid);
    if (role !== "schoolAdmin" && !isTeacherOfClass) {
      throw new HttpsError(
        "permission-denied", "Not a teacher of this class"
      );
    }

    const evalSnap = await db
      .collection(`schools/${schoolId}/comprehensionEvals`)
      .where("classId", "==", classId)
      .where("studentId", "==", studentId)
      .where("logDate", ">=", Timestamp.fromMillis(fromMs))
      .where("logDate", "<=", Timestamp.fromMillis(toMs))
      .orderBy("logDate", "desc")
      .limit(200)
      .get();
    const aggregates = buildStudentEvalAggregates(
      evalSnap.docs.map((doc) =>
        toEvalForReport((doc.data() ?? {}) as Record<string, unknown>))
    );

    if (aggregates.insufficientData) {
      return {aggregates, paragraphs: [], insufficientData: true};
    }

    if (!(await reserveNarrativeBudget(db, schoolId))) {
      throw new HttpsError(
        "resource-exhausted",
        "Daily report-narrative limit reached for this school"
      );
    }

    const cfg = await readAiEvalOpsConfig();
    let paragraphs: string[] = [];
    try {
      const response = await vertexGenerateContent(cfg.model, {
        contents: [{
          role: "user",
          parts: [{text: buildNarrativePrompt(aggregates, periodLabel)}],
        }],
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 800,
          responseMimeType: "application/json",
          responseSchema: NARRATIVE_RESPONSE_SCHEMA,
          thinkingConfig: {thinkingBudget: 0},
        },
      }, 60_000);
      const outcome = classifyProviderResponse(
        response as Parameters<typeof classifyProviderResponse>[0]
      );
      if (outcome.kind === "ok") {
        const parsed = outcome.parsed as {paragraphs?: unknown};
        if (Array.isArray(parsed.paragraphs)) {
          paragraphs = parsed.paragraphs
            .filter((p): p is string => typeof p === "string")
            .slice(0, 4);
        }
        await recordSchoolMonthlyUsage(db, schoolId, {
          narrativeCalls: 1,
          inputTokens: outcome.usage.inputTokens,
          outputTokens: outcome.usage.outputTokens,
        }, new Date());
      }
    } catch (err: unknown) {
      functions.logger.warn("aiEval.narrative.failed", {
        errorCode: errorCodeForLog(err),
      });
    }
    if (paragraphs.length === 0) {
      throw new HttpsError(
        "unavailable",
        "Couldn't generate the narrative right now — try again shortly"
      );
    }
    return {aggregates, paragraphs, insufficientData: false};
  }
);
