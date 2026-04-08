export type NotificationAudienceType = "students" | "classes" | "school";

export interface NotificationPermissions {
  assignedClasses: boolean;
  assignedStudents: boolean;
  schedule: boolean;
  wholeSchool: boolean;
}

export interface AudienceValidationInput {
  role: string;
  permissions?: unknown;
  audienceType: NotificationAudienceType;
  allowedClassIds: string[];
  targetClassIds?: string[];
  studentClassIds?: string[];
  scheduledForMs?: number | null;
}

export interface AudienceValidationResult {
  ok: boolean;
  reason?: string;
}

export interface RecipientStudent {
  id: string;
  firstName: string;
  classId: string;
  parentIds: string[];
}

export interface ParentRecipient {
  parentId: string;
  studentIds: string[];
  studentNames: string[];
  classIds: string[];
}

interface QuietHoursShape {
  start?: string | null;
  end?: string | null;
}

function boolOrDefault(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

export function defaultNotificationPermissions(role: string): NotificationPermissions {
  if (role === "schoolAdmin") {
    return {
      assignedClasses: true,
      assignedStudents: true,
      schedule: true,
      wholeSchool: true,
    };
  }

  return {
    assignedClasses: true,
    assignedStudents: true,
    schedule: true,
    wholeSchool: false,
  };
}

export function normalizeNotificationPermissions(
  role: string,
  rawPermissions?: unknown,
): NotificationPermissions {
  const defaults = defaultNotificationPermissions(role);
  const hasNotifications = typeof rawPermissions === "object" &&
    rawPermissions !== null &&
    "notifications" in rawPermissions;
  const notifications = hasNotifications ?
    (rawPermissions as {notifications?: Record<string, unknown>}).notifications :
    undefined;

  return {
    assignedClasses: boolOrDefault(notifications?.assignedClasses, defaults.assignedClasses),
    assignedStudents: boolOrDefault(notifications?.assignedStudents, defaults.assignedStudents),
    schedule: boolOrDefault(notifications?.schedule, defaults.schedule),
    wholeSchool: boolOrDefault(notifications?.wholeSchool, defaults.wholeSchool),
  };
}

export function validateNotificationAudience(
  input: AudienceValidationInput,
): AudienceValidationResult {
  const permissions = normalizeNotificationPermissions(input.role, input.permissions);
  const allowedClassIds = new Set(input.allowedClassIds);
  const targetClassIds = [...new Set(input.targetClassIds ?? [])];
  const studentClassIds = [...new Set(input.studentClassIds ?? [])];
  const hasSchedule = (input.scheduledForMs ?? 0) > 0;

  if (hasSchedule && !permissions.schedule) {
    return {ok: false, reason: "You do not have permission to schedule notifications."};
  }

  if (input.role !== "teacher" && input.role !== "schoolAdmin") {
    return {ok: false, reason: "Only teachers and school admins can send notifications."};
  }

  switch (input.audienceType) {
  case "school":
    if (!permissions.wholeSchool) {
      return {ok: false, reason: "You do not have permission to notify the whole school."};
    }
    return {ok: true};

  case "classes":
    if (!permissions.assignedClasses) {
      return {ok: false, reason: "You do not have permission to notify classes."};
    }
    if (targetClassIds.length === 0) {
      return {ok: false, reason: "Select at least one class."};
    }
    if (input.role === "teacher" && targetClassIds.some((classId) => !allowedClassIds.has(classId))) {
      return {ok: false, reason: "Teachers can only notify their assigned classes."};
    }
    return {ok: true};

  case "students":
    if (!permissions.assignedStudents) {
      return {ok: false, reason: "You do not have permission to notify students."};
    }
    if (studentClassIds.length === 0) {
      return {ok: false, reason: "Select at least one student."};
    }
    if (input.role === "teacher" && studentClassIds.some((classId) => !allowedClassIds.has(classId))) {
      return {ok: false, reason: "Teachers can only notify students in their assigned classes."};
    }
    return {ok: true};

  default:
    return {ok: false, reason: "Unsupported audience type."};
  }
}

export function mergeRecipientsByParent(students: RecipientStudent[]): ParentRecipient[] {
  const recipients = new Map<string, {
    studentIds: Set<string>;
    studentNames: Set<string>;
    classIds: Set<string>;
  }>();

  for (const student of students) {
    for (const parentId of student.parentIds) {
      if (!recipients.has(parentId)) {
        recipients.set(parentId, {
          studentIds: new Set<string>(),
          studentNames: new Set<string>(),
          classIds: new Set<string>(),
        });
      }

      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      const bucket = recipients.get(parentId)!;
      bucket.studentIds.add(student.id);
      bucket.studentNames.add(student.firstName);
      bucket.classIds.add(student.classId);
    }
  }

  return [...recipients.entries()].map(([parentId, bucket]) => ({
    parentId,
    studentIds: [...bucket.studentIds],
    studentNames: [...bucket.studentNames],
    classIds: [...bucket.classIds],
  }));
}

export function isDueAt(scheduledForMs: number | null | undefined, nowMs: number): boolean {
  if (!scheduledForMs) return true;
  return scheduledForMs <= nowMs;
}

export function parseTimeString(value?: string | null): {hour: number; minute: number} | null {
  if (!value) return null;

  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;

  const hour = parseInt(match[1], 10);
  const minute = parseInt(match[2], 10);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }

  return {hour, minute};
}

function getLocalMinutes(utcNow: Date, timezone: string): number {
  try {
    const formatter = new Intl.DateTimeFormat("en-GB", {
      timeZone: timezone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    });

    const parts = formatter.formatToParts(utcNow);
    const hour = parseInt(parts.find((part) => part.type === "hour")?.value ?? "0", 10);
    const minute = parseInt(parts.find((part) => part.type === "minute")?.value ?? "0", 10);
    return (hour * 60) + minute;
  } catch {
    return (utcNow.getUTCHours() * 60) + utcNow.getUTCMinutes();
  }
}

export function isWithinQuietHours(
  utcNow: Date,
  timezone: string,
  quietHours?: QuietHoursShape | null,
): boolean {
  const start = parseTimeString(quietHours?.start);
  const end = parseTimeString(quietHours?.end);
  if (!start || !end) return false;

  const startMinutes = (start.hour * 60) + start.minute;
  const endMinutes = (end.hour * 60) + end.minute;
  if (startMinutes === endMinutes) return false;

  const localMinutes = getLocalMinutes(utcNow, timezone);

  if (startMinutes < endMinutes) {
    return localMinutes >= startMinutes && localMinutes < endMinutes;
  }

  return localMinutes >= startMinutes || localMinutes < endMinutes;
}
