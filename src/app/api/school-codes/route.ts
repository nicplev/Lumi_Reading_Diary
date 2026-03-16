import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { createSchoolCode } from "@/lib/firestore/school-codes";
import { getSchool } from "@/lib/firestore/schools";
import { createSchoolCodeSchema } from "@/lib/validations/school-code";

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const parsed = createSchoolCodeSchema.parse(body);

    const school = await getSchool(parsed.schoolId);
    if (!school) {
      return NextResponse.json({ error: "School not found" }, { status: 404 });
    }

    const result = await createSchoolCode({
      schoolId: parsed.schoolId,
      schoolName: school.name,
      createdBy: session.uid,
      maxUsages: parsed.maxUsages,
      expiresInDays: parsed.expiresInDays,
    });

    return NextResponse.json(result, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create school code error:", error);
    return NextResponse.json(
      { error: "Failed to create school code" },
      { status: 500 }
    );
  }
}
