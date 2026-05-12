import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { createBook } from "@/lib/firestore/books";
import { createBookSchema } from "@/lib/validations/book";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ schoolId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId } = await params;
    const body = await request.json();
    const parsed = createBookSchema.parse(body);

    const bookId = await createBook(schoolId, {
      ...parsed,
      addedBy: session.uid,
    });
    logAuditEvent({ action: "book.create", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "book", targetId: bookId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ id: bookId }, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create book error:", error);
    return NextResponse.json(
      { error: "Failed to create book" },
      { status: 500 }
    );
  }
}
