import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth/session";
import { aiEvaluationEnabledForSchool } from "@/lib/firestore/comprehensionEvals";

// Read-only feature-status probe for the Settings card. There is
// deliberately NO self-service toggle: the entitlement is switched by the
// Lumi team per commercial agreement.
export async function GET() {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const enabled = await aiEvaluationEnabledForSchool(session.schoolId);
  return NextResponse.json({ enabled });
}
