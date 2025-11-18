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

/**
 * Send reading reminder notifications to parents
 * Scheduled to run daily at configurable times
 */
export const sendReadingReminders = functions.pubsub
  .schedule("0 18 * * *") // 6 PM daily
  .timeZone("America/New_York") // Configurable per school
  .onRun(async (context) => {
    functions.logger.info("Starting daily reading reminders");

    try {
      // Get all schools to check their quiet hours
      const schoolsSnapshot = await db.collection("schools").get();

      for (const schoolDoc of schoolsSnapshot.docs) {
        const schoolId = schoolDoc.id;
        const schoolData = schoolDoc.data();
        const quietHours = schoolData.quietHours;

        // Skip if in quiet hours
        if (quietHours?.enabled) {
          const now = new Date();
          const currentHour = now.getHours();
          if (currentHour >= quietHours.start || currentHour < quietHours.end) {
            functions.logger.info(`Skipping ${schoolId} - quiet hours active`);
            continue;
          }
        }

        // Get students who haven't logged reading today
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const todayTimestamp = admin.firestore.Timestamp.fromDate(today);

        const studentsSnapshot = await db
          .collection(`schools/${schoolId}/students`)
          .get();

        for (const studentDoc of studentsSnapshot.docs) {
          const studentId = studentDoc.id;
          const studentData = studentDoc.data();

          // Check if student has logged today
          const todayLogsSnapshot = await db
            .collection(`schools/${schoolId}/readingLogs`)
            .where("studentId", "==", studentId)
            .where("date", ">=", todayTimestamp)
            .limit(1)
            .get();

          if (todayLogsSnapshot.empty && studentData.parentIds?.length > 0) {
            // Send notification to all linked parents
            for (const parentId of studentData.parentIds) {
              const parentDoc = await db
                .doc(`schools/${schoolId}/parents/${parentId}`)
                .get();

              const parentData = parentDoc.data();
              if (parentData?.fcmToken) {
                const message = {
                  token: parentData.fcmToken,
                  notification: {
                    title: "Time to read with Lumi! 📚",
                    body: `Don't forget to log ${studentData.firstName}'s reading today!`,
                  },
                  data: {
                    type: "reading_reminder",
                    studentId: studentId,
                    schoolId: schoolId,
                  },
                  apns: {
                    payload: {
                      aps: {
                        sound: "default",
                      },
                    },
                  },
                  android: {
                    priority: "high" as const,
                    notification: {
                      sound: "default",
                      clickAction: "FLUTTER_NOTIFICATION_CLICK",
                    },
                  },
                };

                try {
                  await admin.messaging().send(message);
                  functions.logger.info("Reminder sent", {parentId, studentId});
                } catch (error) {
                  functions.logger.error("Failed to send reminder", {
                    parentId,
                    error: error instanceof Error ? error.message : String(error),
                  });
                }
              }
            }
          }
        }
      }

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
        .where("expiryDate", "<", now)
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
