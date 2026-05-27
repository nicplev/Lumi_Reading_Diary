/**
 * Lumi status worker.
 *
 * Serves /status.json out-of-band from Firebase so the app can show a
 * remote message even when Firebase itself is unreachable. KV-backed.
 */

export interface Env {
  STATUS_KV: KVNamespace;
  ADMIN_TOKEN: string;
}

const STATUS_KEY = "status:current";

const ALLOWED_SEVERITIES = ["info", "warn", "critical"] as const;
type Severity = (typeof ALLOWED_SEVERITIES)[number];

interface StatusPayload {
  version: number;
  id: string | null;
  message: string | null;
  severity: Severity;
  updatedAt: string | null;
  dismissible: boolean;
  minAppVersion: string | null;
  platforms: string[];
}

const EMPTY_STATUS: StatusPayload = {
  version: 0,
  id: null,
  message: null,
  severity: "info",
  updatedAt: null,
  dismissible: true,
  minAppVersion: null,
  platforms: ["ios", "android", "web"],
};

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

function isAuthorized(req: Request, env: Env): boolean {
  const auth = req.headers.get("Authorization") ?? "";
  return auth === `Bearer ${env.ADMIN_TOKEN}`;
}

function normalize(input: unknown): StatusPayload | null {
  if (!input || typeof input !== "object") return null;
  const body = input as Record<string, unknown>;
  const severity = (ALLOWED_SEVERITIES as readonly string[]).includes(
    body.severity as string,
  )
    ? (body.severity as Severity)
    : "info";
  return {
    version: Number(body.version) || 0,
    id: typeof body.id === "string" ? body.id : null,
    message:
      typeof body.message === "string" ? body.message.slice(0, 280) : null,
    severity,
    updatedAt: new Date().toISOString(),
    dismissible: body.dismissible !== false,
    minAppVersion:
      typeof body.minAppVersion === "string" ? body.minAppVersion : null,
    platforms: Array.isArray(body.platforms)
      ? (body.platforms as unknown[]).filter(
          (p): p is string => typeof p === "string",
        )
      : ["ios", "android", "web"],
  };
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    if (req.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    if (url.pathname !== "/status" && url.pathname !== "/status.json") {
      return new Response("not found", {
        status: 404,
        headers: CORS_HEADERS,
      });
    }

    if (req.method === "GET") {
      const cached = await env.STATUS_KV.get<StatusPayload>(STATUS_KEY, {
        type: "json",
      });
      const body = cached ?? EMPTY_STATUS;
      return jsonResponse(body, {
        headers: {
          // Edge cache 30s, no client cache (the client polls and dedupes
          // via the `version` field).
          "Cache-Control": "public, max-age=0, s-maxage=30",
        },
      });
    }

    if (req.method === "POST") {
      if (!isAuthorized(req, env)) {
        return new Response("unauthorized", {
          status: 401,
          headers: CORS_HEADERS,
        });
      }
      let parsed: unknown;
      try {
        parsed = await req.json();
      } catch {
        return new Response("invalid json", {
          status: 400,
          headers: CORS_HEADERS,
        });
      }
      const normalized = normalize(parsed);
      if (!normalized) {
        return new Response("invalid body", {
          status: 400,
          headers: CORS_HEADERS,
        });
      }
      await env.STATUS_KV.put(STATUS_KEY, JSON.stringify(normalized));
      return jsonResponse(normalized);
    }

    if (req.method === "DELETE") {
      if (!isAuthorized(req, env)) {
        return new Response("unauthorized", {
          status: 401,
          headers: CORS_HEADERS,
        });
      }
      await env.STATUS_KV.delete(STATUS_KEY);
      return jsonResponse(EMPTY_STATUS);
    }

    return new Response("method not allowed", {
      status: 405,
      headers: CORS_HEADERS,
    });
  },
};
