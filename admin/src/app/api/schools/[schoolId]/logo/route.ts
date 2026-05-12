import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminStorage } from "@/lib/firebase-admin";
import { updateSchool } from "@/lib/firestore/schools";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const ALLOWED_TYPES = [
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/svg+xml",
];
const MAX_SIZE = 2 * 1024 * 1024; // 2MB

function extFromMime(mime: string): string {
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/webp": "webp",
    "image/svg+xml": "svg",
  };
  return map[mime] ?? "png";
}

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
    const formData = await request.formData();
    const file = formData.get("file") as File | null;

    if (!file) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }

    if (!ALLOWED_TYPES.includes(file.type)) {
      return NextResponse.json(
        { error: "Invalid file type. Allowed: PNG, JPEG, WebP, SVG" },
        { status: 400 }
      );
    }

    if (file.size > MAX_SIZE) {
      return NextResponse.json(
        { error: "File too large. Maximum size is 2MB" },
        { status: 400 }
      );
    }

    const ext = extFromMime(file.type);
    const filePath = `schools/${schoolId}/logo.${ext}`;
    const bucket = getAdminStorage().bucket(
      process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET
    );
    const fileRef = bucket.file(filePath);

    const buffer = Buffer.from(await file.arrayBuffer());
    await fileRef.save(buffer, {
      metadata: { contentType: file.type },
    });

    const [signedUrl] = await fileRef.getSignedUrl({
      action: "read",
      expires: "2099-12-31",
    });
    const logoUrl = signedUrl;

    await updateSchool(schoolId, { logoUrl });

    logAuditEvent({
      action: "school.logo.upload",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "school",
      targetId: schoolId,
      schoolId,
      after: { logoUrl } as Record<string, unknown>,
    }).catch(console.error);

    return NextResponse.json({ logoUrl });
  } catch (error) {
    console.error("Logo upload error:", error);
    return NextResponse.json(
      { error: "Failed to upload logo" },
      { status: 500 }
    );
  }
}
