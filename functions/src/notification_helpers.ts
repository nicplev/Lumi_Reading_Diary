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

export interface PushTokenRecipient {
  parentId: string;
  token?: string;
}

export interface UniquePushTarget {
  token: string;
  parentIds: string[];
}

export interface UnambiguousPushRecipients<T extends PushTokenRecipient> {
  recipients: T[];
  suppressedTokens: string[];
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

/**
 * Groups recipients by FCM registration token so one physical app install gets
 * one push even if account switching left that token on multiple parent docs.
 * Every owning parent id is retained so each in-app inbox can still receive an
 * accurate push status.
 * @param {PushTokenRecipient[]} recipients Parent records eligible for push.
 * @return {UniquePushTarget[]} One send target per unique device token.
 */
export function mergePushTargetsByToken(
  recipients: PushTokenRecipient[],
): UniquePushTarget[] {
  const ownersByToken = new Map<string, Set<string>>();

  for (const recipient of recipients) {
    const token = recipient.token?.trim();
    if (!token) continue;

    const owners = ownersByToken.get(token) ?? new Set<string>();
    owners.add(recipient.parentId);
    ownersByToken.set(token, owners);
  }

  return [...ownersByToken.entries()].map(([token, parentIds]) => ({
    token,
    parentIds: [...parentIds],
  }));
}

/**
 * Removes targets that would receive account-specific content for more than
 * one parent record. Unlike a school-wide campaign, a reading reminder names
 * a family's children, so collapsing duplicate tokens to one arbitrary parent
 * could disclose the wrong child's name on a shared or previously-used device.
 *
 * This is a defense-in-depth guard. The parent-token ownership trigger keeps
 * the source records exclusive; this helper avoids a bad send while a token
 * hand-off is still propagating.
 * @param {T[]} recipients Parent records eligible for an account-specific push.
 * @return {UnambiguousPushRecipients<T>} Safe recipients and suppressed tokens.
 */
export function excludeAmbiguousPushTokenRecipients<T extends PushTokenRecipient>(
  recipients: T[],
): UnambiguousPushRecipients<T> {
  const ownersByToken = new Map<string, number>();

  for (const recipient of recipients) {
    const token = recipient.token?.trim();
    if (!token) continue;
    ownersByToken.set(token, (ownersByToken.get(token) ?? 0) + 1);
  }

  const suppressedTokens = [...ownersByToken.entries()]
    .filter(([, ownerCount]) => ownerCount > 1)
    .map(([token]) => token);
  const suppressed = new Set(suppressedTokens);

  return {
    recipients: recipients.filter((recipient) => {
      const token = recipient.token?.trim();
      return !!token && !suppressed.has(token);
    }),
    suppressedTokens,
  };
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

/**
 * The school-local hour (0-23) at which a parent wants their reading
 * reminder. Single source of truth shared by sendReadingReminders'
 * eligibility check, the syncParentReminderHour mirror trigger, and
 * scripts/backfill_reminder_hour.js — the denormalized `reminderHour`
 * field on parent docs MUST always equal this function applied to
 * `preferences.reminderTime`, or the scheduler's equality query will
 * miss/mis-hit parents.
 *
 * Mirrors the scheduler's historical inline parse exactly, INCLUDING its
 * quirk: a "00:xx" (midnight) preference falls back to 19 because
 * parseInt yields a falsy 0. Kept bug-for-bug so denormalizing cannot
 * change who gets reminded at which hour.
 * @param {unknown} reminderTime The raw `preferences.reminderTime` value.
 * @return {number} Hour of day the parent should be reminded (default 19).
 */
export function parseReminderHour(reminderTime: unknown): number {
  if (typeof reminderTime !== "string" || reminderTime.length === 0) {
    return 19;
  }
  return parseInt(reminderTime.split(":")[0], 10) || 19;
}
