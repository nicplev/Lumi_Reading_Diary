import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if (
    "toDate" in ts &&
    typeof (ts as { toDate: unknown }).toDate === "function"
  ) {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

export interface ClassListItem {
  id: string;
  name: string;
  schoolId: string;
  schoolName?: string;
  yearLevel?: string;
  room?: string;
  teacherId: string;
  studentCount: number;
  defaultMinutesTarget: number;
  isActive: boolean;
  createdAt: string;
}

export interface ClassDetail extends ClassListItem {
  assistantTeacherId?: string;
  teacherIds: string[];
  studentIds: string[];
  description?: string;
  createdBy: string;
  settings?: Record<string, unknown>;
}

export async function listClasses(
  schoolId: string,
  options?: { isActive?: boolean }
): Promise<ClassListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("classes")
    .orderBy("createdAt", "desc");

  if (options?.isActive !== undefined) {
    query = query.where("isActive", "==", options.isActive);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.name,
      schoolId,
      yearLevel: data.yearLevel,
      room: data.room,
      teacherId: data.teacherId,
      studentCount: (data.studentIds as string[])?.length ?? 0,
      defaultMinutesTarget: data.defaultMinutesTarget ?? 15,
      isActive: data.isActive ?? true,
      createdAt: toISO(data.createdAt),
    };
  });
}

export async function getClass(
  schoolId: string,
  classId: string
): Promise<ClassDetail | null> {
  const doc = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("classes")
    .doc(classId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  return {
    id: doc.id,
    name: data.name,
    schoolId,
    yearLevel: data.yearLevel,
    room: data.room,
    teacherId: data.teacherId,
    assistantTeacherId: data.assistantTeacherId,
    teacherIds: data.teacherIds ?? [],
    studentIds: data.studentIds ?? [],
    studentCount: (data.studentIds as string[])?.length ?? 0,
    defaultMinutesTarget: data.defaultMinutesTarget ?? 15,
    description: data.description,
    isActive: data.isActive ?? true,
    createdAt: toISO(data.createdAt),
    createdBy: data.createdBy ?? "",
    settings: data.settings,
  };
}

export async function createClass(
  schoolId: string,
  data: {
    name: string;
    yearLevel?: string;
    room?: string;
    teacherId: string;
    defaultMinutesTarget?: number;
    description?: string;
    createdBy: string;
  }
): Promise<string> {
  const docRef = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("classes")
    .add({
      name: data.name,
      yearLevel: data.yearLevel || null,
      room: data.room || null,
      teacherId: data.teacherId,
      assistantTeacherId: null,
      teacherIds: [data.teacherId],
      studentIds: [],
      defaultMinutesTarget: data.defaultMinutesTarget ?? 15,
      description: data.description || null,
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: data.createdBy,
    });
  return docRef.id;
}

export async function updateClass(
  schoolId: string,
  classId: string,
  data: Record<string, unknown>
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("classes")
    .doc(classId)
    .update(data);
}

export async function deactivateClass(
  schoolId: string,
  classId: string
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("classes")
    .doc(classId)
    .update({ isActive: false });
}

export async function listAllClasses(
  options?: { limit?: number }
): Promise<ClassListItem[]> {
  const schoolsSnap = await getAdminDb().collection("schools").get();

  const allClasses = await Promise.all(
    schoolsSnap.docs.map(async (schoolDoc) => {
      const schoolData = schoolDoc.data();
      const classesSnap = await schoolDoc.ref
        .collection("classes")
        .orderBy("createdAt", "desc")
        .get();

      return classesSnap.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          name: data.name,
          schoolId: schoolDoc.id,
          schoolName: schoolData.name as string,
          yearLevel: data.yearLevel,
          room: data.room,
          teacherId: data.teacherId,
          studentCount: (data.studentIds as string[])?.length ?? 0,
          defaultMinutesTarget: data.defaultMinutesTarget ?? 15,
          isActive: data.isActive ?? true,
          createdAt: toISO(data.createdAt),
        };
      });
    })
  );

  const flat = allClasses
    .flat()
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  if (options?.limit) return flat.slice(0, options.limit);
  return flat;
}
