import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const sessionCookie = request.cookies.get("__session")?.value;
  const { pathname, search } = request.nextUrl;

  // No cookie + protected route → redirect to login
  if (!sessionCookie) {
    if (pathname === "/login") return NextResponse.next();
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("redirect", `${pathname}${search}`);
    return NextResponse.redirect(loginUrl);
  }

  // Cookie presence alone does not prove the session is still valid. Let the
  // login page render so a revoked/expired-but-present cookie cannot bounce
  // forever between the authenticated layout and /login.

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/((?!api|_next/static|_next/image|favicon.ico).*)",
  ],
};
