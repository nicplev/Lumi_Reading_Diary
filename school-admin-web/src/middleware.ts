import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { jwtVerify } from 'jose';

const publicPaths = ['/api/auth/session', '/api/auth/logout'];

function getSecret() {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error('SESSION_SECRET environment variable is required');
  return new TextEncoder().encode(secret);
}

async function getSessionData(sessionValue: string): Promise<Record<string, unknown> | null> {
  // Try JWT first
  try {
    const { payload } = await jwtVerify(sessionValue, getSecret());
    return payload as Record<string, unknown>;
  } catch {
    // Backward compat: try plain JSON (for existing sessions during rollout)
    try {
      const data = JSON.parse(sessionValue);
      if (data.uid && data.schoolId && data.role) {
        return data;
      }
    } catch {
      // Not valid JSON either
    }
    return null;
  }
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Allow public paths
  if (publicPaths.some((path) => pathname.startsWith(path))) {
    return NextResponse.next();
  }

  // Allow API routes that handle their own auth
  if (pathname.startsWith('/api/')) {
    return NextResponse.next();
  }

  // If on /login, redirect authenticated users to /dashboard
  if (pathname === '/login') {
    const session = request.cookies.get('lumi_session');
    if (session?.value) {
      const data = await getSessionData(session.value);
      if (data) {
        return NextResponse.redirect(new URL('/dashboard', request.url));
      }
    }
    return NextResponse.next();
  }

  // Check for session cookie
  const session = request.cookies.get('lumi_session');
  if (!session?.value) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('from', pathname);
    return NextResponse.redirect(loginUrl);
  }

  // Verify session
  const data = await getSessionData(session.value);
  if (!data) {
    const loginUrl = new URL('/login', request.url);
    return NextResponse.redirect(loginUrl);
  }

  // Admin-only routes
  const adminOnlyPaths = ['/users', '/parent-links', '/analytics', '/settings'];
  if (adminOnlyPaths.some((path) => pathname.startsWith(path)) && data.role !== 'schoolAdmin') {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|fonts|images).*)'],
};
