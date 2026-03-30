import { adminDb } from '@/lib/firebase/admin';
import type { SchoolClass } from '@/lib/types';

function toClass(doc: FirebaseFirestore.DocumentSnapshot): SchoolClass {
  const data = doc.data()!;
  return {
    id: doc.id,
    name: data.name ?? '',
    schoolId: data.schoolId ?? '',
    yearLevel: data.yearLevel,
    teacherIds: data.teacherIds ?? [],
    studentIds: data.studentIds ?? [],
    defaultMinutesTarget: data.defaultMinutesTarget ?? 15,
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    createdBy: data.createdBy ?? '',
    metadata: data.metadata,
  };
}

export async function getClasses(
  schoolId: string,
  options?: { teacherId?: string }
): Promise<SchoolClass[]> {
  let query: FirebaseFirestore.Query = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('classes')
    .where('isActive', '==', true);

  if (options?.teacherId) {
    query = query.where('teacherIds', 'array-contains', options.teacherId);
  }

  const snap = await query.get();
  return snap.docs.map(toClass);
}

export async function getClass(schoolId: string, classId: string): Promise<SchoolClass | null> {
  const doc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('classes')
    .doc(classId)
    .get();
  if (!doc.exists) return null;
  return toClass(doc);
}

export async function createClass(
  schoolId: string,
  data: {
    name: string;
    yearLevel?: string;
    teacherIds: string[];
    defaultMinutesTarget: number;
    createdBy: string;
  }
): Promise<string> {
  const ref = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('classes')
    .add({
      ...data,
      schoolId,
      studentIds: [],
      isActive: true,
      createdAt: new Date(),
    });
  return ref.id;
}

export async function updateClass(
  schoolId: string,
  classId: string,
  data: Partial<Pick<SchoolClass, 'name' | 'yearLevel' | 'teacherIds' | 'defaultMinutesTarget'>>
): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('classes')
    .doc(classId)
    .update(data);
}

export async function deleteClass(schoolId: string, classId: string): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('classes')
    .doc(classId)
    .update({ isActive: false });
}

export async function getTeachers(schoolId: string): Promise<{ id: string; fullName: string }[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .where('role', 'in', ['teacher', 'schoolAdmin'])
    .get();

  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      fullName: data.fullName ?? data.email ?? 'Unknown',
    };
  });
}
