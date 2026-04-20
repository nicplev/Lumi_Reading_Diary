import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const COLLECTION = 'schoolCodes';

export interface SchoolCode {
  id: string;
  code: string;
  createdAt: Date;
  usageCount: number;
}

function generateCodeString(): string {
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  }
  return code;
}

async function isCodeUnique(code: string): Promise<boolean> {
  const snap = await adminDb
    .collection(COLLECTION)
    .where('code', '==', code)
    .limit(1)
    .get();
  return snap.empty;
}

async function generateUniqueCode(): Promise<string> {
  for (let i = 0; i < 40; i++) {
    const code = generateCodeString();
    if (await isCodeUnique(code)) return code;
  }
  throw new Error('Unable to generate unique school code after max attempts');
}

export async function getActiveSchoolCode(schoolId: string): Promise<SchoolCode | null> {
  const snap = await adminDb
    .collection(COLLECTION)
    .where('schoolId', '==', schoolId)
    .get();

  const active = snap.docs
    .filter((d) => d.data().isActive === true)
    .map((d) => {
      const data = d.data();
      return {
        id: d.id,
        code: data.code ?? '',
        createdAt: data.createdAt?.toDate() ?? new Date(0),
        usageCount: data.usageCount ?? 0,
      };
    })
    .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

  return active[0] ?? null;
}

export async function rotateSchoolCode(
  schoolId: string,
  schoolName: string,
  createdBy: string
): Promise<SchoolCode> {
  const newCode = await generateUniqueCode();

  const schoolSnap = await adminDb
    .collection(COLLECTION)
    .where('schoolId', '==', schoolId)
    .get();

  const batch = adminDb.batch();
  schoolSnap.docs
    .filter((doc) => doc.data().isActive === true)
    .forEach((doc) => {
      batch.update(doc.ref, { isActive: false });
    });

  const newDocRef = adminDb.collection(COLLECTION).doc();
  batch.set(newDocRef, {
    code: newCode,
    schoolId,
    schoolName,
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
    createdBy,
    usageCount: 0,
  });

  await batch.commit();

  const created = await newDocRef.get();
  const data = created.data()!;
  return {
    id: newDocRef.id,
    code: data.code,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    usageCount: data.usageCount ?? 0,
  };
}
