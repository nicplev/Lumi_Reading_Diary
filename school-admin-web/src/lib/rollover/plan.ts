// The RESOLVED rollover plan — what the admin confirmed on the review screen,
// posted to /api/rollover/commit. Built by the wizard from the preview
// (lib/rollover/classify.ts) plus the admin's per-row overrides. Pure types,
// no Firestore imports.

/** Move a matched (active) student to their new class / year level. */
export interface MoveAction {
  action: 'move';
  studentDocId: string;
  /** CSV names are applied (ID wins over name — same as the legacy upsert). */
  firstName: string;
  lastName: string;
  className: string;
  yearLevel?: string;
  parentEmail?: string;
}

/** Confirmed name-suggestion: same as move, plus the external-ID backfill. */
export interface BackfillMoveAction extends Omit<MoveAction, 'action'> {
  action: 'backfill_move';
  externalId: string;
}

/** Matched an archived student: restore, then move. */
export interface RestoreMoveAction extends Omit<MoveAction, 'action'> {
  action: 'restore_move';
}

/** Brand-new student (new Preps / joiners). */
export interface CreateAction {
  action: 'create';
  externalId?: string;
  firstName: string;
  lastName: string;
  className: string;
  yearLevel?: string;
  parentEmail?: string;
  readingLevel?: string;
}

/** Missing student the admin confirmed as graduating/leaving. */
export interface ArchiveAction {
  action: 'archive';
  studentDocId: string;
  reason: 'graduated' | 'left';
}

export type RolloverAction =
  | MoveAction
  | BackfillMoveAction
  | RestoreMoveAction
  | CreateAction
  | ArchiveAction;

export interface RolloverPlan {
  targetAcademicYear: number;
  actions: RolloverAction[];
  /** Opt-in deactivations from the emptyAfterImport list (class renames). */
  classesToDeactivate: string[];
}

export interface RolloverCommitCounts {
  moved: number;
  created: number;
  restored: number;
  archivedGraduates: number;
  archivedLeavers: number;
  idBackfills: number;
  classesCreated: number;
  classesDeactivated: number;
}

export interface RolloverCommitResult {
  importId: string;
  counts: RolloverCommitCounts;
  /** Actions skipped because the data changed since the preview. */
  skipped: { index: number; note: string }[];
  /** True when this importId had already fully applied (idempotent retry). */
  alreadyApplied: boolean;
}
