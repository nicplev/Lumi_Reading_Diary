import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

const publicPaths = ['/login', '/api/auth/session', '/api/auth/logout'];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Allow public paths
  if (publicPaths.some((path) => pathname.startsWith(path))) {
    return NextResponse.next();
  }

  // Allow API routes that handle their own auth
  if (pathname.startsWith('/api/')) {
    return NextResponse.next();
  }

  // Check for session cookie
  const session = request.cookies.get('lumi_session');
  if (!session?.value) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('from', pathname);
    return NextResponse.redirect(loginUrl);
  }

  // Verify session is valid JSON with required fields
  try {
    const data = JSON.parse(session.value);
    if (!data.uid || !data.schoolId || !data.role) {
      throw new Error('Invalid session');
    }

    // Admin-only routes
    const adminOnlyPaths = ['/users', '/parent-links', '/analytics', '/settings'];
    if (adminOnlyPaths.some((path) => pathname.startsWith(path)) && data.role !== 'schoolAdmin') {
      return NextResponse.redirect(new URL('/dashboard', request.url));
    }
  } catch {
    const loginUrl = new URL('/login', request.url);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|fonts|images).*)'],
};
