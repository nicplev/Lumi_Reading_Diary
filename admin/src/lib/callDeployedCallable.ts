import "server-only";
import { getAdminAuth } from "./firebase-admin";

// Default region for firebase-functions v1 onCall — no `.region(...)` is set in
// functions/src/impersonation.ts, so deploys land in us-central1. The
// FUNCTIONS_REGION env var lets us point at staging/emulator without code edits.
const FUNCTIONS_REGION = process.env.FUNCTIONS_REGION || "us-central1";

interface CallableEnvelope<T> {
  result?: T;
  error?: {
    message?: string;
    status?: string;
    details?: unknown;
  };
}

// Invokes a v1 onCall Cloud Function as if it were called by the super-admin
// who is currently driving this request. The dance:
//   1. Admin SDK mints a custom token for callerUid (1h validity).
//   2. We exchange it for a Firebase ID token via the Identity Toolkit REST
//      endpoint (same protocol the web SDK uses for signInWithCustomToken).
//   3. We POST { data: payload } to the callable's HTTPS endpoint with
//      Authorization: Bearer <idToken>.
//
// The custom + ID tokens are minted server-side and never leave this process.
// Both are short-lived. The exchange step is the only reason this helper
// exists: an admin session cookie isn't an ID token, and onCall context.auth
// is populated from an ID token only.
//
// Returns the CF's `result` field (the v1 callable wire format wraps the
// handler's return value as `{ result: ... }`). Throws on any non-2xx HTTP
// response or a structured callable error.
export async function callDeployedCallable<T = unknown>(
  callableName: string,
  callerUid: string,
  payload: Record<string, unknown>
): Promise<T> {
  const projectId = process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID;
  const apiKey = process.env.NEXT_PUBLIC_FIREBASE_API_KEY;
  if (!projectId) throw new Error("NEXT_PUBLIC_FIREBASE_PROJECT_ID is not set");
  if (!apiKey) throw new Error("NEXT_PUBLIC_FIREBASE_API_KEY is not set");

  const customToken = await getAdminAuth().createCustomToken(callerUid);

  const exchangeRes = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    }
  );
  if (!exchangeRes.ok) {
    const text = await exchangeRes.text();
    throw new Error(`Token exchange failed (${exchangeRes.status}): ${text}`);
  }
  const exchanged = (await exchangeRes.json()) as { idToken?: string };
  if (!exchanged.idToken) {
    throw new Error("Token exchange returned no idToken");
  }

  const callableRes = await fetch(
    `https://${FUNCTIONS_REGION}-${projectId}.cloudfunctions.net/${callableName}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${exchanged.idToken}`,
      },
      body: JSON.stringify({ data: payload }),
    }
  );

  const body = (await callableRes.json().catch(() => ({}))) as CallableEnvelope<T>;

  if (!callableRes.ok || body.error) {
    const msg =
      body.error?.message ??
      `Callable ${callableName} failed (HTTP ${callableRes.status})`;
    const err = new Error(msg) as Error & {
      callableStatus?: string;
      httpStatus?: number;
    };
    err.callableStatus = body.error?.status;
    err.httpStatus = callableRes.status;
    throw err;
  }

  return body.result as T;
}
