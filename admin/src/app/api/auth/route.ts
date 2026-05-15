import { NextResponse } from "next/server";
import { getAdminAuth } from "@/lib/firebase-admin";
import { isSuperAdminViaFirestore } from "@/lib/auth-firestore";
import { createSession, destroySession } from "@/lib/auth";

export async function POST(request: Request) {
  try {
    const { idToken } = await request.json();
    if (!idToken) {
      return NextResponse.json(
        { error: "Missing ID token" },
        { status: 400 }
      );
    }

    // Verify the ID token
    const decoded = await getAdminAuth().verifyIdToken(idToken);

    // Gate on /superAdmins membership — same source of truth as Cloud Functions
    if (!(await isSuperAdminViaFirestore(decoded.uid))) {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 403 }
      );
    }

    // Check auth_time freshness (must be within 5 minutes)
    const authTime = decoded.auth_time;
    const fiveMinutesAgo = Math.floor(Date.now() / 1000) - 5 * 60;
    if (authTime < fiveMinutesAgo) {
      return NextResponse.json(
        { error: "Session too old. Please sign in again." },
        { status: 401 }
      );
    }

    await createSession(idToken);
    return NextResponse.json({ status: "success" });
  } catch (error) {
    console.error("Auth error:", error);
    return NextResponse.json(
      { error: "Authentication failed" },
      { status: 401 }
    );
  }
}

export async function DELETE() {
  await destroySession();
  return NextResponse.json({ status: "success" });
}
