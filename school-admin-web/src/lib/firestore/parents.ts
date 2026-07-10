import { adminDb, adminAuth } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { Parent, ParentWithStudents, LinkedStudent } from '@/lib/types';

/**
 * Returns the subset of parent UIDs whose Firebase Auth account no longer
 * exists. The parent list is purely Firestore-driven, so a parent whose Auth
 * user was deleted out-of-band lingers as a ghost "Active" row — this lets the
 * caller flag those instead. Batched in 100s (getUsers' per-call cap).
 *
 * Fails open: on any Auth error we return an empty set, so a transient failure
 * never mislabels real parents as removed.
 */
async function findUidsMissingFromAuth(uids: string[]): Promise<Set<string>> {
  const missing = new Set<string>();
  // A Firebase UID is 1–128 chars; guard so a malformed doc id can't reject a
  // whole getUsers batch.
  const valid = uids.filter((u) => u && u.length <= 128);
  if (valid.length === 0) return missing;
  try {
    for (let i = 0; i < valid.length; i += 100) {
      const chunk = valid.slice(i, i + 100);
      const { notFound } = await adminAuth.getUsers(
        chunk.map((uid) => ({ uid }))
      );
      for (const id of notFound) {
        if ('uid' in id && id.uid) missing.add(id.uid);
      }
    }
  } catch (err) {
    console.error('findUidsMissingFromAuth failed; treating all as present', err);
    return new Set();
  }
  return missing;
}

function toParent(doc: FirebaseFirestore.DocumentSnapshot): Parent {
  const data = doc.data()!;
  return {
    id: doc.id,
    email: data.email ?? '',
    phoneNumber: data.phoneNumber ?? undefined,
    fullName: data.fullName ?? '',
    schoolId: data.schoolId ?? '',
    linkedChildren: data.linkedChildren ?? [],
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    lastLoginAt: data.lastLoginAt?.toDate(),
    relationshipLabel: data.relationshipLabel,
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

  // Keep parents with no linked students. A guardian may legitimately reach
  // this state after an administrator removes their final connection; their
  // Auth account and parent profile must remain available so they can link a
  // child again later. A read path must never perform destructive cleanup.
  const result: ParentWithStudents[] = parents.map((parent) => ({
    ...parent,
    linkedStudents: parent.linkedChildren
      .map((id) => studentMap.get(id))
      .filter((s): s is LinkedStudent => s != null),
  }));

  // Reconcile the displayed parents against Firebase Auth. A parent whose Auth
  // user was deleted out-of-band is a ghost that can't sign in — flag it so the
  // UI shows "Removed" instead of a misleading "Active". Non-destructive: we
  // only annotate, never delete (cleanup of dead docs is a separate decision).
  const missingAuth = await findUidsMissingFromAuth(result.map((p) => p.id));
  for (const parent of result) {
    if (missingAuth.has(parent.id)) parent.authMissing = true;
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
