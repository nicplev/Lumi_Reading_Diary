// Minimal authenticated REST clients for the two Australian regional AI
// endpoints (Phase 3 — dark). Deliberately REST-over-SDK: the runtime SA's
// ADC via google-auth-library (an existing dependency), explicit regional
// URLs that can never silently re-route, and the exact request shapes
// validated by the live probes (docs/AI_EVALUATION_GEMINI_PLAN.md §12).

import {GoogleAuth} from "google-auth-library";
import {
  AI_EVAL_REGION,
  AI_EVAL_SPEECH_ENDPOINT,
  AI_EVAL_VERTEX_BASE_URL,
  assertResidencyPinned,
} from "./config";

let cachedAuth: GoogleAuth | null = null;

function auth(): GoogleAuth {
  if (!cachedAuth) {
    cachedAuth = new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/cloud-platform"],
    });
  }
  return cachedAuth;
}

export class ProviderHttpError extends Error {
  readonly status: number;
  readonly providerMessage: string;
  constructor(status: number, providerMessage: string) {
    super(`provider http ${status}`);
    this.status = status;
    this.providerMessage = providerMessage;
  }
}

async function postJson(
  url: string,
  body: unknown,
  timeoutMs: number
): Promise<unknown> {
  const client = await auth().getClient();
  try {
    const response = await client.request({
      url,
      method: "POST",
      data: body,
      timeout: timeoutMs,
      responseType: "json",
    });
    return response.data;
  } catch (err: unknown) {
    const anyErr = err as {
      response?: {status?: number, data?: unknown},
      code?: string | number,
      message?: string,
    };
    const status = anyErr.response?.status;
    if (typeof status === "number") {
      throw new ProviderHttpError(status, String(anyErr.message ?? ""));
    }
    throw err;
  }
}

function projectId(): string {
  const project =
    process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "";
  if (!project) throw new Error("project id unavailable");
  return project;
}

// POST :generateContent on the pinned Australian Vertex endpoint.
export async function vertexGenerateContent(
  model: string,
  body: unknown,
  timeoutMs: number
): Promise<unknown> {
  assertResidencyPinned(AI_EVAL_REGION);
  const url =
    `${AI_EVAL_VERTEX_BASE_URL}/v1/projects/${projectId()}` +
    `/locations/${AI_EVAL_REGION}/publishers/google/models/` +
    `${encodeURIComponent(model)}:generateContent`;
  return postJson(url, body, timeoutMs);
}

// POST :recognize (Speech-to-Text V2 sync) on the Australian endpoint.
export async function speechRecognize(
  body: unknown,
  timeoutMs: number
): Promise<unknown> {
  assertResidencyPinned(AI_EVAL_REGION);
  const url =
    `https://${AI_EVAL_SPEECH_ENDPOINT}/v2/projects/${projectId()}` +
    `/locations/${AI_EVAL_REGION}/recognizers/_:recognize`;
  return postJson(url, body, timeoutMs);
}
