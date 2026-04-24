import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

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

export interface AllocationListItem {
  id: string;
  schoolId: string;
  classId: string;
  teacherId: string;
  type: string;
  cadence: string;
  targetMinutes: number;
  startDate: string;
  endDate?: string;
  studentCount: number;
  isActive: boolean;
  isRecurring: boolean;
  templateName?: string;
  createdAt: string;
}

export interface AllocationBookItemSerialized {
  id: string;
  title: string;
  bookId?: string;
  isbn?: string;
  isDeleted: boolean;
  addedAt?: string;
  addedBy?: string;
}

export interface StudentOverrideSerialized {
  studentId: string;
  removedItemIds: string[];
  addedItems: AllocationBookItemSerialized[];
  updatedAt?: string;
  updatedBy?: string;
}

export interface AllocationDetail extends AllocationListItem {
  createdBy: string;
  levelStart?: string;
  levelEnd?: string;
  bookIds?: string[];
  bookTitles?: string[];
  assignmentItems: AllocationBookItemSerialized[];
  studentOverrides: StudentOverrideSerialized[];
  studentIds: string[];
  schemaVersion: number;
  metadata?: Record<string, unknown>;
}

export async function listAllocations(
  schoolId: string,
  options?: {
    classId?: string;
    teacherId?: string;
    isActive?: boolean;
    limit?: number;
  }
): Promise<AllocationListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("allocations")
    .orderBy("createdAt", "desc");

  if (options?.classId) {
    query = query.where("classId", "==", options.classId);
  }
  if (options?.teacherId) {
    query = query.where("teacherId", "==", options.teacherId);
  }
  if (options?.isActive !== undefined) {
    query = query.where("isActive", "==", options.isActive);
  }
  if (options?.limit) {
    query = query.limit(options.limit);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      schoolId,
      classId: data.classId,
      teacherId: data.teacherId,
      type: data.type,
      cadence: data.cadence,
      targetMinutes: data.targetMinutes,
      startDate: toISO(data.startDate),
      endDate: toISO(data.endDate) || undefined,
      studentCount: ((data.studentIds as string[]) ?? []).length,
      isActive: data.isActive ?? true,
      isRecurring: data.isRecurring ?? false,
      templateName: data.templateName,
      createdAt: toISO(data.createdAt),
    };
  });
}

export async function getAllocation(
  schoolId: string,
  allocationId: string
): Promise<AllocationDetail | null> {
  const doc = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("allocations")
    .doc(allocationId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data()!;

  const assignmentItems: AllocationBookItemSerialized[] = (
    (data.assignmentItems as Array<Record<string, unknown>>) ?? []
  ).map((item) => ({
    id: (item.id as string) ?? "",
    title: (item.title as string) ?? "",
    bookId: item.bookId as string | undefined,
    isbn: item.isbn as string | undefined,
    isDeleted: (item.isDeleted as boolean) ?? false,
    addedAt: toISO(item.addedAt) || undefined,
    addedBy: item.addedBy as string | undefined,
  }));

  const overridesMap =
    (data.studentOverrides as Record<string, Record<string, unknown>>) ?? {};
  const studentOverrides: StudentOverrideSerialized[] = Object.entries(
    overridesMap
  ).map(([studentId, override]) => ({
    studentId,
    removedItemIds: (override.removedItemIds as string[]) ?? [],
    addedItems: (
      (override.addedItems as Array<Record<string, unknown>>) ?? []
    ).map((item) => ({
      id: (item.id as string) ?? "",
      title: (item.title as string) ?? "",
      bookId: item.bookId as string | undefined,
      isbn: item.isbn as string | undefined,
      isDeleted: (item.isDeleted as boolean) ?? false,
      addedAt: toISO(item.addedAt) || undefined,
      addedBy: item.addedBy as string | undefined,
    })),
    updatedAt: toISO(override.updatedAt) || undefined,
    updatedBy: override.updatedBy as string | undefined,
  }));

  return {
    id: doc.id,
    schoolId,
    classId: data.classId,
    teacherId: data.teacherId,
    type: data.type,
    cadence: data.cadence,
    targetMinutes: data.targetMinutes,
    startDate: toISO(data.startDate),
    endDate: toISO(data.endDate) || undefined,
    studentCount: ((data.studentIds as string[]) ?? []).length,
    isActive: data.isActive ?? true,
    isRecurring: data.isRecurring ?? false,
    templateName: data.templateName,
    createdBy: data.createdBy ?? "",
    levelStart: data.levelStart,
    levelEnd: data.levelEnd,
    bookIds: data.bookIds,
    bookTitles: data.bookTitles,
    assignmentItems,
    studentOverrides,
    studentIds: (data.studentIds as string[]) ?? [],
    schemaVersion: data.schemaVersion ?? 1,
    metadata: data.metadata,
    createdAt: toISO(data.createdAt),
  };
}

export async function createAllocation(
  schoolId: string,
  data: {
    classId: string;
    teacherId: string;
    studentIds: string[];
    type: string;
    cadence: string;
    targetMinutes: number;
    startDate: string;
    endDate: string;
    levelStart?: string;
    levelEnd?: string;
    bookIds?: string[];
    bookTitles?: string[];
    isRecurring?: boolean;
    templateName?: string;
    createdBy: string;
  }
): Promise<string> {
  const docRef = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("allocations")
    .add({
      schoolId,
      classId: data.classId,
      teacherId: data.teacherId,
      studentIds: data.studentIds,
      type: data.type,
      cadence: data.cadence,
      targetMinutes: data.targetMinutes,
      startDate: Timestamp.fromDate(new Date(data.startDate)),
      endDate: Timestamp.fromDate(new Date(data.endDate)),
      levelStart: data.levelStart || null,
      levelEnd: data.levelEnd || null,
      bookIds: data.bookIds ?? [],
      bookTitles: data.bookTitles ?? [],
      isRecurring: data.isRecurring ?? false,
      templateName: data.templateName || null,
      isActive: true,
      assignmentItems: [],
      studentOverrides: {},
      schemaVersion: 1,
      createdBy: data.createdBy,
      createdAt: FieldValue.serverTimestamp(),
    });
  return docRef.id;
}

export async function updateAllocation(
  schoolId: string,
  allocationId: string,
  data: Record<string, unknown>
): Promise<void> {
  // Convert date strings to Timestamps if present
  const updates = { ...data };
  if (typeof updates.endDate === "string") {
    updates.endDate = Timestamp.fromDate(new Date(updates.endDate as string));
  }
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("allocations")
    .doc(allocationId)
    .update(updates);
}

export async function deactivateAllocation(
  schoolId: string,
  allocationId: string
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("allocations")
    .doc(allocationId)
    .update({ isActive: false });
}

export async function getActiveAllocationCount(
  schoolId: string
): Promise<number> {
  const snapshot = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("allocations")
    .where("isActive", "==", true)
    .count()
    .get();
  return snapshot.data().count;
}
