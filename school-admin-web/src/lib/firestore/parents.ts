import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { Parent, ParentWithStudents, LinkedStudent } from '@/lib/types';

function toParent(doc: FirebaseFirestore.DocumentSnapshot): Parent {
  const data = doc.data()!;
  return {
    id: doc.id,
    email: data.email ?? '',
    fullName: data.fullName ?? '',
    schoolId: data.schoolId ?? '',
    linkedChildren: data.linkedChildren ?? [],
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    lastLoginAt: data.lastLoginAt?.toDate(),
  };
}

export async function getParents(schoolId: string): Promise<Parent[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('parents')
    .get();
  return snap.docs.map(toParent);
}

async function fetchStudentsByIds(
  schoolId: string,
  studentIds: string[]
): Promise<Map<string, LinkedStudent>> {
  const map = new Map<string, LinkedStudent>();
  if (studentIds.length === 0) return map;

  // Firestore 'in' queries support max 30 values
  const chunks: string[][] = [];
  for (let i = 0; i < studentIds.length; i += 30) {
    chunks.push(studentIds.slice(i, i + 30));
  }

  for (const chunk of chunks) {
    const snap = await adminDb
      .collection('schools')
      .doc(schoolId)
      .collection('students')
      .where('__name__', 'in', chunk)
      .get();

    for (const doc of snap.docs) {
      const data = doc.data();
      map.set(doc.id, {
        id: doc.id,
        firstName: data.firstName ?? '',
        lastName: data.lastName ?? '',
        classId: data.classId ?? '',
      });
    }
  }

  return map;
}

export async function getParentsWithStudents(
  schoolId: string
): Promise<ParentWithStudents[]> {
  const parents = await getParents(schoolId);

  // Collect all unique student IDs
  const allStudentIds = new Set<string>();
  for (const parent of parents) {
    for (const id of parent.linkedChildren) {
      allStudentIds.add(id);
    }
  }

  const studentMap = await fetchStudentsByIds(schoolId, [...allStudentIds]);

  const result: ParentWithStudents[] = [];
  const orphanIds: string[] = [];
  for (const parent of parents) {
    const linkedStudents = parent.linkedChildren
      .map((id) => studentMap.get(id))
      .filter((s): s is LinkedStudent => s != null);
    if (linkedStudents.length === 0) {
      orphanIds.push(parent.id);
    } else {
      result.push({ ...parent, linkedStudents });
    }
  }

  // Clean up orphaned parents (those whose linked students no longer exist).
  // Policy: auto-delete orphans so the admin view stays consistent with reality.
  if (orphanIds.length > 0) {
    const parentsRef = adminDb.collection('schools').doc(schoolId).collection('parents');
    const BATCH_SIZE = 400;
    for (let i = 0; i < orphanIds.length; i += BATCH_SIZE) {
      const batch = adminDb.batch();
      for (const id of orphanIds.slice(i, i + BATCH_SIZE)) {
        batch.delete(parentsRef.doc(id));
      }
      await batch.commit();
    }
  }

  return result;
}

/**
 * Sync bidirectional parent-student links.
 * Ensures every parent's linkedChildren entry has a matching parentIds entry
 * on the student doc, and vice versa.
 * Returns the number of documents updated.
 */
export async function syncParentStudentLinks(schoolId: string): Promise<number> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);

  // Fetch all parents
  const parentsSnap = await schoolRef.collection('parents').get();
  const studentsSnap = await schoolRef.collection('students').get();

  // Build maps of current state
  const parentLinkedChildren = new Map<string, string[]>();
  for (const doc of parentsSnap.docs) {
    parentLinkedChildren.set(doc.id, doc.data().linkedChildren ?? []);
  }

  const studentParentIds = new Map<string, string[]>();
  for (const doc of studentsSnap.docs) {
    studentParentIds.set(doc.id, doc.data().parentIds ?? []);
  }

  const batch = adminDb.batch();
  let updateCount = 0;

  // For each parent, ensure their linked students have this parent in parentIds
  for (const [parentId, childIds] of parentLinkedChildren) {
    for (const studentId of childIds) {
      const currentParentIds = studentParentIds.get(studentId);
      if (currentParentIds && !currentParentIds.includes(parentId)) {
        batch.update(schoolRef.collection('students').doc(studentId), {
          parentIds: FieldValue.arrayUnion(parentId),
        });
        currentParentIds.push(parentId); // track locally to avoid duplicates
        updateCount++;
      }
    }
  }

  // For each student, ensure their linked parents have this student in linkedChildren
  for (const [studentId, parentIds] of studentParentIds) {
    for (const parentId of parentIds) {
      const currentChildren = parentLinkedChildren.get(parentId);
      if (currentChildren && !currentChildren.includes(studentId)) {
        batch.update(schoolRef.collection('parents').doc(parentId), {
          linkedChildren: FieldValue.arrayUnion(studentId),
        });
        currentChildren.push(studentId);
        updateCount++;
      }
    }
  }

  if (updateCount > 0) {
    await batch.commit();
  }

  return updateCount;
}
