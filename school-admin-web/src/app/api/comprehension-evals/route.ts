import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth/session";
import {
  aiEvaluationEnabledForSchool,
  listClassEvals,
  listStudentEvals,
  teacherTeachesClass,
} from "@/lib/firestore/comprehensionEvals";

// Read-only list of AI comprehension evaluations for a class (optionally
// one student). Teacher access mirrors the app rules (must teach the
// class); schoolAdmin reads any class in their school. The feature gate is
// fail-closed and reported so the UI can render the "contact Lumi" state.
export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const classId = request.nextUrl.searchParams.get("classId")?.trim() ?? "";
  const studentId = request.nextUrl.searchParams.get("studentId")?.trim() ?? "";
  if (!classId) {
    return NextResponse.json({ error: "classId required" }, { status: 400 });
  }

  if (session.role !== "schoolAdmin") {
    const teaches = await teacherTeachesClass(
      session.schoolId,
      classId,
      session.uid
    );
    if (!teaches) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
  }

  const enabled = await aiEvaluationEnabledForSchool(session.schoolId);
  if (!enabled) {
    return NextResponse.json({ enabled: false, evals: [] });
  }

  const evals = studentId
    ? await listStudentEvals(session.schoolId, classId, studentId)
    : await listClassEvals(session.schoolId, classId);
  return NextResponse.json({ enabled: true, evals });
}
