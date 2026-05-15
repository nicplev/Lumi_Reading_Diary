import { NextResponse, type NextRequest } from "next/server";
import { verifySession } from "@/lib/auth";
import { listStudents } from "@/lib/firestore/students";
import { listReadingLogs } from "@/lib/firestore/reading-logs";
import { listAllocations } from "@/lib/firestore/allocations";
import { listClasses } from "@/lib/firestore/classes";
import { toCsvString } from "@/lib/utils/export";

export async function GET(request: NextRequest) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const searchParams = request.nextUrl.searchParams;
    const schoolId = searchParams.get("schoolId");
    const type = searchParams.get("type");

    if (!schoolId || !type) {
      return NextResponse.json(
        { error: "schoolId and type are required" },
        { status: 400 }
      );
    }

    const classes = await listClasses(schoolId);
    const classMap = new Map(classes.map((c) => [c.id, c.name]));

    let csv = "";
    let filename = "";

    if (type === "students") {
      const students = await listStudents(schoolId);
      csv = toCsvString(
        ["firstName", "lastName", "studentId", "class", "readingLevel", "parentLinked", "isActive", "createdAt"],
        students.map((s) => ({
          firstName: s.firstName,
          lastName: s.lastName,
          studentId: s.studentId ?? "",
          class: classMap.get(s.classId) ?? s.classId,
          readingLevel: s.currentReadingLevel ?? "",
          parentLinked: s.parentLinked,
          isActive: s.isActive,
          createdAt: s.createdAt,
        }))
      );
      filename = `students-${schoolId}.csv`;
    } else if (type === "readingLogs") {
      const startDate = searchParams.get("startDate") || undefined;
      const endDate = searchParams.get("endDate") || undefined;

      // Require date range for reading logs to prevent unbounded queries
      if (!startDate || !endDate) {
        return NextResponse.json(
          { error: "startDate and endDate are required for reading log exports" },
          { status: 400 }
        );
      }

      const students = await listStudents(schoolId);
      const studentMap = new Map(
        students.map((s) => [s.id, `${s.firstName} ${s.lastName}`])
      );
      const logs = await listReadingLogs(schoolId, { startDate, endDate, limit: 10000 });
      csv = toCsvString(
        ["student", "class", "date", "minutesRead", "targetMinutes", "status", "books", "feeling", "createdAt"],
        logs.map((l) => ({
          student: studentMap.get(l.studentId) ?? l.studentId,
          class: l.classId ? classMap.get(l.classId) ?? l.classId : "",
          date: l.date ? new Date(l.date).toLocaleDateString() : "",
          minutesRead: l.minutesRead,
          targetMinutes: l.targetMinutes ?? "",
          status: l.status,
          books: l.bookTitles.join("; "),
          feeling: l.childFeeling ?? "",
          createdAt: l.createdAt,
        }))
      );
      filename = `reading-logs-${schoolId}.csv`;
    } else if (type === "allocations") {
      const allocs = await listAllocations(schoolId);
      csv = toCsvString(
        ["class", "type", "cadence", "targetMinutes", "studentCount", "startDate", "endDate", "isActive", "createdAt"],
        allocs.map((a) => ({
          class: classMap.get(a.classId) ?? a.classId,
          type: a.type,
          cadence: a.cadence,
          targetMinutes: a.targetMinutes,
          studentCount: a.studentCount,
          startDate: a.startDate ? new Date(a.startDate).toLocaleDateString() : "",
          endDate: a.endDate ? new Date(a.endDate).toLocaleDateString() : "",
          isActive: a.isActive,
          createdAt: a.createdAt,
        }))
      );
      filename = `allocations-${schoolId}.csv`;
    } else {
      return NextResponse.json(
        { error: "Invalid type. Use: students, readingLogs, allocations" },
        { status: 400 }
      );
    }

    return new NextResponse(csv, {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filename}"`,
      },
    });
  } catch (error) {
    console.error("Export error:", error);
    return NextResponse.json(
      { error: "Failed to generate export" },
      { status: 500 }
    );
  }
}
