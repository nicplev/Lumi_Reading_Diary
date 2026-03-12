import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

/**
 * CRITICAL SECURITY: Stats Aggregation
 * Prevents client-side manipulation of student statistics
 * Triggered whenever a reading log is created or updated
 */
export const aggregateStudentStats = functions.firestore
  .document("schools/{schoolId}/readingLogs/{logId}")
  .onWrite(async (change, context) => {
    const schoolId = context.params.schoolId;
    const log = change.after.exists ? change.after.data() : null;

    if (!log) {
      // Log was deleted, we'll handle this separately
      return null;
    }

    const studentId = log.studentId;
    if (!studentId) {
      functions.logger.warn("Reading log has no studentId", {logId: context.params.logId});
      return null;
    }

    const studentRef = db.doc(`schools/${schoolId}/students/${studentId}`);

    try {
      // Get all reading logs for this student
      const logsSnapshot = await db
        .collection(`schools/${schoolId}/readingLogs`)
        .where("studentId", "==", studentId)
        .where("status", "in", ["completed", "partial"])
        .get();

      // Calculate stats from scratch (authoritative source)
      let totalMinutesRead = 0;
      let totalBooksRead = 0;
      let currentStreak = 0;
      let longestStreak = 0;
      let lastReadingDate: admin.firestore.Timestamp | null = null;
      const readingDates: Set<string> = new Set();

      const logsByDate: Array<{date: admin.firestore.Timestamp; minutes: number; books: number}> = [];

      logsSnapshot.docs.forEach((doc) => {
        const logData = doc.data();
        totalMinutesRead += logData.minutesRead || 0;
        totalBooksRead += (logData.bookTitles?.length || 0);

        if (logData.date) {
          const dateStr = logData.date.toDate().toISOString().split("T")[0];
          readingDates.add(dateStr);
          logsByDate.push({
            date: logData.date,
            minutes: logData.minutesRead || 0,
            books: logData.bookTitles?.length || 0,
          });
        }
      });

      // Calculate streaks
      const sortedLogs = logsByDate.sort((a, b) => b.date.toMillis() - a.date.toMillis());

      if (sortedLogs.length > 0) {
        lastReadingDate = sortedLogs[0].date;

        // Calculate current streak
        let streakCount = 0;
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        for (const log of sortedLogs) {
          const logDate = log.date.toDate();
          logDate.setHours(0, 0, 0, 0);

          const expectedDate = new Date(today);
          expectedDate.setDate(expectedDate.getDate() - streakCount);

          if (logDate.getTime() === expectedDate.getTime()) {
            streakCount++;
          } else {
            break;
          }
        }
        currentStreak = streakCount;

        // Calculate longest streak
        let tempStreak = 1;
        for (let i = 0; i < sortedLogs.length - 1; i++) {
          const currentDate = sortedLogs[i].date.toDate();
          const nextDate = sortedLogs[i + 1].date.toDate();

          const diffDays = Math.floor(
            (currentDate.getTime() - nextDate.getTime()) / (1000 * 60 * 60 * 24)
          );

          if (diffDays === 1) {
            tempStreak++;
            longestStreak = Math.max(longestStreak, tempStreak);
          } else {
            tempStreak = 1;
          }
        }
        longestStreak = Math.max(longestStreak, tempStreak, currentStreak);
      }

      const totalReadingDays = readingDates.size;
      const averageMinutesPerDay = totalReadingDays > 0 ? totalMinutesRead / totalReadingDays : 0;

      // Update student document with calculated stats
      await studentRef.update({
        "stats.totalMinutesRead": totalMinutesRead,
        "stats.totalBooksRead": totalBooksRead,
        "stats.currentStreak": currentStreak,
        "stats.longestStreak": longestStreak,
        "stats.lastReadingDate": lastReadingDate,
        "stats.averageMinutesPerDay": Math.round(averageMinutesPerDay * 10) / 10,
        "stats.totalReadingDays": totalReadingDays,
        "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
      });

      functions.logger.info("Student stats aggregated", {
        studentId,
        totalMinutesRead,
        totalBooksRead,
        currentStreak,
      });

      return null;
    } catch (error) {
      functions.logger.error("Error aggregating student stats", {
        studentId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  });

// ---------------------------------------------------------------------------
// Reading reminders — scalable, cost-effective, per-parent scheduling
// ---------------------------------------------------------------------------

/** Max messages per sendEach call (FCM limit) */
const FCM_BATCH_LIMIT = 500;

/** How many schools to process concurrently (prevents OOM on large deployments) */
const SCHOOL_CONCURRENCY = 10;

/** Firestore `in` query limit */
const FIRESTORE_IN_LIMIT = 30;

/**
 * Helper: resolve local hour & ISO weekday for a timezone.
 */
function getLocalTime(utcNow: Date, tz: string): {hour: number; weekday: number} {
  try {
    const hf = new Intl.DateTimeFormat("en-GB", {timeZone: tz, hour: "numeric", hour12: false});
    const hour = parseInt(hf.format(utcNow), 10);

    const df = new Intl.DateTimeFormat("en-GB", {timeZone: tz, weekday: "short"});
    const dayMap: Record<string, number> = {Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7};
    const weekday = dayMap[df.format(utcNow)] ?? 1;

    return {hour, weekday};
  } catch {
    const hour = utcNow.getUTCHours();
    const weekday = utcNow.getUTCDay() === 0 ? 7 : utcNow.getUTCDay();
    return {hour, weekday};
  }
}

/**
 * Helper: split array into chunks of `size`.
 */
function chunk<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

/**
 * Helper: process an array with limited concurrency.
 */
async function mapConcurrent<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];
  const batches = chunk(items, concurrency);
  for (const batch of batches) {
    const batchResults = await Promise.all(batch.map(fn));
    results.push(...batchResults);
  }
  return results;
}

/**
 * Process reminders for a single school.
 *
 * Flow:
 *  1. Determine local hour/weekday from school timezone.
 *  2. Fetch parents with tokens — filter eligible in memory.
 *  3. Gather student IDs from eligible parents' linkedChildren (no full students read).
 *  4. Check which of those students logged today (batched `in` queries).
 *  5. Build ONE message per parent listing all un-logged children.
 *  6. Send via sendEach in 500-msg chunks.
 *  7. Clean up stale tokens.
 */
async function processSchool(
  schoolId: string,
  schoolData: FirebaseFirestore.DocumentData,
  utcNow: Date,
): Promise<{sent: number; failed: number; stale: number}> {
  const schoolTz = schoolData.timezone || "Europe/London";
  const {hour: localHour, weekday: localWeekday} = getLocalTime(utcNow, schoolTz);

  // Quiet hours check
  const qh = schoolData.quietHours;
  if (qh?.enabled && (localHour >= qh.start || localHour < qh.end)) {
    return {sent: 0, failed: 0, stale: 0};
  }

  // ---- Step 1: Fetch parents who have a token ----
  const parentsSnap = await db
    .collection(`schools/${schoolId}/parents`)
    .where("fcmToken", "!=", null)
    .get();

  if (parentsSnap.empty) return {sent: 0, failed: 0, stale: 0};

  // ---- Step 2: Filter eligible parents in memory ----
  // Also collect ALL student IDs we need to check (from linkedChildren)
  interface EligibleParent {
    id: string;
    token: string;
    linkedChildren: string[]; // student IDs
  }

  const eligible: EligibleParent[] = [];
  const allStudentIds = new Set<string>();

  for (const pDoc of parentsSnap.docs) {
    const p = pDoc.data();
    if (!p.fcmToken) continue;
    if (p.preferences?.notificationsEnabled === false) continue;

    // Hour check (default 18 / 6 PM)
    let prefHour = 18;
    if (p.preferences?.reminderTime) {
      const parts = (p.preferences.reminderTime as string).split(":");
      prefHour = parseInt(parts[0], 10) || 18;
    }
    if (prefHour !== localHour) continue;

    // Day-of-week check (empty = every day)
    const days: number[] = p.preferences?.reminderDays ?? [];
    if (days.length > 0 && !days.includes(localWeekday)) continue;

    const children: string[] = p.linkedChildren ?? [];
    if (children.length === 0) continue;

    eligible.push({id: pDoc.id, token: p.fcmToken, linkedChildren: children});
    children.forEach((c) => allStudentIds.add(c));
  }

  if (eligible.length === 0) return {sent: 0, failed: 0, stale: 0};

  // ---- Step 3: Check which students logged today ----
  // Use batched `in` queries on readingLogs (max 30 per query)
  const today = new Date(utcNow);
  today.setHours(0, 0, 0, 0);
  const todayTs = admin.firestore.Timestamp.fromDate(today);

  const tomorrow = new Date(today);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowTs = admin.firestore.Timestamp.fromDate(tomorrow);

  const loggedToday = new Set<string>();
  const studentIdBatches = chunk([...allStudentIds], FIRESTORE_IN_LIMIT);

  await Promise.all(studentIdBatches.map(async (batch) => {
    const snap = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "in", batch)
      .where("date", ">=", todayTs)
      .where("date", "<", tomorrowTs)
      .select("studentId")
      .get();
    snap.docs.forEach((d) => loggedToday.add(d.data().studentId as string));
  }));

  // ---- Step 4: Fetch student first names for un-logged children ----
  // Only read student docs we actually need (children not yet logged)
  const unloggedIds = [...allStudentIds].filter((id) => !loggedToday.has(id));
  if (unloggedIds.length === 0) return {sent: 0, failed: 0, stale: 0};

  const studentNames = new Map<string, string>();
  const nameBatches = chunk(unloggedIds, FIRESTORE_IN_LIMIT);

  await Promise.all(nameBatches.map(async (batch) => {
    // getAll is more efficient than individual reads
    const refs = batch.map((id) => db.doc(`schools/${schoolId}/students/${id}`));
    const docs = await db.getAll(...refs);
    docs.forEach((d) => {
      if (d.exists) {
        studentNames.set(d.id, d.data()?.firstName ?? "your child");
      }
    });
  }));

  // ---- Step 5: Build ONE message per parent ----
  const messages: admin.messaging.TokenMessage[] = [];
  const msgParentIds: string[] = [];

  for (const parent of eligible) {
    const unloggedChildren = parent.linkedChildren
      .filter((id) => !loggedToday.has(id))
      .map((id) => studentNames.get(id))
      .filter((name): name is string => !!name);

    if (unloggedChildren.length === 0) continue;

    // Build a human-readable body
    let body: string;
    if (unloggedChildren.length === 1) {
      body = `Don't forget to log ${unloggedChildren[0]}'s reading today!`;
    } else if (unloggedChildren.length === 2) {
      body = `Don't forget to log ${unloggedChildren[0]} and ${unloggedChildren[1]}'s reading today!`;
    } else {
      const last = unloggedChildren.pop();
      body = `Don't forget to log ${unloggedChildren.join(", ")} and ${last}'s reading today!`;
    }

    messages.push({
      token: parent.token,
      notification: {
        title: "Time to read with Lumi! 📚",
        body,
      },
      data: {
        type: "reading_reminder",
        schoolId,
      },
      apns: {payload: {aps: {sound: "default"}}},
      android: {
        priority: "high" as const,
        notification: {sound: "default", clickAction: "FLUTTER_NOTIFICATION_CLICK"},
      },
    });
    msgParentIds.push(parent.id);
  }

  if (messages.length === 0) return {sent: 0, failed: 0, stale: 0};

  // ---- Step 6: Send in 500-message chunks ----
  let totalSent = 0;
  let totalFailed = 0;
  const staleParentIds = new Set<string>();

  const msgChunks = chunk(messages, FCM_BATCH_LIMIT);
  const idChunks = chunk(msgParentIds, FCM_BATCH_LIMIT);

  for (let i = 0; i < msgChunks.length; i++) {
    const results = await admin.messaging().sendEach(msgChunks[i]);
    totalSent += results.successCount;
    totalFailed += results.failureCount;

    results.responses.forEach((resp, idx) => {
      if (!resp.success && resp.error) {
        const code = resp.error.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          staleParentIds.add(idChunks[i][idx]);
        }
      }
    });
  }

  // ---- Step 7: Clean up stale tokens ----
  if (staleParentIds.size > 0) {
    const staleBatches = chunk([...staleParentIds], 500); // Firestore batch limit
    for (const batch of staleBatches) {
      const writeBatch = db.batch();
      for (const pid of batch) {
        writeBatch.update(db.doc(`schools/${schoolId}/parents/${pid}`), {
          fcmToken: admin.firestore.FieldValue.delete(),
          fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
        });
      }
      await writeBatch.commit();
    }
  }

  return {sent: totalSent, failed: totalFailed, stale: staleParentIds.size};
}

/**
 * Send reading reminder notifications to parents.
 *
 * Runs every hour. Uses school timezone to match each parent's preferred
 * reminder hour and day-of-week. One notification per parent (not per child).
 * Processes schools with bounded concurrency and sends FCM in 500-msg chunks.
 *
 * Firestore reads per school ≈ parents(with token) + unlogged_students + log_checks
 * (NOT all students × all logs like the naive approach)
 */
export const sendReadingReminders = functions
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .pubsub.schedule("0 * * * *") // Every hour on the hour
  .timeZone("UTC")
  .onRun(async () => {
    const utcNow = new Date();
    functions.logger.info("sendReadingReminders tick", {utcHour: utcNow.getUTCHours()});

    try {
      const schoolsSnap = await db.collection("schools").get();

      const results = await mapConcurrent(
        schoolsSnap.docs,
        SCHOOL_CONCURRENCY,
        (doc) => processSchool(doc.id, doc.data(), utcNow),
      );

      const totals = results.reduce(
        (acc, r) => ({sent: acc.sent + r.sent, failed: acc.failed + r.failed, stale: acc.stale + r.stale}),
        {sent: 0, failed: 0, stale: 0},
      );

      functions.logger.info("sendReadingReminders complete", {
        schools: schoolsSnap.size,
        ...totals,
      });

      return null;
    } catch (error) {
      functions.logger.error("Error in sendReadingReminders", {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  });

/**
 * Achievement Detector
 * Triggers when student stats are updated to check for new achievements
 */
export const detectAchievements = functions.firestore
  .document("schools/{schoolId}/students/{studentId}")
  .onUpdate(async (change, context) => {
    const schoolId = context.params.schoolId;
    const studentId = context.params.studentId;
    const newData = change.after.data();
    const oldData = change.before.data();

    const newStats = newData.stats || {};
    const oldStats = oldData.stats || {};

    const achievements: Array<{id: string; name: string; description: string; icon: string}> = [];

    // Check for streak achievements
    if (newStats.currentStreak >= 7 && oldStats.currentStreak < 7) {
      achievements.push({
        id: "week_streak",
        name: "Week Warrior",
        description: "Read for 7 days in a row!",
        icon: "🔥",
      });
    }

    if (newStats.currentStreak >= 30 && oldStats.currentStreak < 30) {
      achievements.push({
        id: "month_streak",
        name: "Monthly Master",
        description: "Read for 30 days in a row!",
        icon: "🌟",
      });
    }

    // Check for book milestones
    if (newStats.totalBooksRead >= 10 && oldStats.totalBooksRead < 10) {
      achievements.push({
        id: "ten_books",
        name: "Book Collector",
        description: "Read 10 books!",
        icon: "📚",
      });
    }

    if (newStats.totalBooksRead >= 50 && oldStats.totalBooksRead < 50) {
      achievements.push({
        id: "fifty_books",
        name: "Bookworm",
        description: "Read 50 books!",
        icon: "🐛",
      });
    }

    // Check for time milestones
    if (newStats.totalMinutesRead >= 600 && oldStats.totalMinutesRead < 600) {
      achievements.push({
        id: "ten_hours",
        name: "Time Traveler",
        description: "Read for 10 hours total!",
        icon: "⏰",
      });
    }

    if (achievements.length > 0) {
      // Save achievements to student document
      const existingAchievements = newData.achievements || [];
      const newAchievements = [
        ...existingAchievements,
        ...achievements.map((a) => ({
          ...a,
          earnedAt: admin.firestore.FieldValue.serverTimestamp(),
        })),
      ];

      await change.after.ref.update({
        achievements: newAchievements,
      });

      // Notify parents
      if (newData.parentIds?.length > 0) {
        for (const parentId of newData.parentIds) {
          const parentDoc = await db
            .doc(`schools/${schoolId}/parents/${parentId}`)
            .get();

          const parentData = parentDoc.data();
          if (parentData?.fcmToken) {
            const achievementNames = achievements.map((a) => a.name).join(", ");
            const message = {
              token: parentData.fcmToken,
              notification: {
                title: `${newData.firstName} earned new achievements! 🎉`,
                body: achievementNames,
              },
              data: {
                type: "achievement_earned",
                studentId: studentId,
                schoolId: schoolId,
                achievements: JSON.stringify(achievements),
              },
            };

            try {
              await admin.messaging().send(message);
              functions.logger.info("Achievement notification sent", {parentId, studentId, achievements});
            } catch (error) {
              functions.logger.error("Failed to send achievement notification", {
                parentId,
                error: error instanceof Error ? error.message : String(error),
              });
            }
          }
        }
      }
    }

    return null;
  });

/**
 * Validate Reading Log
 * Server-side validation before allowing log creation
 */
export const validateReadingLog = functions.firestore
  .document("schools/{schoolId}/readingLogs/{logId}")
  .onCreate(async (snapshot, context) => {
    const schoolId = context.params.schoolId;
    const logData = snapshot.data();

    // Validation rules
    const validationErrors: string[] = [];

    // Validate minutes read (reasonable limits)
    if (logData.minutesRead < 1 || logData.minutesRead > 240) {
      validationErrors.push("Minutes read must be between 1 and 240");
    }

    // Validate student exists
    const studentDoc = await db
      .doc(`schools/${schoolId}/students/${logData.studentId}`)
      .get();

    if (!studentDoc.exists) {
      validationErrors.push("Student does not exist");
    }

    // Validate parent has permission
    const studentData = studentDoc.data();
    if (studentData && !studentData.parentIds?.includes(logData.parentId)) {
      validationErrors.push("Parent not linked to this student");
    }

    // If validation fails, mark the log as invalid
    if (validationErrors.length > 0) {
      await snapshot.ref.update({
        validationStatus: "invalid",
        validationErrors: validationErrors,
      });

      functions.logger.warn("Invalid reading log detected", {
        logId: context.params.logId,
        errors: validationErrors,
      });
    } else {
      await snapshot.ref.update({
        validationStatus: "valid",
        validatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return null;
  });

/**
 * Clean up expired link codes
 * Runs daily to remove old codes
 */
export const cleanupExpiredLinkCodes = functions.pubsub
  .schedule("0 2 * * *") // 2 AM daily
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();

    try {
      const expiredCodesSnapshot = await db
        .collection("studentLinkCodes")
        .where("expiresAt", "<", now)
        .where("status", "==", "active")
        .get();

      const batch = db.batch();
      let count = 0;

      expiredCodesSnapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: "expired",
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
      });

      if (count > 0) {
        await batch.commit();
        functions.logger.info(`Expired ${count} link codes`);
      }

      return null;
    } catch (error) {
      functions.logger.error("Error cleaning up expired codes", {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  });

/**
 * Update class statistics when allocations or logs change
 */
export const updateClassStats = functions.firestore
  .document("schools/{schoolId}/readingLogs/{logId}")
  .onWrite(async (change, context) => {
    const schoolId = context.params.schoolId;
    const log = change.after.exists ? change.after.data() : null;

    if (!log) return null;

    const studentDoc = await db
      .doc(`schools/${schoolId}/students/${log.studentId}`)
      .get();

    const studentData = studentDoc.data();
    if (!studentData?.classId) return null;

    const classId = studentData.classId;

    // Aggregate class stats
    const classLogsSnapshot = await db
      .collection(`schools/${schoolId}/readingLogs`)
      .where("studentId", "in", studentData.classId)
      .get();

    let totalMinutes = 0;
    let totalBooks = 0;
    const uniqueStudents = new Set();

    classLogsSnapshot.docs.forEach((doc) => {
      const logData = doc.data();
      totalMinutes += logData.minutesRead || 0;
      totalBooks += logData.bookTitles?.length || 0;
      uniqueStudents.add(logData.studentId);
    });

    await db.doc(`schools/${schoolId}/classes/${classId}`).update({
      "stats.totalMinutesRead": totalMinutes,
      "stats.totalBooksRead": totalBooks,
      "stats.activeStudents": uniqueStudents.size,
      "stats.lastUpdated": admin.firestore.FieldValue.serverTimestamp(),
    });

    return null;
  });
