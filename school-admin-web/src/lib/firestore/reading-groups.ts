import { adminDb } from '@/lib/firebase/admin';
import {
  getSchoolTimezone,
  localDateString,
  shiftDateStr,
  zonedDayStart,
} from '@/lib/school-time';
import type { ReadingGroup, ReadingGroupStat } from '@/lib/types';
import { getClass } from './classes';
import { getStudents } from './students';

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
    description: data.description,
    targetMinutes: typeof data.targetMinutes === 'number' ? data.targetMinutes : undefined,
    sortOrder: typeof data.sortOrder === 'number' ? data.sortOrder : 0,
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
  // Order by sortOrder (client-side — keeps the existing classId+isActive index,
  // no new composite index), falling back to creation order for legacy groups.
  return snap.docs
    .map(toGroup)
    .sort((a, b) => a.sortOrder - b.sortOrder || a.createdAt.getTime() - b.createdAt.getTime());
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
  // Append new groups after the existing ones in the class.
  const existing = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingGroups')
    .where('classId', '==', data.classId)
    .get();
  let maxSort = -1;
  for (const d of existing.docs) {
    const so = d.data().sortOrder;
    if (typeof so === 'number' && so > maxSort) maxSort = so;
  }

  const ref = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingGroups')
    .add({
      ...data,
      schoolId,
      studentIds: [],
      isActive: true,
      sortOrder: maxSort + 1,
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
    sortOrder?: number;
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

/** Persist a new display order — writes each group's sortOrder to its index. */
export async function reorderReadingGroups(schoolId: string, orderedIds: string[]): Promise<void> {
  const batch = adminDb.batch();
  const col = adminDb.collection('schools').doc(schoolId).collection('readingGroups');
  orderedIds.forEach((id, i) => batch.update(col.doc(id), { sortOrder: i }));
  await batch.commit();
}

/**
 * This-week performance per reading group, for the differentiated-instruction
 * view. Reuses getClassReport's definitions (active reader = any minutes; "met
 * target" = a log's minutes ≥ its target-or-class-default, student counts when
 * ≥70% of their logs met it; needs support = no logs / <3 days / <50% met) and
 * partitions one class-scoped log scan by each group's members. Same
 * classId+date index getClassReport already uses — no new index.
 */
export async function getReadingGroupStats(
  schoolId: string,
  classId: string,
  sinceDays = 7
): Promise<ReadingGroupStat[]> {
  const [cls, students, groups] = await Promise.all([
    getClass(schoolId, classId),
    getStudents(schoolId, { classId, isActive: true }),
    getReadingGroups(schoolId, classId),
  ]);
  const defaultTarget = cls?.defaultMinutesTarget ?? 20;

  // School-local day window, not server midnight (see lib/school-time.ts).
  const tz = await getSchoolTimezone(schoolId);
  const since = zonedDayStart(
    shiftDateStr(localDateString(new Date(), tz), -(sinceDays - 1)),
    tz,
  );

  interface Acc {
    minutes: number;
    sessions: number;
    met: number;
    days: Set<string>;
  }
  const acc = new Map<string, Acc>();
  try {
    const logsSnap = await adminDb
      .collection('schools')
      .doc(schoolId)
      .collection('readingLogs')
      .where('classId', '==', classId)
      .where('date', '>=', since)
      .get();
    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const sid: string = d.studentId ?? '';
      if (!sid) continue;
      const a = acc.get(sid) ?? { minutes: 0, sessions: 0, met: 0, days: new Set<string>() };
      const mins: number = d.minutesRead ?? 0;
      a.minutes += mins;
      a.sessions += 1;
      const dt: Date | null = d.date?.toDate?.() ?? null;
      if (dt) a.days.add(localDateString(dt, tz));
      const target = typeof d.targetMinutes === 'number' && d.targetMinutes > 0 ? d.targetMinutes : defaultTarget;
      if (mins >= target) a.met += 1;
      acc.set(sid, a);
    }
  } catch {
    /* ignore — return zeroed stats */
  }

  const nameById = new Map(
    students.map((s) => [s.id, `${s.firstName ?? ''} ${s.lastName ?? ''}`.trim()])
  );

  return groups.map((g) => {
    const members = g.studentIds;
    let activeReaders = 0;
    let totalMinutes = 0;
    let studentsMetTarget = 0;
    let needsSupportCount = 0;
    let topReaderName: string | null = null;
    let topReaderMinutes = 0;
    for (const sid of members) {
      const a = acc.get(sid);
      const minutes = a?.minutes ?? 0;
      const sessions = a?.sessions ?? 0;
      const days = a?.days.size ?? 0;
      const metPct = sessions > 0 ? Math.round(((a?.met ?? 0) / sessions) * 100) : 0;
      if (minutes > 0) activeReaders++;
      totalMinutes += minutes;
      if (sessions > 0 && metPct >= 70) studentsMetTarget++;
      if (sessions === 0 || days < 3 || metPct < 50) needsSupportCount++;
      if (minutes > topReaderMinutes) {
        topReaderMinutes = minutes;
        topReaderName = nameById.get(sid) ?? null;
      }
    }
    return {
      groupId: g.id,
      totalStudents: members.length,
      activeReaders,
      totalMinutes,
      avgMinutes: members.length > 0 ? Math.round(totalMinutes / members.length) : 0,
      studentsMetTarget,
      topReaderName: topReaderMinutes > 0 ? topReaderName : null,
      topReaderMinutes,
      needsSupportCount,
    };
  });
}
