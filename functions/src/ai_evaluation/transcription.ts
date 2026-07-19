// Speech-to-Text stage (Phase 3 — dark).
//
// V2 synchronous recognition against the Australian regional endpoint,
// `long` model, en-AU, automatic AAC/M4A decoding — exactly the shape
// validated by the Phase 0 spike (docs/AI_EVALUATION_PLAN.md). The worker
// always reads the CANONICAL object at its recorded generation; the
// untrusted pending namespace is never touched.

import * as admin from "firebase-admin";
import {comprehensionAudioObjectPath} from "../comprehension_retention";
import {ProviderHttpError, speechRecognize} from "./vertex_rest";

export const STT_MODEL = "long";
export const STT_LANGUAGE = "en-AU";
export const TRANSCRIPTION_PROVIDER = "google-stt-v2-long";
export const LOW_STT_CONFIDENCE_THRESHOLD = 0.5;
export const STT_TIMEOUT_MS = 60_000;

export interface TranscriptionResult {
  transcript: string;
  confidence: number;
  billedSec: number;
}

export class SttQuotaError extends Error {}
export class AudioUnavailableError extends Error {}

interface RecognizeResponseLike {
  results?: Array<{
    alternatives?: Array<{transcript?: string, confidence?: number}>;
  }>;
  metadata?: {totalBilledDuration?: string | {seconds?: number | string}};
}

// Pure: joins per-result top alternatives into one transcript.
export function joinTranscript(response: RecognizeResponseLike): string {
  const parts: string[] = [];
  for (const result of response.results ?? []) {
    const text = result.alternatives?.[0]?.transcript ?? "";
    if (text.trim()) parts.push(text.trim());
  }
  return parts.join(" ").trim();
}

// Pure: lowest per-segment confidence, 1 when the API reports none.
export function minConfidence(response: RecognizeResponseLike): number {
  let min = 1;
  let seen = false;
  for (const result of response.results ?? []) {
    const confidence = result.alternatives?.[0]?.confidence;
    if (typeof confidence === "number" && confidence > 0) {
      seen = true;
      if (confidence < min) min = confidence;
    }
  }
  return seen ? min : 1;
}

// Pure: REST returns totalBilledDuration as "7s" or {seconds: 7}.
export function billedSeconds(response: RecognizeResponseLike): number {
  const raw = response.metadata?.totalBilledDuration;
  if (typeof raw === "string") {
    const value = Number(raw.replace(/s$/i, ""));
    return Number.isFinite(value) ? value : 0;
  }
  const seconds = raw?.seconds ?? 0;
  const value = typeof seconds === "string" ? Number(seconds) : seconds;
  return Number.isFinite(value) ? Number(value) : 0;
}

export function buildRecognizeBody(bytes: Buffer): Record<string, unknown> {
  return {
    config: {
      autoDecodingConfig: {},
      model: STT_MODEL,
      languageCodes: [STT_LANGUAGE],
      features: {
        enableAutomaticPunctuation: true,
        profanityFilter: false,
      },
    },
    content: bytes.toString("base64"),
  };
}

// Downloads the canonical audio at its exact recorded generation and
// transcribes it. Throws SttQuotaError (deferral class) or
// AudioUnavailableError (skip class); anything else is retryable.
export async function transcribeCanonicalAudio(params: {
  schoolId: string,
  logId: string,
  objectGeneration: string,
}): Promise<TranscriptionResult> {
  const storagePath =
    comprehensionAudioObjectPath(params.schoolId, params.logId);
  const file = admin.storage().bucket().file(storagePath, {
    generation: params.objectGeneration,
  });
  let bytes: Buffer;
  try {
    [bytes] = await file.download();
  } catch (err: unknown) {
    const code = (err as {code?: number}).code;
    if (code === 404) {
      throw new AudioUnavailableError("canonical audio object missing");
    }
    throw err;
  }

  let response: RecognizeResponseLike;
  try {
    response = await speechRecognize(
      buildRecognizeBody(bytes),
      STT_TIMEOUT_MS
    ) as RecognizeResponseLike;
  } catch (err: unknown) {
    if (err instanceof ProviderHttpError && err.status === 429) {
      throw new SttQuotaError("speech quota exhausted");
    }
    throw err;
  }

  return {
    transcript: joinTranscript(response),
    confidence: minConfidence(response),
    billedSec: billedSeconds(response),
  };
}
