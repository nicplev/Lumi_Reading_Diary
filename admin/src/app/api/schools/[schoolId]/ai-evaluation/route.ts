import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import {
  getAiEvaluationSchoolConfig,
  setAiEvaluationSchoolConfig,
  ServerOpsValidationError,
} from "@lumi/server-ops";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { schoolId } = await params;
  const config = await getAiEvaluationSchoolConfig(getAdminDb(), schoolId);
  return NextResponse.json(config);
}

export async function PUT(
  request: Request,
  { params }: { params: Promise<{ schoolId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { schoolId } = await params;
  try {
    const body = await request.json();
    const config = await setAiEvaluationSchoolConfig(
      getAdminDb(),
      { uid: session.uid, email: session.email },
      {
        schoolId,
        enabled: body.enabled === true,
        capPerDay: Number(body.capPerDay),
        plan: body.plan,
        notes: body.notes,
        termsVersionAccepted: body.termsVersionAccepted,
      }
    );
    return NextResponse.json(config);
  } catch (err) {
    if (err instanceof ServerOpsValidationError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    throw err;
  }
}
