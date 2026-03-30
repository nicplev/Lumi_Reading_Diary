import { adminDb } from '@/lib/firebase/admin';
import type { ReadingGroup } from '@/lib/types';

function toGroup(doc: FirebaseFirestore.DocumentSnapshot): ReadingGroup {
  const data = doc.data()!;
  return {
    id: doc.id,
    name: data.name ?? '',
    schoolId: data.schoolId ?? '',
    classId: data.classId ?? '',
    teacherId: data.teacherId ?? '',
    studentIds: data.studentIds ?? [],
    readingLevel: data.readingLevel,
    color: data.color,
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
  };
}

export async function getReadingGroups(schoolId: string, classId: string): Promise<ReadingGroup[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingGroups')
    .where('classId', '==', classId)
    .where('isActive', '==', true)
    .get();
  return snap.docs.map(toGroup);
}

export async function createReadingGroup(
  schoolId: string,
  data: {
    name: string;
    classId: string;
    teacherId: string;
    readingLevel?: string;
    color?: string;
    description?: string;
    targetMinutes?: number;
  }
): Promise<string> {
  const ref = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingGroups')
    .add({
      ...data,
      schoolId,
      studentIds: [],
      isActive: true,
      createdAt: new Date(),
    });
  return ref.id;
}

export async function updateReadingGroup(
  schoolId: string,
  groupId: string,
  data: Partial<Pick<ReadingGroup, 'name' | 'readingLevel' | 'color'>> & {
    description?: string;
    targetMinutes?: number;
  }
): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingGroups')
    .doc(groupId)
    .update(data);
}

export async function deleteReadingGroup(schoolId: string, groupId: string): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingGroups')
    .doc(groupId)
    .delete();
}

export async function assignStudentsToGroup(
  schoolId: string,
  groupId: string,
  studentIds: string[]
): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingGroups')
    .doc(groupId)
    .update({ studentIds });
}
