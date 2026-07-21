import { NextResponse } from "next/server";
import QRCode from "qrcode";
import { verifyFreshSuperAdmin } from "@/lib/admin-auth-guard";
import { startEnrollment, confirmEnrollment, hasMfa } from "@/lib/mfa/store";
import { createSession } from "@/lib/auth";

// TOTP enrollment (only reachable by a fresh-signed-in super-admin without an
// active factor). `start` returns the QR/secret; `confirm` verifies a code,
// activates the factor and mints the session. Re-enrolling over an existing
// factor is blocked — that path is peer-reset / break-glass, then enrol fresh.
export async function POST(request: Request) {
  try {
    const { idToken, step, code } = await request.json();

    const guard = await verifyFreshSuperAdmin(idToken);
    if (!guard.ok) {
      return NextResponse.json({ error: guard.error }, { status: guard.status });
    }
    if (await hasMfa(guard.uid)) {
      return NextResponse.json({ error: "MFA already enrolled" }, { status: 409 });
    }

    if (step === "start") {
      const { secret, otpauthUri } = await startEnrollment(
        guard.uid,
        guard.email ?? guard.uid,
      );
      const qrDataUrl = await QRCode.toDataURL(otpauthUri, { margin: 1, width: 220 });
      return NextResponse.json({ secret, otpauthUri, qrDataUrl });
    }

    if (step === "confirm") {
      if (!code || typeof code !== "string") {
        return NextResponse.json({ error: "Code required" }, { status: 400 });
      }
      if (!(await confirmEnrollment(guard.uid, code, Date.now()))) {
        return NextResponse.json({ error: "Invalid or expired code" }, { status: 401 });
      }
      await createSession(idToken);
      return NextResponse.json({ status: "success" });
    }

    return NextResponse.json({ error: "Invalid step" }, { status: 400 });
  } catch (error) {
    console.error("MFA enroll error:", error);
    return NextResponse.json({ error: "Enrollment failed" }, { status: 500 });
  }
}
