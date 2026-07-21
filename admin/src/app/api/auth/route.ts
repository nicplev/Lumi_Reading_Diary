import { NextResponse } from "next/server";
import { verifyFreshSuperAdmin } from "@/lib/admin-auth-guard";
import { hasMfa, verifyLogin } from "@/lib/mfa/store";
import { createSession, destroySession } from "@/lib/auth";

// Login. A session cookie is minted ONLY after the TOTP second factor is
// satisfied, so the cookie's existence implies MFA passed. A super-admin with
// no factor yet is told to enrol first (the login page shows the QR flow).
export async function POST(request: Request) {
  try {
    const { idToken, code } = await request.json();

    const guard = await verifyFreshSuperAdmin(idToken);
    if (!guard.ok) {
      return NextResponse.json({ error: guard.error }, { status: guard.status });
    }

    if (!(await hasMfa(guard.uid))) {
      // No second factor enrolled — the client routes to enrollment.
      return NextResponse.json({ status: "enrollment_required" }, { status: 401 });
    }

    if (!code || typeof code !== "string") {
      return NextResponse.json({ status: "mfa_required" }, { status: 401 });
    }
    if (!(await verifyLogin(guard.uid, code, Date.now()))) {
      return NextResponse.json(
        { status: "mfa_required", error: "Invalid or expired code" },
        { status: 401 },
      );
    }

    await createSession(idToken);
    return NextResponse.json({ status: "success" });
  } catch (error) {
    console.error("Auth error:", error);
    return NextResponse.json({ error: "Authentication failed" }, { status: 401 });
  }
}

export async function DELETE() {
  await destroySession();
  return NextResponse.json({ status: "success" });
}
