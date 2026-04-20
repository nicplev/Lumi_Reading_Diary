import { NextRequest, NextResponse } from 'next/server';
import { createHash } from 'crypto';
import { z } from 'zod';
import { getSession } from '@/lib/auth/session';
import { hasDevAccess } from '@/lib/auth/dev-access';
import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';

// DEV-ONLY: resets a parent link code so it can be tested repeatedly.
// Flips `studentLinkCodes/{id}.status` back to `active`, removes the parent
// from the student's `parentIds`, deletes the parent doc, and drops the
// email→school index entry. Firebase Auth user is intentionally left intact.

const schema = z.object({
  code: z.string().regex(/^[A-Z0-9]{8}$/, 'Code must be 8 uppercase letters or digits'),
});

function hashEmail(email: string): string {
  return createHash('sha256').update(email.toLowerCase().trim()).digest('hex');
}

export async function POST(request: NextRequest) {
  const session = await getSession();
  // Gated on the Firestore-backed dev allowlist rather than NODE_ENV so the
  // dev can still use this in production. Returns 404 (not 403/401) so the
  // endpoint is indistinguishable from a missing route to unauthorised callers.
  if (!session || !(await hasDevAccess(session.email))) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }

  try {
    const body = await request.json();
    const { code } = schema.parse(body);

    const snapshot = await adminDb
      .collection('studentLinkCodes')
      .where('code', '==', code)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return NextResponse.json({ error: `Code ${code} not found.` }, { status: 404 });
    }

    const codeDoc = snapshot.docs[0];
    const data = codeDoc.data();

    if (data.schoolId !== session.schoolId) {
      return NextResponse.json(
        { error: 'This code belongs to a different school.' },
        { status: 403 },
      );
    }

    const usedBy: string | undefined = data.usedBy;
    const schoolId: string = data.schoolId;
    const studentId: string = data.studentId;

    let unlinkedEmail: string | null = null;

    if (usedBy) {
      const parentRef = adminDb
        .collection('schools').doc(schoolId)
        .collection('parents').doc(usedBy);
      const parentSnap = await parentRef.get();

      if (parentSnap.exists) {
        unlinkedEmail = (parentSnap.data()?.email as string | undefined) ?? null;

        await adminDb
          .collection('schools').doc(schoolId)
          .collection('students').doc(studentId)
          .update({ parentIds: FieldValue.arrayRemove(usedBy) });

        await parentRef.delete();

        try {
          await adminDb
            .collection('schools').doc(schoolId)
            .update({ parentCount: FieldValue.increment(-1) });
        } catch {
          // Non-critical; continue.
        }

        if (unlinkedEmail) {
          try {
            await adminDb
              .collection('userSchoolIndex')
              .doc(hashEmail(unlinkedEmail))
              .delete();
          } catch {
            // Tolerate missing index doc.
          }
        }
      }
    }

    await codeDoc.ref.update({
      status: 'active',
      usedBy: FieldValue.delete(),
      usedAt: FieldValue.delete(),
      revokedBy: FieldValue.delete(),
      revokedAt: FieldValue.delete(),
      revokeReason: FieldValue.delete(),
    });

    return NextResponse.json({
      ok: true,
      unlinkedParent: usedBy ? { uid: usedBy, email: unlinkedEmail } : null,
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors[0].message }, { status: 400 });
    }
    const message = error instanceof Error ? error.message : 'Failed to reset code';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
