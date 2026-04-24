import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { updateBook, deleteBook } from "@/lib/firestore/books";
import { updateBookSchema } from "@/lib/validations/book";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ schoolId: string; bookId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, bookId } = await params;
    const body = await request.json();
    const parsed = updateBookSchema.parse(body);

    await updateBook(schoolId, bookId, parsed);

    logAuditEvent({ action: "book.update", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "book", targetId: bookId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Update book error:", error);
    return NextResponse.json(
      { error: "Failed to update book" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string; bookId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, bookId } = await params;
    await deleteBook(schoolId, bookId);

    logAuditEvent({ action: "book.delete", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "book", targetId: bookId, schoolId }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Delete book error:", error);
    return NextResponse.json(
      { error: "Failed to delete book" },
      { status: 500 }
    );
  }
}
