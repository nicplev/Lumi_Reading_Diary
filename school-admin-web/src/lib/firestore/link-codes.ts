import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import { randomInt } from 'node:crypto';
import type { StudentLinkCode } from '@/lib/types';

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude I/O/0/1

function generateCode(): string {
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += CODE_CHARS[randomInt(CODE_CHARS.length)];
  }
  return code;
}

async function isCodeUnique(code: string): Promise<boolean> {
  const snap = await adminDb
    .collection('studentLinkCodes')
    .where('code', '==', code)
    .limit(1)
    .get();
  return snap.empty;
}

async function generateUniqueCode(): Promise<string> {
  for (let i = 0; i < 40; i++) {
    const code = generateCode();
    if (await isCodeUnique(code)) return code;
  }
  throw new Error('Unable to generate unique link code after max attempts');
}

function toLinkCode(doc: FirebaseFirestore.DocumentSnapshot): StudentLinkCode {
  const data = doc.data()!;
  return {
    id: doc.id,
    code: data.code ?? '',
    schoolId: data.schoolId ?? '',
    studentId: data.studentId ?? '',
    studentName: data.studentName ?? data.metadata?.studentFullName ?? '',
    classId: data.classId ?? '',
    status: data.status ?? 'active',
    // Legacy codes predate this field — treat them as staff-issued.
    intendedFor: data.intendedFor ?? 'staff_issued',
    note: data.note,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    expiresAt: data.expiresAt?.toDate() ?? new Date(),
    usedAt: data.usedAt?.toDate(),
    usedBy: data.usedBy,
    createdBy: data.createdBy ?? '',
  };
}

export async function getLinkCodes(schoolId: string): Promise<StudentLinkCode[]> {
  const snap = await adminDb
    .collection('studentLinkCodes')
    .where('schoolId', '==', schoolId)
    .orderBy('createdAt', 'desc')
    .get();
  return snap.docs.map(toLinkCode);
}

export async function createLinkCode(
  schoolId: string,
  studentId: string,
  createdBy: string
): Promise<StudentLinkCode> {
  const code = await generateUniqueCode();

  // Fetch student name
  const studentDoc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(studentId)
    .get();

  let studentName = '';
  let classId = '';
  if (studentDoc.exists) {
    const sd = studentDoc.data()!;
    studentName = `${sd.firstName ?? ''} ${sd.lastName ?? ''}`.trim();
    classId = sd.classId ?? '';
  }

  // Supersede existing active codes for this student — but ONLY staff-issued
  // ones. A pending co_parent_invite (created by a guardian inviting another
  // guardian) must survive a staff regeneration, so it is left untouched.
  const activeCodes = await adminDb
    .collection('studentLinkCodes')
    .where('studentId', '==', studentId)
    .where('status', '==', 'active')
    .get();

  const batch = adminDb.batch();
  for (const codeDoc of activeCodes.docs) {
    // Legacy codes (no intendedFor) are treated as staff-issued.
    if (codeDoc.data().intendedFor === 'co_parent_invite') continue;
    batch.update(codeDoc.ref, {
      status: 'revoked',
      revokedBy: createdBy,
      revokedAt: FieldValue.serverTimestamp(),
      revokeReason: 'Superseded by newly generated link code',
    });
  }

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 30);

  const ref = adminDb.collection('studentLinkCodes').doc();
  batch.set(ref, {
    code,
    schoolId,
    studentId,
    studentName,
    classId,
    status: 'active',
    // The admin portal only ever issues staff codes; guardian-initiated
    // co-parent invites are created from the parent app.
    intendedFor: 'staff_issued',
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
    createdBy,
    metadata: { studentFullName: studentName },
  });

  await batch.commit();

  return {
    id: ref.id,
    code,
    schoolId,
    studentId,
    studentName,
    classId,
    status: 'active',
    intendedFor: 'staff_issued',
    createdAt: new Date(),
    expiresAt,
    createdBy,
  };
}

export async function revokeLinkCode(codeId: string, revokedBy: string, schoolId: string): Promise<void> {
  const ref = adminDb.collection('studentLinkCodes').doc(codeId);
  const snap = await ref.get();
  // studentLinkCodes is a TOP-LEVEL collection, so a bare .doc(codeId) update
  // would let a staff member of one school revoke another school's codes.
  // Prove tenant ownership first (mirrors link-codes/reset).
  if (!snap.exists || snap.data()?.schoolId !== schoolId) throw new Error('Code not found');
  await ref.update({
    status: 'revoked',
    revokedBy,
    revokedAt: FieldValue.serverTimestamp(),
    revokeReason: 'Manually revoked by staff',
  });
}

export async function deleteLinkCode(codeId: string, schoolId: string): Promise<void> {
  const ref = adminDb.collection('studentLinkCodes').doc(codeId);
  const snap = await ref.get();
  // Tenant ownership check — codeId is client-supplied against a top-level
  // collection, so it must belong to the caller's school.
  if (!snap.exists || snap.data()?.schoolId !== schoolId) throw new Error('Code not found');
  if (snap.data()?.status !== 'revoked') throw new Error('Only revoked codes can be permanently deleted');
  await ref.delete();
}

export async function bulkCreateLinkCodes(
  schoolId: string,
  studentIds: string[],
  createdBy: string
): Promise<{ created: StudentLinkCode[]; failedStudentIds: string[] }> {
  const unique = [...new Set(studentIds)];
  const created: StudentLinkCode[] = [];
  const failedStudentIds: string[] = [];

  // Each createLinkCode commits its own batch, so a chunk can partially
  // succeed. Use allSettled so one failure doesn't abort the run (and throw
  // away the codes already committed) — report exactly which students failed
  // so the caller can retry ONLY those (a blind full retry would supersede the
  // codes that already succeeded).
  for (let i = 0; i < unique.length; i += 25) {
    const chunk = unique.slice(i, i + 25);
    const settled = await Promise.allSettled(
      chunk.map((studentId) => createLinkCode(schoolId, studentId, createdBy))
    );
    settled.forEach((r, idx) => {
      if (r.status === 'fulfilled') created.push(r.value);
      else failedStudentIds.push(chunk[idx]);
    });
  }

  return { created, failedStudentIds };
}
