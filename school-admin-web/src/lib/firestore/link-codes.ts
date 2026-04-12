import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { StudentLinkCode } from '@/lib/types';

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude I/O/0/1

function generateCode(): string {
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
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

  // Revoke any existing active codes for this student
  const activeCodes = await adminDb
    .collection('studentLinkCodes')
    .where('studentId', '==', studentId)
    .where('status', '==', 'active')
    .get();

  const batch = adminDb.batch();
  for (const codeDoc of activeCodes.docs) {
    batch.update(codeDoc.ref, {
      status: 'revoked',
      revokedBy: createdBy,
      revokedAt: FieldValue.serverTimestamp(),
      revokeReason: 'Superseded by newly generated link code',
    });
  }

  const expiresAt = new Date();
  expiresAt.setFullYear(expiresAt.getFullYear() + 1);

  const ref = adminDb.collection('studentLinkCodes').doc();
  batch.set(ref, {
    code,
    schoolId,
    studentId,
    studentName,
    classId,
    status: 'active',
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
    createdAt: new Date(),
    expiresAt,
    createdBy,
  };
}

export async function revokeLinkCode(codeId: string, revokedBy: string): Promise<void> {
  await adminDb.collection('studentLinkCodes').doc(codeId).update({
    status: 'revoked',
    revokedBy,
    revokedAt: FieldValue.serverTimestamp(),
    revokeReason: 'Manually revoked by staff',
  });
}

export async function deleteLinkCode(codeId: string): Promise<void> {
  const ref = adminDb.collection('studentLinkCodes').doc(codeId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error('Code not found');
  if (snap.data()?.status !== 'revoked') throw new Error('Only revoked codes can be permanently deleted');
  await ref.delete();
}

export async function bulkCreateLinkCodes(
  schoolId: string,
  studentIds: string[],
  createdBy: string
): Promise<StudentLinkCode[]> {
  const unique = [...new Set(studentIds)];
  const results: StudentLinkCode[] = [];

  // Process in chunks of 25
  for (let i = 0; i < unique.length; i += 25) {
    const chunk = unique.slice(i, i + 25);
    const chunkResults = await Promise.all(
      chunk.map((studentId) => createLinkCode(schoolId, studentId, createdBy))
    );
    results.push(...chunkResults);
  }

  return results;
}
