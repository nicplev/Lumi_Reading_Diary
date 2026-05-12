import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { listClasses } from "@/lib/firestore/classes";
import { logAuditEvent } from "@/lib/firestore/audit-log";
import { bulkStudentRowSchema, MAX_BULK_ROWS } from "@/lib/validations/bulk";

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { schoolId, students } = body;

    if (!schoolId || !Array.isArray(students)) {
      return NextResponse.json(
        { error: "schoolId and students array are required" },
        { status: 400 }
      );
    }

    if (students.length > MAX_BULK_ROWS) {
      return NextResponse.json(
        { error: `Maximum ${MAX_BULK_ROWS} rows per import` },
        { status: 400 }
      );
    }

    if (students.length === 0) {
      return NextResponse.json(
        { error: "No students to import" },
        { status: 400 }
      );
    }

    // Resolve class names to IDs
    const classes = await listClasses(schoolId);
    const classNameMap = new Map(
      classes.map((c) => [c.name.toLowerCase(), c.id])
    );

    const db = getAdminDb();
    const studentsCol = db
      .collection("schools")
      .doc(schoolId)
      .collection("students");

    const errors: { row: number; message: string }[] = [];
    let created = 0;

    // Process in batches of 500
    let batch = db.batch();
    let batchCount = 0;

    for (let i = 0; i < students.length; i++) {
      const row = students[i];
      const result = bulkStudentRowSchema.safeParse(row);

      if (!result.success) {
        errors.push({
          row: i + 1,
          message: result.error.issues.map((e) => e.message).join(", "),
        });
        continue;
      }

      const classId = classNameMap.get(result.data.className.toLowerCase());
      if (!classId) {
        errors.push({
          row: i + 1,
          message: `Class "${result.data.className}" not found`,
        });
        continue;
      }

      const docRef = studentsCol.doc();
      batch.set(docRef, {
        firstName: result.data.firstName,
        lastName: result.data.lastName,
        studentId: result.data.studentId || null,
        classId,
        currentReadingLevel: result.data.currentReadingLevel || null,
        parentIds: [],
        levelHistory: [],
        isActive: true,
        createdAt: FieldValue.serverTimestamp(),
      });

      created += 1;
      batchCount += 1;

      if (batchCount === 500) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    logAuditEvent({
      action: "student.bulkImport",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "student",
      targetId: schoolId,
      schoolId,
      after: { created, errors: errors.length, totalRows: students.length },
    }).catch(console.error);

    return NextResponse.json({ created, errors });
  } catch (error) {
    console.error("Bulk student import error:", error);
    return NextResponse.json(
      { error: "Failed to import students" },
      { status: 500 }
    );
  }
}
