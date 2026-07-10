import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import { getCurrentAcademicYear, hardExpiryFor, isRenewalWindowOpen } from '@/lib/access';
import {
  classifyRollover,
  classKey,
  idKey,
  type ExistingClass,
  type ExistingStudent,
  type RolloverClassification,
  type RolloverCSVRow,
} from '@/lib/rollover/classify';
import type {
  RolloverAction,
  RolloverCommitCounts,
  RolloverCommitResult,
  RolloverPlan,
} from '@/lib/rollover/plan';
import { deleteStudents } from '@/lib/firestore/students';

export interface RolloverPreview extends RolloverClassification {
  targetAcademicYear: number;
  /** Soft warning — the Oct→Feb renewal window isn't open right now. */
  outsideRenewalWindow: boolean;
}

/**
 * Dry-run classification of a rollover CSV against the school's current
 * students and classes. Reads everything, writes NOTHING — safe to run
 * anywhere, any time. The commit endpoint receives the plan the admin
 * resolves from this preview.
 */
export async function previewRollover(
  schoolId: string,
  rows: RolloverCSVRow[],
  targetAcademicYear?: number
): Promise<RolloverPreview> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const [studentsSnap, classesSnap, currentYear] = await Promise.all([
    // All students — archived included (restore-matching needs them).
    schoolRef.collection('students').get(),
    // All classes — deactivated included (rename/name-clash detection).
    schoolRef.collection('classes').get(),
    getCurrentAcademicYear(),
  ]);

  const students: ExistingStudent[] = studentsSnap.docs.map((doc) => {
    const d = doc.data();
    const additional = (d.additionalInfo ?? {}) as Record<string, unknown>;
    return {
      docId: doc.id,
      externalId: typeof d.studentId === 'string' && d.studentId.trim() !== '' ? d.studentId.trim() : null,
      firstName: d.firstName ?? '',
      lastName: d.lastName ?? '',
      classId: d.classId ?? '',
      isActive: d.isActive ?? true,
      yearLevel: typeof additional.yearLevel === 'string' && additional.yearLevel.trim() !== ''
        ? additional.yearLevel.trim()
        : null,
      graduated: additional.graduated === true,
      hasParentLink: Array.isArray(d.parentIds) && d.parentIds.length > 0,
    };
  });

  const classes: ExistingClass[] = classesSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      docId: doc.id,
      name: typeof d.name === 'string' ? d.name : '',
      yearLevel: typeof d.yearLevel === 'string' && d.yearLevel.trim() !== '' ? d.yearLevel.trim() : null,
      isActive: d.isActive ?? true,
    };
  });

  // The import is the first half of a transition, never a current-year roster
  // edit. Defaulting to the next configured year prevents the historical
  // July-vs-October mismatch between this helper and the access-grant screen.
  const year = targetAcademicYear ?? currentYear + 1;
  return {
    ...classifyRollover(rows, students, classes),
    targetAcademicYear: year,
    outsideRenewalWindow: !isRenewalWindowOpen(year),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Commit
// ─────────────────────────────────────────────────────────────────────────────

const BATCH_SIZE = 400;
const IN_QUERY_CHUNK = 30;

/** Per-student before-snapshot recorded in entry chunks for undo. */
interface RolloverEntry {
  index: number;
  action: 'move' | 'backfill_move' | 'restore_move' | 'archive';
  studentDocId: string;
  name: string;
  /** Resolved destination class (move-type actions). */
  newClassId: string | null;
  wroteYearLevel: boolean;
  wroteParentEmail: boolean;
  wroteExternalId: boolean;
  prevFirstName: string;
  prevLastName: string;
  prevClassId: string;
  prevExternalId: string | null;
  prevYearLevel: string | null;
  prevYearLevelSetForYear: number | null;
  prevGraduated: boolean;
  prevParentEmail: string | null;
  prevPendingParentEmail: string | null;
  prevIsActive: boolean;
  prevArchivedAtMs: number | null;
  prevArchivedReason: string | null;
  prevArchivedBy: string | null;
  prevAccess: Record<string, unknown> | null;
  prevAccessBeforeArchive: Record<string, unknown> | null;
  archiveReason?: 'graduated' | 'left';
}

interface ImportDocSteps {
  snapshot: boolean;
  classes: boolean;
  students: boolean;
  groups: boolean;
  codes: boolean;
  rosters: boolean;
  counter: boolean;
}

export interface RolloverImportSummary {
  id: string;
  status: 'applying' | 'applied' | 'undone' | 'failed';
  targetAcademicYear: number;
  counts: RolloverCommitCounts | null;
  performedByName: string | null;
  performedAtIso: string | null;
  undoneAtIso: string | null;
}

function importRefFor(schoolId: string, importId: string) {
  return adminDb.collection('schools').doc(schoolId).collection('rolloverImports').doc(importId);
}

/**
 * Apply a resolved rollover plan. Designed to be safely re-POSTable: the
 * import doc is claimed with a transactional create keyed on the
 * client-generated importId; every mutation step is value-idempotent and
 * gated by a per-step completion flag, so a retry after a network failure or
 * crash resumes where it stopped instead of double-applying. Before-snapshots
 * for every touched student are written to `entryChunks` BEFORE any mutation,
 * mirroring the renewalBatches undo pattern.
 *
 * Deliberately untouched (see the plan doc): historical readingLogs keep last
 * year's classId (that reading belongs to last year's class); class stats are
 * left to the weekly reconcile cron; old allocations lapse naturally.
 */
export async function commitRollover(
  schoolId: string,
  plan: RolloverPlan,
  importId: string,
  performedBy: string,
  performedByName?: string
): Promise<RolloverCommitResult> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const studentsRef = schoolRef.collection('students');
  const classesRef = schoolRef.collection('classes');
  const importRef = importRefFor(schoolId, importId);

  // ── Claim / resume ─────────────────────────────────────────────────────────
  let steps: ImportDocSteps = {
    snapshot: false, classes: false, students: false,
    groups: false, codes: false, rosters: false, counter: false,
  };
  let storedCreatedClasses: { key: string; name: string; docId: string }[] = [];
  let storedCreatedStudents: { index: number; docId: string }[] = [];
  try {
    await importRef.create({
      status: 'applying',
      targetAcademicYear: plan.targetAcademicYear,
      performedBy,
      performedByName: performedByName ?? null,
      performedAt: FieldValue.serverTimestamp(),
      steps,
    });
  } catch {
    // Already exists — either a finished import (idempotent retry) or a
    // crashed one (resume).
    const existing = await importRef.get();
    const data = existing.data();
    if (!data) throw new Error('Import record unreadable — try again with a new import.');
    if (data.status === 'applied' || data.status === 'undone') {
      return {
        importId,
        counts: (data.counts as RolloverCommitCounts) ?? emptyCounts(),
        skipped: (data.skipped as { index: number; note: string }[]) ?? [],
        alreadyApplied: true,
      };
    }
    steps = { ...steps, ...(data.steps as Partial<ImportDocSteps>) };
    storedCreatedClasses = (data.createdClasses as typeof storedCreatedClasses) ?? [];
    storedCreatedStudents = (data.createdStudents as typeof storedCreatedStudents) ?? [];
  }

  const skipped: { index: number; note: string }[] = [];
  const skip = (index: number, note: string) => skipped.push({ index, note });

  // ── Dedupe (a student/ID may appear in only one action) ────────────────────
  const seenDocIds = new Set<string>();
  const seenExternalIds = new Set<string>();
  const actions: { index: number; a: RolloverAction }[] = [];
  for (let i = 0; i < plan.actions.length; i++) {
    const a = plan.actions[i];
    if (a.action !== 'create') {
      if (seenDocIds.has(a.studentDocId)) { skip(i, 'Duplicate action for this student — first one wins'); continue; }
      seenDocIds.add(a.studentDocId);
    }
    const ext = a.action === 'create' ? idKey(a.externalId) : a.action === 'backfill_move' ? idKey(a.externalId) : null;
    if (ext) {
      if (seenExternalIds.has(ext)) { skip(i, `Duplicate Student ID ${ext} in the plan — first one wins`); continue; }
      seenExternalIds.add(ext);
    }
    actions.push({ index: i, a });
  }

  // ── Re-read current state (the preview may be stale) ───────────────────────
  const referencedIds = actions.filter((x) => x.a.action !== 'create').map((x) => (x.a as { studentDocId: string }).studentDocId);
  const snapById = new Map<string, FirebaseFirestore.DocumentSnapshot>();
  for (let i = 0; i < referencedIds.length; i += 300) {
    const chunk = referencedIds.slice(i, i + 300);
    const snaps = await adminDb.getAll(...chunk.map((id) => studentsRef.doc(id)));
    for (const s of snaps) snapById.set(s.id, s);
  }

  // Active holders of every external ID the plan wants to introduce
  // (backfills, creates, restores) — collisions get skipped, not guessed at.
  const introducedIds = new Set<string>();
  for (const { a } of actions) {
    if (a.action === 'create' && a.externalId) introducedIds.add(idKey(a.externalId)!);
    if (a.action === 'backfill_move') introducedIds.add(idKey(a.externalId)!);
    if (a.action === 'restore_move') {
      const prev = snapById.get(a.studentDocId)?.data()?.studentId as string | undefined;
      const k = idKey(prev);
      if (k) introducedIds.add(k);
    }
  }
  const activeIdHolders = new Map<string, string>(); // idKey → docId
  const idList = Array.from(introducedIds);
  for (let i = 0; i < idList.length; i += IN_QUERY_CHUNK) {
    const chunk = idList.slice(i, i + IN_QUERY_CHUNK);
    // studentId casing can differ from the key — query both the raw chunk and
    // rely on idKey comparison when indexing the results.
    const snap = await studentsRef.where('isActive', '==', true).where('studentId', 'in', chunk).get();
    for (const doc of snap.docs) {
      const k = idKey(doc.data().studentId as string | undefined);
      if (k) activeIdHolders.set(k, doc.id);
    }
  }

  // ── Resolve validity per action ────────────────────────────────────────────
  type Resolved =
    | { index: number; kind: 'move' | 'backfill_move' | 'restore_move'; a: Exclude<RolloverAction, { action: 'create' } | { action: 'archive' }>; snap: FirebaseFirestore.DocumentSnapshot; backfillId?: string; restore: boolean }
    | { index: number; kind: 'create'; a: Extract<RolloverAction, { action: 'create' }> }
    | { index: number; kind: 'archive'; a: Extract<RolloverAction, { action: 'archive' }>; snap: FirebaseFirestore.DocumentSnapshot };
  const resolved: Resolved[] = [];

  for (const { index, a } of actions) {
    if (a.action === 'create') {
      const k = idKey(a.externalId);
      if (k && activeIdHolders.has(k)) {
        skip(index, `An active student already has Student ID ${a.externalId} — re-run the preview`);
        continue;
      }
      resolved.push({ index, kind: 'create', a });
      continue;
    }

    const snap = snapById.get(a.studentDocId);
    if (!snap?.exists) { skip(index, 'Student no longer exists — skipped'); continue; }
    const isActive = (snap.data()!.isActive ?? true) === true;

    if (a.action === 'archive') {
      if (!isActive) { skip(index, 'Student is already archived — skipped'); continue; }
      resolved.push({ index, kind: 'archive', a, snap });
      continue;
    }

    if (a.action === 'move') {
      if (!isActive) { skip(index, 'Student was archived since the preview — skipped, re-run the preview'); continue; }
      resolved.push({ index, kind: 'move', a, snap, restore: false });
      continue;
    }

    if (a.action === 'backfill_move') {
      if (!isActive) { skip(index, 'Student was archived since the preview — skipped'); continue; }
      const currentId = idKey(snap.data()!.studentId as string | undefined);
      const wanted = idKey(a.externalId)!;
      if (currentId && currentId !== wanted) {
        skip(index, `Student now has a different Student ID (${snap.data()!.studentId}) — skipped`);
        continue;
      }
      const holder = activeIdHolders.get(wanted);
      if (holder && holder !== a.studentDocId) {
        skip(index, `Another active student already has Student ID ${a.externalId} — skipped`);
        continue;
      }
      resolved.push({ index, kind: 'backfill_move', a, snap, backfillId: currentId ? undefined : a.externalId.trim(), restore: false });
      continue;
    }

    // restore_move
    const prevExt = idKey(snap.data()!.studentId as string | undefined);
    if (isActive) {
      // Restored by hand since the preview — a plain move is what's wanted.
      resolved.push({ index, kind: 'restore_move', a, snap, restore: false });
      continue;
    }
    if (prevExt) {
      const holder = activeIdHolders.get(prevExt);
      if (holder && holder !== a.studentDocId) {
        skip(index, `An active student now has Student ID ${snap.data()!.studentId} — restore skipped`);
        continue;
      }
    }
    resolved.push({ index, kind: 'restore_move', a, snap, restore: true });
  }

  // ── Classes: find-or-create ────────────────────────────────────────────────
  const neededClassKeys = new Map<string, { name: string; yearLevels: Map<string, number> }>();
  for (const r of resolved) {
    if (r.kind === 'archive') continue;
    const name = r.a.className.trim();
    const ck = classKey(name);
    const agg = neededClassKeys.get(ck) ?? { name, yearLevels: new Map<string, number>() };
    const yl = r.a.yearLevel?.trim();
    if (yl) agg.yearLevels.set(yl, (agg.yearLevels.get(yl) ?? 0) + 1);
    neededClassKeys.set(ck, agg);
  }

  const activeClassesSnap = await classesRef.where('isActive', '==', true).get();
  const classIdByKey = new Map<string, string>();
  for (const doc of activeClassesSnap.docs) {
    const name = doc.data().name;
    if (typeof name === 'string') classIdByKey.set(classKey(name), doc.id);
  }
  const createdClasses: { key: string; name: string; docId: string }[] = [...storedCreatedClasses];
  for (const c of createdClasses) classIdByKey.set(c.key, c.docId); // resume reuse
  const classesToCreate: { key: string; name: string; docId: string; yearLevel: string | null }[] = [];
  for (const [ck, agg] of neededClassKeys) {
    if (classIdByKey.has(ck)) continue;
    let modal: string | null = null;
    let modalCount = 0;
    for (const [yl, count] of agg.yearLevels) {
      if (count > modalCount) { modal = yl; modalCount = count; }
    }
    const docId = classesRef.doc().id;
    classesToCreate.push({ key: ck, name: agg.name, docId, yearLevel: modal });
    createdClasses.push({ key: ck, name: agg.name, docId });
    classIdByKey.set(ck, docId);
  }

  // ── Pre-allocate create refs (stable across resume) ────────────────────────
  const createDocIdByIndex = new Map<number, string>(storedCreatedStudents.map((c) => [c.index, c.docId]));
  const createdStudents: { index: number; docId: string }[] = [...storedCreatedStudents];
  for (const r of resolved) {
    if (r.kind !== 'create' || createDocIdByIndex.has(r.index)) continue;
    const docId = studentsRef.doc().id;
    createDocIdByIndex.set(r.index, docId);
    createdStudents.push({ index: r.index, docId });
  }

  // ── Build undo entries + counts ────────────────────────────────────────────
  const entries: RolloverEntry[] = [];
  const counts = emptyCounts();
  counts.classesCreated = classesToCreate.length;

  for (const r of resolved) {
    if (r.kind === 'create') { counts.created++; continue; }
    const d = r.snap.data()!;
    const additional = (d.additionalInfo ?? {}) as Record<string, unknown>;
    const base: RolloverEntry = {
      index: r.index,
      action: r.kind,
      studentDocId: r.snap.id,
      name: `${d.firstName ?? ''} ${d.lastName ?? ''}`.trim(),
      newClassId: null,
      wroteYearLevel: false,
      wroteParentEmail: false,
      wroteExternalId: false,
      prevFirstName: d.firstName ?? '',
      prevLastName: d.lastName ?? '',
      prevClassId: (d.classId as string | undefined) ?? '',
      prevExternalId: (d.studentId as string | undefined) ?? null,
      prevYearLevel: typeof additional.yearLevel === 'string' ? (additional.yearLevel as string) : null,
      prevYearLevelSetForYear: typeof additional.yearLevelSetForYear === 'number' ? (additional.yearLevelSetForYear as number) : null,
      prevGraduated: additional.graduated === true,
      prevParentEmail: (d.parentEmail as string | undefined) ?? null,
      prevPendingParentEmail: typeof additional.pendingParentEmail === 'string' ? (additional.pendingParentEmail as string) : null,
      prevIsActive: (d.isActive ?? true) === true,
      prevArchivedAtMs: d.archivedAt?.toMillis?.() ?? null,
      prevArchivedReason: (d.archivedReason as string | undefined) ?? null,
      prevArchivedBy: (d.archivedBy as string | undefined) ?? null,
      prevAccess: (d.access as Record<string, unknown> | undefined) ?? null,
      prevAccessBeforeArchive:
        (d.accessBeforeArchive as Record<string, unknown> | undefined) ?? null,
    };

    if (r.kind === 'archive') {
      base.archiveReason = r.a.reason;
      if (r.a.reason === 'graduated') counts.archivedGraduates++;
      else counts.archivedLeavers++;
      entries.push(base);
      continue;
    }

    base.newClassId = classIdByKey.get(classKey(r.a.className)) ?? null;
    base.wroteYearLevel = !!r.a.yearLevel?.trim();
    base.wroteExternalId = r.kind === 'backfill_move' && !!r.backfillId;
    // Update-if-unlinked: never clobber a linked family's email.
    const parentIds = (d.parentIds ?? []) as string[];
    base.wroteParentEmail =
      !!r.a.parentEmail?.trim() &&
      parentIds.length === 0 &&
      !base.prevParentEmail &&
      !base.prevPendingParentEmail;

    if (r.restore) counts.restored++;
    else counts.moved++;
    if (base.wroteExternalId) counts.idBackfills++;
    entries.push(base);
  }
  counts.classesDeactivated = plan.classesToDeactivate.length;

  // ── Snapshot step: entries + allocations recorded BEFORE any mutation ──────
  if (!steps.snapshot) {
    const chunksCol = importRef.collection('entryChunks');
    for (let i = 0; i < entries.length; i += BATCH_SIZE) {
      await chunksCol.doc(String(Math.floor(i / BATCH_SIZE))).set({
        entries: entries.slice(i, i + BATCH_SIZE),
      });
    }
    steps.snapshot = true;
    await importRef.update({
      counts,
      skipped,
      createdClasses,
      createdStudents,
      entryChunkCount: Math.ceil(entries.length / BATCH_SIZE),
      'steps.snapshot': true,
    });
  }

  // ── Step: create classes ───────────────────────────────────────────────────
  if (!steps.classes) {
    if (classesToCreate.length > 0) {
      const batch = adminDb.batch();
      for (const c of classesToCreate) {
        batch.set(classesRef.doc(c.docId), {
          name: c.name,
          schoolId,
          yearLevel: c.yearLevel,
          teacherIds: [],
          studentIds: [],
          defaultMinutesTarget: 15,
          isActive: true,
          createdAt: new Date(),
          createdBy: performedBy,
        });
      }
      await batch.commit();
    }
    steps.classes = true;
    await importRef.update({ 'steps.classes': true });
  }

  // ── Step: student writes ───────────────────────────────────────────────────
  if (!steps.students) {
    const now = new Date();
    const writes: { ref: FirebaseFirestore.DocumentReference; type: 'set' | 'update'; data: Record<string, unknown> }[] = [];

    for (const r of resolved) {
      if (r.kind === 'create') {
        const docId = createDocIdByIndex.get(r.index)!;
        const classId = classIdByKey.get(classKey(r.a.className))!;
        writes.push({
          ref: studentsRef.doc(docId),
          type: 'set',
          data: {
            studentId: r.a.externalId?.trim() || null,
            firstName: r.a.firstName,
            lastName: r.a.lastName,
            classId,
            schoolId,
            dateOfBirth: null,
            currentReadingLevel: r.a.readingLevel?.trim() || null,
            parentEmail: r.a.parentEmail?.trim() || null,
            enrollmentStatus: 'not_enrolled',
            parentIds: [],
            isActive: true,
            createdAt: now,
            enrolledAt: now,
            createdBy: performedBy,
            createdByImport: importId,
            additionalInfo: {
              ...(r.a.parentEmail?.trim() ? { pendingParentEmail: r.a.parentEmail.trim() } : {}),
              ...(r.a.yearLevel?.trim()
                ? { yearLevel: r.a.yearLevel.trim(), yearLevelSetForYear: plan.targetAcademicYear }
                : {}),
            },
            levelHistory: [],
            stats: {
              totalMinutesRead: 0,
              totalBooksRead: 0,
              currentStreak: 0,
              longestStreak: 0,
              averageMinutesPerDay: 0,
              totalReadingDays: 0,
            },
          },
        });
        continue;
      }

      const entry = entries.find((e) => e.index === r.index)!;
      if (r.kind === 'archive') {
        const existingAccess = r.snap.data()!.access ?? null;
        writes.push({
          ref: studentsRef.doc(r.snap.id),
          type: 'update',
          data: {
            isActive: false,
            status: 'archived',
            archivedAt: now,
            archivedReason: r.a.reason === 'graduated' ? 'graduated' : 'left',
            archivedBy: performedBy,
            accessBeforeArchive: existingAccess,
            access: {
              ...(existingAccess ?? {}),
              status: 'revoked',
              academicYear: existingAccess?.academicYear ?? plan.targetAcademicYear,
              expiresAt:
                existingAccess?.expiresAt ?? hardExpiryFor(plan.targetAcademicYear),
              revokedAt: FieldValue.serverTimestamp(),
              revokedBy: performedBy,
              revokeReason: `student_archived:${r.a.reason}`,
            },
            ...(r.a.reason === 'graduated' ? { 'additionalInfo.graduated': true } : {}),
          },
        });
        continue;
      }

      // move / backfill_move / restore_move
      const data: Record<string, unknown> = {
        firstName: r.a.firstName,
        lastName: r.a.lastName,
        classId: entry.newClassId ?? '',
        updatedAt: now,
      };
      if (entry.wroteYearLevel) {
        data['additionalInfo.yearLevel'] = r.a.yearLevel!.trim();
        data['additionalInfo.yearLevelSetForYear'] = plan.targetAcademicYear;
      }
      if (entry.wroteParentEmail) {
        data.parentEmail = r.a.parentEmail!.trim();
        data['additionalInfo.pendingParentEmail'] = r.a.parentEmail!.trim();
      }
      if (entry.wroteExternalId && r.kind === 'backfill_move') {
        data.studentId = r.backfillId;
      }
      if (r.restore) {
        data.isActive = true;
        data.status = FieldValue.delete();
        data.archivedAt = FieldValue.delete();
        data.archivedReason = FieldValue.delete();
        data.archivedBy = FieldValue.delete();
        data.access = r.snap.data()!.accessBeforeArchive ?? r.snap.data()!.access;
        data.accessBeforeArchive = FieldValue.delete();
      }
      writes.push({ ref: studentsRef.doc(r.snap.id), type: 'update', data });
    }

    for (let i = 0; i < writes.length; i += BATCH_SIZE) {
      const batch = adminDb.batch();
      for (const w of writes.slice(i, i + BATCH_SIZE)) {
        if (w.type === 'set') batch.set(w.ref, w.data);
        else batch.update(w.ref, w.data);
      }
      await batch.commit();
    }
    steps.students = true;
    await importRef.update({ 'steps.students': true });
  }

  // ── Step: reading-group cleanup ────────────────────────────────────────────
  // Moved students leave their old class's groups; archived students leave all
  // groups. Removals are recorded for undo.
  if (!steps.groups) {
    const groupsSnap = await schoolRef.collection('readingGroups').get();
    const archivedIds = new Set(entries.filter((e) => e.action === 'archive').map((e) => e.studentDocId));
    const newClassByStudent = new Map(
      entries.filter((e) => e.action !== 'archive').map((e) => [e.studentDocId, e.newClassId])
    );
    const removed: { groupId: string; studentIds: string[] }[] = [];
    const batchOps: { ref: FirebaseFirestore.DocumentReference; ids: string[] }[] = [];
    for (const g of groupsSnap.docs) {
      const gd = g.data();
      const members = (gd.studentIds ?? []) as string[];
      const groupClassId = gd.classId as string | undefined;
      const toRemove = members.filter((id) => {
        if (archivedIds.has(id)) return true;
        const newClass = newClassByStudent.get(id);
        return newClass !== undefined && newClass !== groupClassId;
      });
      if (toRemove.length > 0) {
        removed.push({ groupId: g.id, studentIds: toRemove });
        batchOps.push({ ref: g.ref, ids: toRemove });
      }
    }
    await importRef.collection('entryChunks').doc('groups').set({ removed });
    for (let i = 0; i < batchOps.length; i += BATCH_SIZE) {
      const batch = adminDb.batch();
      for (const op of batchOps.slice(i, i + BATCH_SIZE)) {
        batch.update(op.ref, { studentIds: FieldValue.arrayRemove(...op.ids) });
      }
      await batch.commit();
    }
    steps.groups = true;
    await importRef.update({ 'steps.groups': true });
  }

  // ── Step: revoke link codes for archived students ──────────────────────────
  if (!steps.codes) {
    const archivedIds = entries.filter((e) => e.action === 'archive').map((e) => e.studentDocId);
    const codeRefs: FirebaseFirestore.DocumentReference[] = [];
    for (let i = 0; i < archivedIds.length; i += IN_QUERY_CHUNK) {
      const chunk = archivedIds.slice(i, i + IN_QUERY_CHUNK);
      const snap = await adminDb
        .collection('studentLinkCodes')
        .where('studentId', 'in', chunk)
        .where('status', '==', 'active')
        .get();
      for (const doc of snap.docs) codeRefs.push(doc.ref);
    }
    // Merge with any ids already recorded by a prior attempt (their status is
    // no longer 'active', so the query above won't re-find them).
    const codesDoc = await importRef.collection('entryChunks').doc('codes').get();
    const prior = (codesDoc.data()?.codeIds as string[] | undefined) ?? [];
    const codeIds = Array.from(new Set([...prior, ...codeRefs.map((r) => r.id)]));
    await importRef.collection('entryChunks').doc('codes').set({ codeIds });
    for (let i = 0; i < codeRefs.length; i += BATCH_SIZE) {
      const batch = adminDb.batch();
      for (const ref of codeRefs.slice(i, i + BATCH_SIZE)) {
        batch.update(ref, {
          status: 'revoked',
          revokedAt: FieldValue.serverTimestamp(),
          revokeReason: 'student_archived',
        });
      }
      await batch.commit();
    }
    steps.codes = true;
    await importRef.update({ 'steps.codes': true });
  }

  // ── Step: class roster mirrors + opted-in deactivations ───────────────────
  if (!steps.rosters) {
    const leaving = new Map<string, Set<string>>();
    const arriving = new Map<string, Set<string>>();
    const add = (map: Map<string, Set<string>>, classId: string | null | undefined, id: string) => {
      if (!classId) return;
      const set = map.get(classId) ?? new Set<string>();
      set.add(id);
      map.set(classId, set);
    };
    for (const e of entries) {
      if (e.action === 'archive') {
        add(leaving, e.prevClassId, e.studentDocId);
      } else {
        if (e.prevClassId !== e.newClassId) {
          add(leaving, e.prevClassId, e.studentDocId);
          add(arriving, e.newClassId, e.studentDocId);
        } else if (e.action === 'restore_move') {
          // Restored into the same class — make sure the mirror has them.
          add(arriving, e.newClassId, e.studentDocId);
        }
      }
    }
    for (const r of resolved) {
      if (r.kind !== 'create') continue;
      add(arriving, classIdByKey.get(classKey(r.a.className)), createDocIdByIndex.get(r.index)!);
    }

    // Removes and unions run as SEPARATE sequential phases: a class routinely
    // both loses last year's cohort and gains this year's, and two transforms
    // on the same doc+field must not share a batch.
    const removeOps: { ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown> }[] = [];
    const unionOps: { ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown> }[] = [];
    for (const [classId, ids] of leaving) {
      if (ids.size > 0) removeOps.push({ ref: classesRef.doc(classId), data: { studentIds: FieldValue.arrayRemove(...ids) } });
    }
    for (const [classId, ids] of arriving) {
      if (ids.size > 0) unionOps.push({ ref: classesRef.doc(classId), data: { studentIds: FieldValue.arrayUnion(...ids) } });
    }
    const deactivatedClassIds: string[] = [];
    for (const classId of plan.classesToDeactivate) {
      unionOps.push({ ref: classesRef.doc(classId), data: { isActive: false } });
      deactivatedClassIds.push(classId);
    }

    for (const ops of [removeOps, unionOps]) {
      for (let i = 0; i < ops.length; i += BATCH_SIZE) {
        const batch = adminDb.batch();
        for (const op of ops.slice(i, i + BATCH_SIZE)) batch.update(op.ref, op.data);
        await batch.commit();
      }
    }
    steps.rosters = true;
    await importRef.update({ 'steps.rosters': true, deactivatedClassIds });
  }

  // ── Step: studentCount (transaction-guarded, exactly once) ─────────────────
  const counterDelta = counts.created + counts.restored - counts.archivedGraduates - counts.archivedLeavers;
  await adminDb.runTransaction(async (tx) => {
    const doc = await tx.get(importRef);
    const s = (doc.data()?.steps ?? {}) as Partial<ImportDocSteps>;
    if (s.counter) return;
    if (counterDelta !== 0) {
      tx.update(schoolRef, { studentCount: FieldValue.increment(counterDelta) });
    }
    tx.update(importRef, { 'steps.counter': true });
  });

  await importRef.update({ status: 'applied', counts, skipped });
  return { importId, counts, skipped, alreadyApplied: false };
}

function emptyCounts(): RolloverCommitCounts {
  return {
    moved: 0, created: 0, restored: 0,
    archivedGraduates: 0, archivedLeavers: 0,
    idBackfills: 0, classesCreated: 0, classesDeactivated: 0,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Undo
// ─────────────────────────────────────────────────────────────────────────────

export interface RolloverUndoResult {
  reverted: number;
  createdDeleted: number;
  skippedMissing: number;
}

/**
 * Undo an applied rollover import from its before-snapshots. Scope is exactly
 * the import's own writes — nothing teachers did afterwards is touched.
 * Re-runnable: every restore write is value-idempotent, and the counter +
 * status flip commit atomically at the very end, so a crash mid-undo leaves
 * the import 'applied' and a second undo finishes the job without
 * double-counting.
 */
export async function undoRolloverImport(
  schoolId: string,
  importId: string,
  undoneBy: string
): Promise<RolloverUndoResult> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const studentsRef = schoolRef.collection('students');
  const classesRef = schoolRef.collection('classes');
  const importRef = importRefFor(schoolId, importId);

  const importSnap = await importRef.get();
  if (!importSnap.exists) throw new Error('Import not found.');
  const importData = importSnap.data()!;
  if (importData.status === 'undone') throw new Error('This import has already been undone.');
  if (importData.status !== 'applied') {
    throw new Error('Only a fully applied import can be undone. If it failed part-way, re-run the import first.');
  }

  // Load entries.
  const chunkCount = (importData.entryChunkCount as number) ?? 0;
  const entries: RolloverEntry[] = [];
  for (let i = 0; i < chunkCount; i++) {
    const doc = await importRef.collection('entryChunks').doc(String(i)).get();
    entries.push(...(((doc.data()?.entries ?? []) as RolloverEntry[])));
  }

  // 1. Reactivate classes the import deactivated (before roster unions).
  const deactivatedClassIds = (importData.deactivatedClassIds as string[] | undefined) ?? [];
  if (deactivatedClassIds.length > 0) {
    const batch = adminDb.batch();
    for (const id of deactivatedClassIds) batch.update(classesRef.doc(id), { isActive: true });
    await batch.commit();
  }

  // 2. Delete created students via the existing cascade (they are minutes-to-
  //    days old; the cascade also fixes rosters, parents and the counter).
  const createdStudents = ((importData.createdStudents as { index: number; docId: string }[] | undefined) ?? []).map((c) => c.docId);
  const createdDeleted = createdStudents.length > 0 ? await deleteStudents(schoolId, createdStudents) : 0;

  // 3. Restore each entry from its snapshot.
  const present = new Set<string>();
  for (let i = 0; i < entries.length; i += 300) {
    const chunk = entries.slice(i, i + 300);
    const snaps = await adminDb.getAll(...chunk.map((e) => studentsRef.doc(e.studentDocId)));
    for (const s of snaps) if (s.exists) present.add(s.id);
  }

  let reverted = 0;
  let unarchived = 0;
  let rearchived = 0;
  for (let i = 0; i < entries.length; i += BATCH_SIZE) {
    const batch = adminDb.batch();
    for (const e of entries.slice(i, i + BATCH_SIZE)) {
      if (!present.has(e.studentDocId)) continue; // hard-deleted since — skip
      const ref = studentsRef.doc(e.studentDocId);

      if (e.action === 'archive') {
        batch.update(ref, {
          isActive: true,
          status: FieldValue.delete(),
          archivedAt: FieldValue.delete(),
          archivedReason: FieldValue.delete(),
          archivedBy: FieldValue.delete(),
          access: e.prevAccess ?? FieldValue.delete(),
          accessBeforeArchive:
            e.prevAccessBeforeArchive ?? FieldValue.delete(),
          'additionalInfo.graduated': e.prevGraduated ? true : FieldValue.delete(),
        });
        unarchived++;
        reverted++;
        continue;
      }

      const data: Record<string, unknown> = {
        firstName: e.prevFirstName,
        lastName: e.prevLastName,
        classId: e.prevClassId,
      };
      if (e.wroteYearLevel) {
        data['additionalInfo.yearLevel'] = e.prevYearLevel ?? FieldValue.delete();
        data['additionalInfo.yearLevelSetForYear'] = e.prevYearLevelSetForYear ?? FieldValue.delete();
      }
      if (e.wroteParentEmail) {
        data.parentEmail = e.prevParentEmail ?? null;
        data['additionalInfo.pendingParentEmail'] = e.prevPendingParentEmail ?? FieldValue.delete();
      }
      if (e.wroteExternalId) {
        data.studentId = e.prevExternalId ?? null;
      }
      if (e.action === 'restore_move' && !e.prevIsActive) {
        // Put the student back into the archived state they were in.
        data.isActive = false;
        data.status = 'archived';
        data.archivedAt = e.prevArchivedAtMs ? new Date(e.prevArchivedAtMs) : new Date();
        data.archivedReason = e.prevArchivedReason ?? 'manual';
        data.archivedBy = e.prevArchivedBy ?? undoneBy;
        data.access = e.prevAccess ?? FieldValue.delete();
        data.accessBeforeArchive =
          e.prevAccessBeforeArchive ?? FieldValue.delete();
        rearchived++;
      }
      batch.update(ref, data);
      reverted++;
    }
    await batch.commit();
  }

  // 4. Roster mirrors: reverse every move/restore/archive membership change.
  const leaving = new Map<string, Set<string>>();
  const arriving = new Map<string, Set<string>>();
  const add = (map: Map<string, Set<string>>, classId: string | null | undefined, id: string) => {
    if (!classId) return;
    const set = map.get(classId) ?? new Set<string>();
    set.add(id);
    map.set(classId, set);
  };
  for (const e of entries) {
    if (!present.has(e.studentDocId)) continue;
    if (e.action === 'archive') {
      add(arriving, e.prevClassId, e.studentDocId); // back onto the roster
    } else if (e.action === 'restore_move' && !e.prevIsActive) {
      add(leaving, e.newClassId, e.studentDocId); // re-archived — off the roster
    } else if (e.prevClassId !== e.newClassId) {
      add(leaving, e.newClassId, e.studentDocId);
      add(arriving, e.prevClassId, e.studentDocId);
    }
  }
  // Removes then unions as separate phases — same doc+field must not share a
  // batch when a class both loses and regains members.
  const removePhase: { ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown> }[] = [];
  const unionPhase: { ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown> }[] = [];
  for (const [classId, ids] of leaving) {
    if (ids.size > 0) removePhase.push({ ref: classesRef.doc(classId), data: { studentIds: FieldValue.arrayRemove(...ids) } });
  }
  for (const [classId, ids] of arriving) {
    if (ids.size > 0) unionPhase.push({ ref: classesRef.doc(classId), data: { studentIds: FieldValue.arrayUnion(...ids) } });
  }
  for (const ops of [removePhase, unionPhase]) {
    for (let i = 0; i < ops.length; i += BATCH_SIZE) {
      const batch = adminDb.batch();
      for (const op of ops.slice(i, i + BATCH_SIZE)) batch.update(op.ref, op.data);
      await batch.commit();
    }
  }

  // 5. Soft-delete classes the import created, once nothing active points at
  //    them (skip-notes may have legitimately left someone there).
  const createdClasses = ((importData.createdClasses as { key: string; name: string; docId: string }[] | undefined) ?? []);
  for (const c of createdClasses) {
    const inUse = await studentsRef.where('classId', '==', c.docId).where('isActive', '==', true).limit(1).get();
    if (inUse.empty) {
      await classesRef.doc(c.docId).update({ isActive: false });
    }
  }

  // 6. Re-add reading-group memberships the import removed.
  const groupsDoc = await importRef.collection('entryChunks').doc('groups').get();
  const removedGroups = ((groupsDoc.data()?.removed ?? []) as { groupId: string; studentIds: string[] }[]);
  if (removedGroups.length > 0) {
    for (let i = 0; i < removedGroups.length; i += BATCH_SIZE) {
      const batch = adminDb.batch();
      for (const g of removedGroups.slice(i, i + BATCH_SIZE)) {
        const stillHere = g.studentIds.filter((id) => present.has(id));
        if (stillHere.length === 0) continue;
        batch.update(schoolRef.collection('readingGroups').doc(g.groupId), {
          studentIds: FieldValue.arrayUnion(...stillHere),
        });
      }
      await batch.commit();
    }
  }

  // 7. Un-revoke the link codes the import revoked (skip expired ones).
  const codesDoc = await importRef.collection('entryChunks').doc('codes').get();
  const codeIds = ((codesDoc.data()?.codeIds ?? []) as string[]);
  if (codeIds.length > 0) {
    const refs = codeIds.map((id) => adminDb.collection('studentLinkCodes').doc(id));
    const snaps = await adminDb.getAll(...refs);
    const now = Date.now();
    const batch = adminDb.batch();
    for (const s of snaps) {
      if (!s.exists) continue;
      const d = s.data()!;
      if (d.status !== 'revoked' || d.revokeReason !== 'student_archived') continue;
      const expiresAt = d.expiresAt?.toMillis?.() ?? 0;
      if (expiresAt <= now) continue;
      batch.update(s.ref, {
        status: 'active',
        revokedAt: FieldValue.delete(),
        revokeReason: FieldValue.delete(),
      });
    }
    await batch.commit();
  }

  // 8. Counter + status flip — atomically, so a re-run of a crashed undo can't
  //    double-apply the counter.
  const counterDelta = unarchived - rearchived;
  const finalBatch = adminDb.batch();
  if (counterDelta !== 0) {
    finalBatch.update(schoolRef, { studentCount: FieldValue.increment(counterDelta) });
  }
  finalBatch.update(importRef, {
    status: 'undone',
    undoneBy,
    undoneAt: FieldValue.serverTimestamp(),
  });
  await finalBatch.commit();

  return { reverted, createdDeleted, skippedMissing: entries.length - reverted };
}

/** Most-recent rollover imports (for the wizard's history / undo list). */
export async function getRecentRolloverImports(
  schoolId: string,
  max = 5
): Promise<RolloverImportSummary[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('rolloverImports')
    .orderBy('performedAt', 'desc')
    .limit(max)
    .get();
  return snap.docs.map((doc) => {
    const d = doc.data();
    const performedAt = d.performedAt as { toDate?: () => Date } | undefined;
    const undoneAt = d.undoneAt as { toDate?: () => Date } | undefined;
    return {
      id: doc.id,
      status: (d.status as RolloverImportSummary['status']) ?? 'failed',
      targetAcademicYear: (d.targetAcademicYear as number) ?? 0,
      counts: (d.counts as RolloverCommitCounts | undefined) ?? null,
      performedByName: (d.performedByName as string | null) ?? null,
      performedAtIso: performedAt?.toDate ? performedAt.toDate().toISOString() : null,
      undoneAtIso: undoneAt?.toDate ? undoneAt.toDate().toISOString() : null,
    };
  });
}
