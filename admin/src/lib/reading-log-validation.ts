export interface ReadingLogValidationInput {
  minutesRead?: unknown;
  parentId?: unknown;
  loggedByRole?: unknown;
}

export function validateReadingLogForReview(
  log: ReadingLogValidationInput,
  student: { exists: boolean; parentIds: unknown }
): string[] {
  const errors: string[] = [];
  const minutes = Number(log.minutesRead);

  if (!Number.isFinite(minutes) || minutes < 1 || minutes > 240) {
    errors.push("Minutes read must be between 1 and 240");
  }

  if (!student.exists) {
    errors.push("Student does not exist");
    return errors;
  }

  const isTeacherProxy = log.loggedByRole === "teacher";
  const parentIds = Array.isArray(student.parentIds)
    ? student.parentIds.filter(
        (value): value is string => typeof value === "string"
      )
    : [];
  if (
    !isTeacherProxy &&
    (typeof log.parentId !== "string" || !parentIds.includes(log.parentId))
  ) {
    errors.push("Parent not linked to this student");
  }

  return errors;
}
