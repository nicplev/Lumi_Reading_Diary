import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  regenerateAdminSetupLink,
  OnboardingProvisionError,
} from "@/lib/onboarding/provision";

// POST /api/onboarding/[id]/admin-link — regenerate the school-admin's
// password-setup link (no email is sent at provision time, so this is how the
// operator re-obtains it).
export async function POST(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const result = await regenerateAdminSetupLink(
      { uid: session.uid, email: session.email ?? undefined },
      id
    );
    return NextResponse.json({ success: true, ...result });
  } catch (error) {
    if (error instanceof OnboardingProvisionError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("Regenerate admin link error:", error);
    return NextResponse.json(
      { error: "Failed to generate admin setup link" },
      { status: 500 }
    );
  }
}
