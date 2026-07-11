import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { jwtVerify } from 'jose';

// Unauthenticated routes: the session-cookie API endpoints, plus the public
// legal/support pages (Privacy Policy, Terms of Use, Support) that the mobile
// app links to and that Apple App Review must reach without signing in.
const publicPaths = ['/api/auth/session', '/api/auth/logout', '/legal', '/support'];

/**
 * API paths that MUST be reachable even with non-GET methods during an active
 * impersonation session — e.g. the user has to be able to end their own
 * session and log out cleanly. Everything else is locked to read-only.
 */
const impersonationWhitelist = new Set<string>([
  '/api/auth/logout',
  '/api/auth/session',
  '/api/auth/me',
  '/api/dev/impersonate/end',
]);

function getSecret() {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error('SESSION_SECRET environment variable is required');
  return new TextEncoder().encode(secret);
}

async function getSessionData(sessionValue: string): Promise<Record<string, unknown> | null> {
  try {
    const { payload } = await jwtVerify(sessionValue, getSecret(), {
      algorithms: ['HS256'],
    });
    return payload as Record<string, unknown>;
  } catch {
    // Invalid or unsigned cookie — never trust it. (A plain-JSON fallback here
    // would let anyone forge an admin session by setting the cookie by hand.)
    return null;
  }
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Allow public paths
  if (publicPaths.some((path) => pathname.startsWith(path))) {
    return NextResponse.next();
  }

  // ── Impersonation enforcement (runs BEFORE the /api/ passthrough so API
  // mutations are locked regardless of what the handler does) ──────────────
  // Read the session up-front so both API and page requests can consult it.
  const cookie = request.cookies.get('__session');
  const decodedSession = cookie?.value ? await getSessionData(cookie.value) : null;
  // Do not let an admin cookie minted before mandatory MFA pass the edge
  // convenience check. API handlers independently enforce the same invariant
  // through getSession().
  const sessionData =
    decodedSession?.role === 'schoolAdmin' &&
    decodedSession.mfaVerified !== true &&
    decodedSession.mfaExemptReason !== 'isolatedDemoReadOnly'
      ? null
      : decodedSession;
  const impersonation = sessionData?.impersonation as
    | { expiresAt?: number }
    | undefined;

  // The public demo administrator deliberately skips MFA, so its portal
  // session is read-only. This prevents the shared demo password from being
  // used to create accounts, send email, delete records, or change settings.
  if (
    sessionData?.mfaExemptReason === 'isolatedDemoReadOnly' &&
    !['GET', 'HEAD', 'OPTIONS'].includes(request.method.toUpperCase())
  ) {
    return NextResponse.json(
      { error: 'The demo administrator is read-only.' },
      { status: 403 },
    );
  }

  if (impersonation) {
    // Expired → force the client out. Middleware cannot call the end-session
    // Cloud Function itself; cleanup will happen when the client notices the
    // 401 or the scheduled `expireImpersonationSessions` function runs.
    if (
      typeof impersonation.expiresAt === 'number' &&
      impersonation.expiresAt < Date.now()
    ) {
      const response = pathname.startsWith('/api/')
        ? NextResponse.json(
            { error: 'Impersonation session expired.' },
            { status: 401 },
          )
        : NextResponse.redirect(new URL('/login', request.url));
      response.cookies.delete('__session');
      return response;
    }

    // Non-read methods are blocked everywhere except the small whitelist.
    const method = request.method.toUpperCase();
    const isRead = method === 'GET' || method === 'HEAD' || method === 'OPTIONS';
    const isWhitelisted = Array.from(impersonationWhitelist).some((p) =>
      pathname.startsWith(p),
    );
    if (!isRead && !isWhitelisted) {
      return NextResponse.json(
        {
          error:
            'Impersonation is read-only. Exit the session to perform this action.',
        },
        { status: 403 },
      );
    }
  }

  // Allow API routes that handle their own auth
  if (pathname.startsWith('/api/')) {
    return NextResponse.next();
  }

  // If on /login, redirect authenticated users to /dashboard
  if (pathname === '/login') {
    if (sessionData) {
      return NextResponse.redirect(new URL('/dashboard', request.url));
    }
    return NextResponse.next();
  }

  // Check for session cookie
  if (!cookie?.value) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('from', pathname);
    return NextResponse.redirect(loginUrl);
  }

  // Verify session
  if (!sessionData) {
    const loginUrl = new URL('/login', request.url);
    const response = NextResponse.redirect(loginUrl);
    response.cookies.delete('__session');
    return response;
  }

  // Admin-only routes
  const adminOnlyPaths = ['/users', '/parent-links', '/analytics', '/settings'];
  // The Students *list* (/students) is admin-only, but teachers must still reach
  // individual student profiles (/students/[id]) from their class, the dashboard
  // widgets, reading groups, etc. — so match the list exactly, not by prefix.
  const isAdminOnly =
    adminOnlyPaths.some((path) => pathname.startsWith(path)) || pathname === '/students';
  if (isAdminOnly && sessionData.role !== 'schoolAdmin') {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|fonts|images|characters|blobs|staff-characters).*)',
  ],
};
