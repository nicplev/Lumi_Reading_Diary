import * as functions from "firebase-functions/v1";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import {randomBytes} from "crypto";
import sgMail from "@sendgrid/mail";
import {buildDemoAccessEmail} from "./email_templates";
import {lumiMascotAttachment} from "./email_assets";
import {DEFAULT_TIMEZONE} from "./access";
import {recordCronRun} from "./ops_heartbeat";
import {errorCodeForLog} from "./log_safety";

// Demo-day rolling-access backend. Two functions live here:
//   • processDemoAccessEmail — Firestore-trigger that emails a prospect the
//     day's demo credentials (mirrors processStaffOnboardingEmail in index.ts).
//   • scrambleDemoPasswords — nightly cron that unconditionally rotates every
//     demo account's password to an unstored random string, so a demo-day
//     password only works its own calendar day (Sydney time).
// The portal issues the day password (server-ops provisionDemoAccess) into
// demoAccess/state; both functions here only READ that state. See
// docs/DEMO_DAY_ACCESS_PLAN.md.

const sendgridApiKey = defineSecret("SENDGRID_API_KEY");
const sendgridSenderEmail = defineSecret("SENDGRID_SENDER_EMAIL");

// Permanent demo tenant seeded by scripts/seed_demo_school.js. The live values
// are read from platformConfig/demoAccess so store URLs can be filled in later
// without a functions deploy; these are the fail-safe defaults.
const DEMO_SCHOOL_ID = "lumi_demo_primary_school";
// Every demo-access email BCCs this inbox as an exact-content paper-trail backup.
const PAPER_TRAIL_ADDRESS = "support@lumi-reading.com";

interface DemoAccessConfig {
  schoolId: string;
  adminEmail: string;
  teacherEmail: string;
  parentEmail: string;
  scrambleOnlyEmails: string[];
  portalLoginUrl: string;
  marketingUrl: string;
  appStoreUrl: string | null;
  playStoreUrl: string | null;
}

const DEFAULT_CONFIG: DemoAccessConfig = {
  schoolId: DEMO_SCHOOL_ID,
  adminEmail: "support+demo@lumi-reading.com",
  teacherEmail: "support+demo.teacher@lumi-reading.com",
  parentEmail: "support+demo.parent@lumi-reading.com",
  scrambleOnlyEmails: [
    "demo.admin@lumidemo.school",
    "demo.teacher2@lumidemo.school",
    "demo.parent2@lumidemo.school",
  ],
  portalLoginUrl: "https://lumi-school-admin-au.web.app/login",
  marketingUrl: "https://lumi-reading.com",
  appStoreUrl: null,
  playStoreUrl: null,
};

/**
 * The Sydney calendar day of an instant as "YYYY-MM-DD". This is the canonical
 * dayKey the whole demo-access feature keys on (issued/scrambled/valid-today).
 * @param {Date} d The instant.
 * @param {string} tz The IANA timezone (defaults to Australia/Sydney).
 * @return {string} The local calendar day, "YYYY-MM-DD".
 */
export function sydneyDayKey(d: Date, tz: string = DEFAULT_TIMEZONE): string {
  try {
    // en-CA renders as YYYY-MM-DD.
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: tz,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(d);
  } catch {
    return d.toISOString().slice(0, 10);
  }
}

/**
 * A human date label for the email subject/body, e.g. "Friday 11 Jul", in the
 * given timezone.
 * @param {Date} d The instant.
 * @param {string} tz The IANA timezone (defaults to Australia/Sydney).
 * @return {string} The formatted label.
 */
export function sydneyDateLabel(d: Date, tz: string = DEFAULT_TIMEZONE): string {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: tz,
      weekday: "long",
      day: "numeric",
      month: "short",
    }).formatToParts(d);
    const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
    return `${get("weekday")} ${get("day")} ${get("month")}`.trim();
  } catch {
    return sydneyDayKey(d, tz);
  }
}

/**
 * Read platformConfig/demoAccess, falling back field-by-field to the built-in
 * defaults so a missing/partial doc can never disable the nightly scramble.
 * @param {FirebaseFirestore.Firestore} db The Firestore instance.
 * @return {Promise<DemoAccessConfig>} The resolved config.
 */
async function readDemoConfig(
  db: FirebaseFirestore.Firestore,
): Promise<DemoAccessConfig> {
  try {
    const snap = await db.doc("platformConfig/demoAccess").get();
    if (!snap.exists) return DEFAULT_CONFIG;
    const d = snap.data() ?? {};
    const str = (v: unknown, fb: string) =>
      typeof v === "string" && v.trim().length > 0 ? v.trim() : fb;
    const url = (v: unknown) =>
      typeof v === "string" && v.trim().length > 0 ? v.trim() : null;
    return {
      schoolId: str(d.schoolId, DEFAULT_CONFIG.schoolId),
      adminEmail: str(d.adminEmail, DEFAULT_CONFIG.adminEmail),
      teacherEmail: str(d.teacherEmail, DEFAULT_CONFIG.teacherEmail),
      parentEmail: str(d.parentEmail, DEFAULT_CONFIG.parentEmail),
      scrambleOnlyEmails: Array.isArray(d.scrambleOnlyEmails) ?
        (d.scrambleOnlyEmails as unknown[]).filter(
          (e): e is string => typeof e === "string" && e.length > 0,
        ) :
        DEFAULT_CONFIG.scrambleOnlyEmails,
      portalLoginUrl: str(d.portalLoginUrl, DEFAULT_CONFIG.portalLoginUrl),
      marketingUrl: str(d.marketingUrl, DEFAULT_CONFIG.marketingUrl),
      appStoreUrl: url(d.appStoreUrl),
      playStoreUrl: url(d.playStoreUrl),
    };
  } catch (err) {
    functions.logger.error("readDemoConfig failed; using defaults", {
      errorCode: errorCodeForLog(err),
    });
    return DEFAULT_CONFIG;
  }
}

/**
 * Resolve an email to its Auth uid, but ONLY if that uid actually belongs to
 * the demo school (a users/ OR parents/ doc under it). Returns null otherwise —
 * we never touch an account we can't prove is part of the demo tenant. This is
 * the "resolve from config, never rotate by query" safety rule.
 * @param {FirebaseFirestore.Firestore} db The Firestore instance.
 * @param {string} schoolId The demo school id.
 * @param {string} email The account email.
 * @return {Promise<string | null>} The verified uid, or null.
 */
async function resolveDemoUid(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  email: string,
): Promise<string | null> {
  let uid: string;
  try {
    const user = await admin.auth().getUserByEmail(email);
    uid = user.uid;
  } catch {
    return null;
  }
  const [userDoc, parentDoc] = await Promise.all([
    db.doc(`schools/${schoolId}/users/${uid}`).get(),
    db.doc(`schools/${schoolId}/parents/${uid}`).get(),
  ]);
  return userDoc.exists || parentDoc.exists ? uid : null;
}

/**
 * A throwaway password: 40 random bytes, never stored anywhere. Only has to be
 * un-guessable so the account is unusable until the next Provision reissues the
 * day password.
 * @return {string} A random password string.
 */
function randomThrowawayPassword(): string {
  return randomBytes(40).toString("base64url");
}

// ── Nightly scramble ────────────────────────────────────────────────────────

/**
 * Unconditionally rotate every demo account's password to an unstored random
 * string just after Sydney midnight, so yesterday's shared password stops
 * working. Idempotent, state-free, and permanently neutralises the hardcoded
 * seed password. Never throws on a single-account failure.
 */
export const scrambleDemoPasswords = onSchedule(
  {
    schedule: "5 0 * * *", // 00:05 gives a small grace past midnight
    timeZone: DEFAULT_TIMEZONE, // Australia/Sydney
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const config = await readDemoConfig(db);

    const emails = [
      config.adminEmail,
      config.teacherEmail,
      config.parentEmail,
      ...config.scrambleOnlyEmails,
    ].filter((e, i, arr) => e.length > 0 && arr.indexOf(e) === i);

    let scrambled = 0;
    const failures: {email: string; reason: string}[] = [];
    for (const email of emails) {
      try {
        const uid = await resolveDemoUid(db, config.schoolId, email);
        if (!uid) {
          failures.push({email, reason: "not_a_demo_school_member"});
          continue;
        }
        await admin.auth().updateUser(uid, {
          password: randomThrowawayPassword(),
        });
        await admin.auth().revokeRefreshTokens(uid);
        scrambled++;
      } catch (err) {
        failures.push({
          email,
          reason: err instanceof Error ? err.message : String(err),
        });
      }
    }

    // Stamp the state so a same-day Email attempt now refuses as stale. Best
    // effort — the scramble itself is the real enforcement.
    try {
      const stateRef = db.doc("demoAccess/state");
      const stateSnap = await stateRef.get();
      if (stateSnap.exists) {
        await stateRef.set(
          {scrambledAt: admin.firestore.FieldValue.serverTimestamp()},
          {merge: true},
        );
      }
    } catch (err) {
      functions.logger.error("scrambleDemoPasswords: state stamp failed", {
        errorCode: errorCodeForLog(err),
      });
    }

    functions.logger.info("scrambleDemoPasswords complete", {
      scrambled,
      failed: failures.length,
      failures,
    });
    await recordCronRun(
      "scrambleDemoPasswords",
      "ok",
      failures.length > 0 ? `${failures.length} account(s) failed` : undefined,
    );
  },
);

// ── Email delivery ───────────────────────────────────────────────────────────

/**
 * Send a prospect the day's demo credentials. Reads the live demoAccess/state
 * and REFUSES to send if the password is not for today or has been scrambled,
 * so it is impossible to email a stale password. The queue doc is the permanent
 * paper-trail record (never deleted) — this writes the final status back to it.
 */
export const processDemoAccessEmail = onDocumentCreated(
  {
    document: "demoAccessEmails/{emailId}",
    concurrency: 1,
    timeoutSeconds: 120,
    memory: "256MiB",
    secrets: [sendgridApiKey, sendgridSenderEmail],
  },
  async (event) => {
    if (!event.data) return;
    const data = event.data.data();
    if (data.status !== "queued") return;

    const docRef = event.data.ref;
    const db = admin.firestore();
    const now = new Date();
    const todayKey = sydneyDayKey(now);

    // Claim the document.
    await docRef.update({status: "processing"});

    const recipient: string | null =
      typeof data.to === "string" && data.to.length > 0 ? data.to : null;
    const onboardingId: string | null =
      typeof data.onboardingId === "string" ? data.onboardingId : null;

    const markFailed = async (reason: string) => {
      functions.logger.error("processDemoAccessEmail failed");
      await docRef.update({
        status: "failed",
        error: reason,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        await db.doc("demoAccess/state").set(
          {
            lastEmail: {
              to: recipient,
              onboardingId,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
              status: "failed",
            },
          },
          {merge: true},
        );
      } catch {
        // state mirror is best-effort
      }
    };

    try {
      const sendgridKey = sendgridApiKey.value();
      if (!sendgridKey) {
        await markFailed("SendGrid API key not configured");
        return;
      }
      if (!recipient) {
        await markFailed("No recipient email on the queue doc");
        return;
      }

      // Freshness gate: read the live state and never email a stale/scrambled
      // password.
      const stateSnap = await db.doc("demoAccess/state").get();
      const state = stateSnap.data();
      if (!stateSnap.exists || !state) {
        await markFailed("No demo password has been issued — provision first");
        return;
      }
      if (state.dayKey !== todayKey) {
        await markFailed(
          `Demo password is for ${state.dayKey}, not today (${todayKey})`,
        );
        return;
      }
      if (state.scrambledAt != null) {
        await markFailed("Demo password has already been scrambled");
        return;
      }
      const password: string =
        typeof state.password === "string" ? state.password : "";
      if (!password) {
        await markFailed("Demo state has no password");
        return;
      }

      const config = await readDemoConfig(db);
      const dateLabel = sydneyDateLabel(now);
      const subject = `Your Lumi demo access for ${dateLabel}`;

      const html = buildDemoAccessEmail({
        contactPerson:
          typeof data.contactPerson === "string" ? data.contactPerson : "",
        schoolName: typeof data.schoolName === "string" ? data.schoolName : "",
        dateLabel,
        password,
        adminEmail: config.adminEmail,
        teacherEmail: config.teacherEmail,
        parentEmail: config.parentEmail,
        portalLoginUrl: config.portalLoginUrl,
        marketingUrl: config.marketingUrl,
        appStoreUrl: config.appStoreUrl,
        playStoreUrl: config.playStoreUrl,
      });

      sgMail.setApiKey(sendgridKey);
      const senderEmail =
        sendgridSenderEmail.value() || "noreply@lumi-reading.app";

      await sgMail.send({
        to: recipient,
        from: {email: senderEmail, name: "Lumi"},
        replyTo: PAPER_TRAIL_ADDRESS,
        bcc: PAPER_TRAIL_ADDRESS,
        subject,
        html,
        attachments: [lumiMascotAttachment()],
      });

      await docRef.update({
        status: "sent",
        subject,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await db.doc("demoAccess/state").set(
        {
          lastEmail: {
            to: recipient,
            onboardingId,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            status: "sent",
          },
        },
        {merge: true},
      );
    } catch (err) {
      await markFailed(err instanceof Error ? err.message : String(err));
    }
  },
);
