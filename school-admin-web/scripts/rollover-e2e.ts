// End-to-end verification of the annual rollover import against a DISPOSABLE
// test school in lumi-ninc-au (user-approved). Exercises the real portal lib
// functions (the same modules the API routes call). Run from school-admin-web:
//   FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/Users/nicplev/keys/lumi-ninc-au-admin.json \
//     npx tsx <scratchpad>/rollover-e2e.ts
// Everything lives under schools/zz-rollover-test-e2e (+ scoped studentLinkCodes
// and one schoolSubscriptions doc), all deleted in CLEANUP — even on failure.

import assert from 'node:assert/strict';

const SCHOOL_ID = 'zz-rollover-test-e2e';
const TARGET_YEAR = 2027;

async function main() {
  const { adminDb } = await import('@/lib/firebase/admin');
  const { previewRollover, commitRollover, undoRolloverImport } = await import('@/lib/firestore/rollover');
  const { archiveStudents } = await import('@/lib/firestore/students');
  const { getRenewalRoster, renewStudents } = await import('@/lib/firestore/renewals');
  const { FieldValue } = await import('firebase-admin/firestore');
  type Row = import('@/lib/rollover/classify').RolloverCSVRow;

  const schoolRef = adminDb.collection('schools').doc(SCHOOL_ID);
  const studentsRef = schoolRef.collection('students');
  const classesRef = schoolRef.collection('classes');

  let pass = 0;
  const check = (name: string, fn: () => void) => {
    try {
      fn();
      pass++;
      console.log(`  ✓ ${name}`);
    } catch (e) {
      console.error(`  ✗ ${name}`);
      throw e;
    }
  };

  const cleanup = async () => {
    console.log('\nCLEANUP…');
    // Scoped link codes first (top-level collection).
    const codes = await adminDb.collection('studentLinkCodes').where('schoolId', '==', SCHOOL_ID).get();
    for (const d of codes.docs) await d.ref.delete();
    await adminDb.collection('schoolSubscriptions').doc(`${SCHOOL_ID}_${TARGET_YEAR}`).delete();
    await adminDb.recursiveDelete(schoolRef);
    console.log(`Cleaned: ${codes.size} link codes, 1 subscription, school tree.`);
  };

  // Belt & braces: if a previous run died, start clean.
  if ((await schoolRef.get()).exists) await cleanup();

  try {
    // ════════ SETUP ════════
    console.log('SETUP: seeding test school…');
    const mk = (over: Record<string, unknown>) => ({
      schoolId: SCHOOL_ID,
      parentIds: [],
      isActive: true,
      enrollmentStatus: 'not_enrolled',
      createdAt: new Date(),
      enrolledAt: new Date(),
      createdBy: 'e2e',
      additionalInfo: {},
      levelHistory: [],
      stats: { totalMinutesRead: 0, totalBooksRead: 0, currentStreak: 0, longestStreak: 0, averageMinutesPerDay: 0, totalReadingDays: 0 },
      ...over,
    });
    const classDoc = (name: string, yearLevel: string) => ({
      name, schoolId: SCHOOL_ID, yearLevel, teacherIds: [], studentIds: [] as string[],
      defaultMinutesTarget: 15, isActive: true, createdAt: new Date(), createdBy: 'e2e',
    });

    await schoolRef.set({
      name: 'ZZ Rollover Test (E2E — safe to delete)',
      isActive: false, // keep it out of crons/dashboards
      studentCount: 0,
      timezone: 'Australia/Sydney',
      createdAt: new Date(),
    });
    await classesRef.doc('c-prep').set(classDoc('Prep A', 'Prep'));
    await classesRef.doc('c-3a').set(classDoc('3A', '3'));
    await classesRef.doc('c-5b').set(classDoc('5B', '5'));
    await classesRef.doc('c-6a').set(classDoc('6A', '6'));

    const seed: Record<string, Record<string, unknown>> = {
      // 3A → will move to 4A
      's-301': mk({ studentId: 'T3001', firstName: 'Ava', lastName: 'Reed', classId: 'c-3a' }),
      's-302': mk({ studentId: 'T3002', firstName: 'Ben', lastName: 'Cole', classId: 'c-3a' }),
      's-303': mk({ studentId: 'T3003', firstName: 'Cal', lastName: 'Diaz', classId: 'c-3a' }), // repeater (year 3 again)
      's-304': mk({ studentId: 'T3004', firstName: 'Dee', lastName: 'Ellis', classId: 'c-3a' }), // CSV renames to Deanna
      's-mia': mk({ studentId: null, firstName: 'Mia', lastName: 'Nguyễn', classId: 'c-3a' }), // no ID → suggest
      's-306': mk({ studentId: 'T3006', firstName: 'Eli', lastName: 'Fox', classId: 'c-3a', additionalInfo: { yearLevel: '3' } }), // blank CSV year → renewal must still bump
      // 5B → renamed to 6 Blue
      's-501': mk({ studentId: 'T5001', firstName: 'Gus', lastName: 'Hale', classId: 'c-5b' }),
      's-502': mk({ studentId: 'T5002', firstName: 'Ida', lastName: 'Jones', classId: 'c-5b' }),
      // 6A → graduating (absent from CSV)
      's-601': mk({ studentId: 'T6001', firstName: 'Kai', lastName: 'Lowe', classId: 'c-6a', parentIds: ['e2e-parent-1'] }),
      's-602': mk({ studentId: 'T6002', firstName: 'Lia', lastName: 'Moss', classId: 'c-6a' }),
      's-603': mk({ studentId: 'T6003', firstName: 'Noa', lastName: 'Odum', classId: 'c-6a' }),
      // Prep A → moving to (new) 1A
      's-p01': mk({ studentId: 'TP001', firstName: 'Pia', lastName: 'Quill', classId: 'c-prep' }),
      's-p02': mk({ studentId: 'TP002', firstName: 'Rex', lastName: 'Shaw', classId: 'c-prep' }),
      // Archived last year, back this year under the same ID
      's-999': mk({ studentId: 'T9999', firstName: 'Tam', lastName: 'Vance', classId: 'c-3a' }),
    };
    for (const [id, doc] of Object.entries(seed)) {
      await studentsRef.doc(id).set(doc);
      const cid = doc.classId as string;
      await classesRef.doc(cid).update({ studentIds: FieldValue.arrayUnion(id) });
    }
    await schoolRef.update({ studentCount: Object.keys(seed).length });
    // Linked parent for s-601 (links must survive archive).
    await schoolRef.collection('parents').doc('e2e-parent-1').set({ linkedChildren: ['s-601'], createdAt: new Date() });
    // Active link code for s-601 (must be revoked on archive, un-revoked on undo).
    await adminDb.collection('studentLinkCodes').doc('e2e-code-1').set({
      code: 'ZZTEST99', schoolId: SCHOOL_ID, studentId: 's-601', studentName: 'Kai Lowe',
      classId: 'c-6a', status: 'active', intendedFor: 'staff_issued',
      createdAt: new Date(), expiresAt: new Date(Date.now() + 300 * 86400e3), createdBy: 'e2e',
    });
    // Reading group in 3A containing movers (must be cleaned on import, restored on undo).
    await schoolRef.collection('readingGroups').doc('g-3a').set({
      classId: 'c-3a', name: 'Red group', studentIds: ['s-301', 's-302'], createdAt: new Date(),
    });
    // Archive s-999 through the real path (also removes from roster, -1 count).
    await archiveStudents(SCHOOL_ID, ['s-999'], 'left', 'e2e');
    const baseCount = (await schoolRef.get()).data()!.studentCount as number;
    check('setup: studentCount after seeding + archiving one', () => assert.equal(baseCount, 13));

    // ════════ SCENARIO A: preview ════════
    console.log('\nSCENARIO A: dry-run preview…');
    const csv: Row[] = [
      { studentId: 'T3001', firstName: 'Ava', lastName: 'Reed', className: '4A', yearLevel: '4' },
      { studentId: 't3002 ', firstName: 'Ben', lastName: 'Cole', className: '4A', yearLevel: '4' }, // case/space in ID
      { studentId: 'T3003', firstName: 'Cal', lastName: 'Diaz', className: '4A', yearLevel: '3' }, // repeater
      { studentId: 'T3004', firstName: 'Deanna', lastName: 'Ellis', className: '4A', yearLevel: '4' }, // renamed
      { studentId: 'T3100', firstName: 'Mia', lastName: 'Nguyen', className: '4A', yearLevel: '4' }, // suggest + backfill
      { studentId: 'T3006', firstName: 'Eli', lastName: 'Fox', className: '4A' }, // NO year level → no marker
      { studentId: 'T5001', firstName: 'Gus', lastName: 'Hale', className: '6 Blue', yearLevel: '6' },
      { studentId: 'T5002', firstName: 'Ida', lastName: 'Jones', className: '6 Blue', yearLevel: '6' },
      { studentId: 'TP001', firstName: 'Pia', lastName: 'Quill', className: '1A', yearLevel: '1' },
      { studentId: 'TP002', firstName: 'Rex', lastName: 'Shaw', className: '1A', yearLevel: '1' },
      { studentId: 'T9999', firstName: 'Tam', lastName: 'Vance', className: '4A', yearLevel: '4' }, // archived → restore
      { studentId: 'P2001', firstName: 'Uma', lastName: 'West', className: 'Prep A', yearLevel: 'Prep', parentEmail: 'uma.parent@example.com' },
      { firstName: 'Zed', lastName: 'Zane', className: 'Prep A', yearLevel: 'Prep' }, // ID-less new
      { studentId: 'TDUP', firstName: 'Dup', lastName: 'One', className: '4A', yearLevel: '4' },
      { studentId: 'TDUP', firstName: 'Dup', lastName: 'Two', className: '4A', yearLevel: '4' },
    ];
    const preview = await previewRollover(SCHOOL_ID, csv, TARGET_YEAR);
    const rowByIdx = (i: number) => preview.rows[i];

    check('A: buckets', () => {
      assert.equal(preview.stats.match, 9);
      assert.equal(preview.stats.matchArchived, 1);
      assert.equal(preview.stats.nameSuggest, 1); // Mia
      assert.equal(preview.stats.new, 2); // Uma (unknown ID) + Zed (no ID)
      assert.equal(preview.stats.error, 2); // TDUP twice
    });
    check('A: P2001 is new despite having an ID', () => assert.equal(rowByIdx(11).bucket, 'new'));
    check('A: ID matching is case/space-insensitive', () => assert.equal(rowByIdx(1).matchedStudentDocId, 's-302'));
    check('A: repeater flagged off-ladder', () => assert.equal(rowByIdx(2).offLadder, true));
    check('A: rename flagged, ID wins', () => assert.equal(rowByIdx(3).nameMismatch?.storedName, 'Dee Ellis'));
    check('A: suggestion found for Mia (diacritics-insensitive)', () => {
      assert.equal(rowByIdx(4).bucket, 'name_suggest');
      assert.equal(rowByIdx(4).candidates?.[0].docId, 's-mia');
    });
    check('A: archived T9999 → match_archived', () => assert.equal(rowByIdx(10).bucket, 'match_archived'));
    check('A: missing = 6A cohort, all graduating (top year)', () => {
      const byId = new Map(preview.missing.map((m) => [m.docId, m]));
      assert.equal(byId.size, 4); // s-601..603 + s-mia (unconfirmed suggestion)
      for (const id of ['s-601', 's-602', 's-603']) assert.equal(byId.get(id)?.disposition, 'graduating');
      assert.equal(byId.get('s-mia')?.disposition, 'leaver');
      assert.deepEqual(byId.get('s-mia')?.suggestedInRows, [5]);
    });
    check('A: classes to create', () =>
      assert.deepEqual(preview.classes.toCreate.map((c) => c.name).sort(), ['1A', '4A', '6 Blue']));
    check('A: 6A whole-class-missing; 3A/5B/PrepA empty analysis', () => {
      assert.deepEqual(preview.classes.wholeClassMissing.map((c) => c.docId), ['c-6a']);
      const empty = preview.classes.emptyAfterImport.map((c) => c.docId).sort();
      assert.deepEqual(empty, ['c-3a', 'c-5b', 'c-6a']); // Prep A gains new preps → not empty
    });

    // ════════ SCENARIO B: commit ════════
    console.log('\nSCENARIO B: commit…');
    const base = (r: Row) => ({
      firstName: r.firstName, lastName: r.lastName, className: r.className,
      yearLevel: r.yearLevel, parentEmail: r.parentEmail,
    });
    const plan = {
      targetAcademicYear: TARGET_YEAR,
      actions: [
        { action: 'move' as const, studentDocId: 's-301', ...base(csv[0]) },
        { action: 'move' as const, studentDocId: 's-302', ...base(csv[1]) },
        { action: 'move' as const, studentDocId: 's-303', ...base(csv[2]) },
        { action: 'move' as const, studentDocId: 's-304', ...base(csv[3]) },
        { action: 'backfill_move' as const, studentDocId: 's-mia', externalId: 'T3100', ...base(csv[4]) },
        { action: 'move' as const, studentDocId: 's-306', ...base(csv[5]) },
        { action: 'move' as const, studentDocId: 's-501', ...base(csv[6]) },
        { action: 'move' as const, studentDocId: 's-502', ...base(csv[7]) },
        { action: 'move' as const, studentDocId: 's-p01', ...base(csv[8]) },
        { action: 'move' as const, studentDocId: 's-p02', ...base(csv[9]) },
        { action: 'restore_move' as const, studentDocId: 's-999', ...base(csv[10]) },
        { action: 'create' as const, externalId: 'P2001', ...base(csv[11]) },
        { action: 'create' as const, ...base(csv[12]) },
        { action: 'archive' as const, studentDocId: 's-601', reason: 'graduated' as const },
        { action: 'archive' as const, studentDocId: 's-602', reason: 'graduated' as const },
        { action: 'archive' as const, studentDocId: 's-603', reason: 'graduated' as const },
      ],
      classesToDeactivate: ['c-3a'],
    };
    const importId = 'e2e00000-0000-4000-8000-000000000001';
    const result = await commitRollover(SCHOOL_ID, plan, importId, 'e2e', 'E2E Harness');

    check('B: counts', () => {
      assert.equal(result.alreadyApplied, false);
      assert.equal(result.counts.moved, 10);
      assert.equal(result.counts.created, 2);
      assert.equal(result.counts.restored, 1);
      assert.equal(result.counts.archivedGraduates, 3);
      assert.equal(result.counts.idBackfills, 1);
      assert.equal(result.counts.classesCreated, 3);
      assert.equal(result.skipped.length, 0);
    });

    const doc = async (id: string) => (await studentsRef.doc(id).get()).data()!;
    const classByName = new Map<string, { id: string; data: FirebaseFirestore.DocumentData }>();
    for (const c of (await classesRef.get()).docs) classByName.set(c.data().name, { id: c.id, data: c.data() });

    const c4a = classByName.get('4A')!;
    {
      const s301 = await doc('s-301');
      assert.equal(s301.classId, c4a.id);
      assert.equal(s301.additionalInfo.yearLevel, '4');
      assert.equal(s301.additionalInfo.yearLevelSetForYear, TARGET_YEAR);
      const s304 = await doc('s-304');
      assert.equal(s304.firstName, 'Deanna');
      pass++; console.log('  ✓ B: mover fields — class, year, marker, CSV name applied');
    }
    {
      const mia = await doc('s-mia');
      assert.equal(mia.studentId, 'T3100');
      assert.equal(mia.classId, c4a.id);
      pass++; console.log('  ✓ B: Mia backfilled with T3100 and moved');
    }
    {
      const eli = await doc('s-306');
      assert.equal(eli.additionalInfo.yearLevel, '3'); // untouched (blank CSV year)
      assert.equal(eli.additionalInfo.yearLevelSetForYear, undefined);
      pass++; console.log('  ✓ B: blank CSV year → yearLevel untouched, no marker');
    }
    {
      const tam = await doc('s-999');
      assert.equal(tam.isActive, true);
      assert.equal(tam.status, undefined);
      assert.equal(tam.classId, c4a.id);
      pass++; console.log('  ✓ B: archived T9999 restored + moved');
    }
    {
      const kai = await doc('s-601');
      assert.equal(kai.isActive, false);
      assert.equal(kai.archivedReason, 'graduated');
      assert.equal(kai.additionalInfo.graduated, true);
      assert.deepEqual(kai.parentIds, ['e2e-parent-1']); // links survive
      const code = (await adminDb.collection('studentLinkCodes').doc('e2e-code-1').get()).data()!;
      assert.equal(code.status, 'revoked');
      assert.equal(code.revokeReason, 'student_archived');
      pass++; console.log('  ✓ B: graduate archived — reason, flag, parent link kept, code revoked');
    }
    {
      const created = await studentsRef.where('createdByImport', '==', importId).get();
      assert.equal(created.size, 2);
      const uma = created.docs.find((d) => d.data().firstName === 'Uma')!.data();
      assert.equal(uma.additionalInfo.pendingParentEmail, 'uma.parent@example.com');
      assert.equal(uma.access, undefined); // access NEVER granted by import
      pass++; console.log('  ✓ B: creates — pendingParentEmail set, NO access granted');
    }
    {
      const c3a = (await classesRef.doc('c-3a').get()).data()!;
      assert.equal(c3a.isActive, false); // opted-in deactivation
      assert.deepEqual(c3a.studentIds, []);
      assert.equal((c4a.data.studentIds as string[]).length >= 6, true);
      const group = (await schoolRef.collection('readingGroups').doc('g-3a').get()).data()!;
      assert.deepEqual(group.studentIds, []); // movers cleaned out
      pass++; console.log('  ✓ B: rosters + deactivation + reading-group cleanup');
    }
    {
      const count = (await schoolRef.get()).data()!.studentCount;
      assert.equal(count, baseCount + 2 + 1 - 3); // +creates +restore −archives
      pass++; console.log('  ✓ B: studentCount delta correct');
    }

    // ════════ SCENARIO C: idempotency ════════
    console.log('\nSCENARIO C: idempotent retry + re-preview…');
    const retry = await commitRollover(SCHOOL_ID, plan, importId, 'e2e', 'E2E Harness');
    check('C: same importId → alreadyApplied, same counts, no double-apply', () => {
      assert.equal(retry.alreadyApplied, true);
      assert.equal(retry.counts.moved, 10);
    });
    {
      const count = (await schoolRef.get()).data()!.studentCount;
      assert.equal(count, baseCount + 2 + 1 - 3);
      pass++; console.log('  ✓ C: studentCount unchanged after retry');
    }
    {
      const re = await previewRollover(SCHOOL_ID, csv, TARGET_YEAR);
      assert.equal(re.stats.match, 12); // Mia + Tam now ID-match; P2001 matches its created student
      assert.equal(re.stats.matchArchived, 0);
      // ID-less Zed's created doc resurfaces as a name suggestion (the wizard
      // warns about ID-less rows for exactly this reason) — NOT a blind dup.
      assert.equal(re.stats.nameSuggest, 1);
      assert.equal(re.stats.new, 0);
      assert.equal(re.missing.length, 1);
      assert.equal(re.missing[0].suggestedInRows.length, 1);
      pass++; console.log('  ✓ C: re-preview — all ID rows match; ID-less Zed resurfaces as a suggestion, not a duplicate');
    }

    // ════════ SCENARIO D: renewals interaction ════════
    console.log('\nSCENARIO D: renewal after import (no double-bump)…');
    await adminDb.collection('schoolSubscriptions').doc(`${SCHOOL_ID}_${TARGET_YEAR}`).set({
      schoolId: SCHOOL_ID, academicYear: TARGET_YEAR, status: 'comp', createdAt: new Date(),
    });
    const roster = await getRenewalRoster(SCHOOL_ID, TARGET_YEAR);
    const rosterById = new Map(roster.map((r) => [r.studentId, r]));
    check('D: roster excludes archived, marks imported year levels', () => {
      assert.equal(rosterById.has('s-601'), false); // archived → gone
      const ava = rosterById.get('s-301')!;
      assert.equal(ava.yearLevelSetByImport, true);
      assert.equal(ava.nextYearLevel, '4'); // held, not bumped
      const eli = rosterById.get('s-306')!;
      assert.equal(eli.yearLevelSetByImport, false);
      assert.equal(eli.nextYearLevel, '4'); // 3 → 4 bump still offered
    });
    await renewStudents(SCHOOL_ID, TARGET_YEAR, ['s-301', 's-306'], 'e2e', 'E2E Harness');
    {
      const ava = await doc('s-301');
      assert.equal(ava.additionalInfo.yearLevel, '4'); // NOT double-bumped to 5
      assert.equal(ava.access.academicYear, TARGET_YEAR);
      assert.equal(ava.access.source, 'school_renewal');
      const eli = await doc('s-306');
      assert.equal(eli.additionalInfo.yearLevel, '4'); // bumped 3 → 4
      pass++; console.log('  ✓ D: renewal grants access; marked student held at 4, unmarked bumped 3→4');
    }

    // ════════ SCENARIO E: undo ════════
    console.log('\nSCENARIO E: undo the import…');
    const undo = await undoRolloverImport(SCHOOL_ID, importId, 'e2e');
    check('E: undo counts', () => {
      assert.equal(undo.createdDeleted, 2);
      assert.equal(undo.reverted, 14); // 10 moves + 1 restore + 3 archives
    });
    {
      const ava = await doc('s-301');
      assert.equal(ava.classId, 'c-3a');
      assert.equal(ava.additionalInfo.yearLevel, undefined); // restored to pre-import (none)
      assert.equal(ava.additionalInfo.yearLevelSetForYear, undefined);
      assert.equal(ava.access.academicYear, TARGET_YEAR); // renewal's access deliberately untouched
      const dee = await doc('s-304');
      assert.equal(dee.firstName, 'Dee'); // name restored
      const mia = await doc('s-mia');
      assert.equal(mia.studentId, null); // backfill removed
      const tam = await doc('s-999');
      assert.equal(tam.isActive, false); // re-archived
      assert.equal(tam.archivedReason, 'left');
      const kai = await doc('s-601');
      assert.equal(kai.isActive, true); // un-archived
      assert.equal(kai.additionalInfo.graduated, undefined);
      pass++; console.log('  ✓ E: students restored — class, year, marker, name, ID, archive states');
    }
    {
      const c3a = (await classesRef.doc('c-3a').get()).data()!;
      assert.equal(c3a.isActive, true); // reactivated
      assert.equal((c3a.studentIds as string[]).sort().length, 6); // 301-304, mia, 306 back
      const created = await classesRef.doc(classByName.get('4A')!.id).get();
      assert.equal(created.data()!.isActive, false); // created class soft-deleted
      const group = (await schoolRef.collection('readingGroups').doc('g-3a').get()).data()!;
      assert.deepEqual((group.studentIds as string[]).sort(), ['s-301', 's-302']); // memberships back
      const code = (await adminDb.collection('studentLinkCodes').doc('e2e-code-1').get()).data()!;
      assert.equal(code.status, 'active'); // un-revoked
      const count = (await schoolRef.get()).data()!.studentCount;
      assert.equal(count, baseCount); // back to the start
      pass++; console.log('  ✓ E: classes, groups, link code, studentCount all restored');
    }
    {
      await assert.rejects(() => undoRolloverImport(SCHOOL_ID, importId, 'e2e'), /already been undone/);
      pass++; console.log('  ✓ E: double-undo rejected');
    }

    console.log(`\nALL SCENARIOS PASSED (${pass} checks).`);
  } finally {
    await cleanup();
  }
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
