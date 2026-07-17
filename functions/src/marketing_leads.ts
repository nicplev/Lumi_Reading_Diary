import {onCall, CallableOptions, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import sgMail from "@sendgrid/mail";
import {errorCodeForLog} from "./log_safety";

const sendgridApiKey = defineSecret("SENDGRID_API_KEY");
const sendgridSenderEmail = defineSecret("SENDGRID_SENDER_EMAIL");

// App Check enforcement, opt-in via env var. Default off until the marketing
// site's web app is registered with App Check (reCAPTCHA) and verified.
// Flip via MARKETING_LEADS_APP_CHECK_ENFORCED=true once that's done — these
// callables are the first genuinely public-internet-facing surface hitting
// this project, so App Check matters more here than on authenticated paths.
const APP_CHECK_ENFORCED =
  process.env.MARKETING_LEADS_APP_CHECK_ENFORCED === "true";

function marketingRuntime(
  opts: Pick<CallableOptions, "timeoutSeconds" | "memory">
): CallableOptions {
  return {
    ...opts,
    enforceAppCheck: APP_CHECK_ENFORCED,
    consumeAppCheckToken: APP_CHECK_ENFORCED,
  };
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RATE_WINDOW_MS = 60 * 60 * 1000;
const RATE_COLLECTION = "marketingLeadRateLimits";

function limitedString(
  raw: unknown,
  field: string,
  maxLength: number,
  required = false
): string {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (required && !value) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  if (value.length > maxLength) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be ${maxLength} characters or fewer.`
    );
  }
  return value;
}

function rateKey(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

async function enforceMarketingRateLimit(
  kind: "demo" | "contact",
  request: {rawRequest: {ip?: string}},
  email: string
): Promise<void> {
  const ip = request.rawRequest.ip || "unknown";
  const limits = kind === "demo" ? {ip: 8, email: 3} : {ip: 5, email: 3};
  const db = admin.firestore();
  const refs = [
    {
      ref: db.collection(RATE_COLLECTION).doc(rateKey(`${kind}:ip:${ip}`)),
      limit: limits.ip,
    },
    {
      ref: db.collection(RATE_COLLECTION).doc(
        rateKey(`${kind}:email:${email.toLowerCase()}`)
      ),
      limit: limits.email,
    },
  ];

  await db.runTransaction(async (tx) => {
    const snapshots = [];
    for (const entry of refs) snapshots.push(await tx.get(entry.ref));
    const now = admin.firestore.Timestamp.now();

    for (let i = 0; i < refs.length; i++) {
      const data = snapshots[i].data() ?? {};
      const startedAt = data.windowStartedAt as
        | admin.firestore.Timestamp
        | undefined;
      const inWindow = startedAt ?
        now.toMillis() - startedAt.toMillis() < RATE_WINDOW_MS :
        false;
      const count = inWindow && typeof data.count === "number" ?
        data.count :
        0;
      if (count >= refs[i].limit) {
        throw new HttpsError(
          "resource-exhausted",
          "Too many requests. Please try again later."
        );
      }
      tx.set(refs[i].ref, {
        kind,
        count: count + 1,
        windowStartedAt: inWindow && startedAt ? startedAt : now,
        updatedAt: now,
        expiresAt: admin.firestore.Timestamp.fromMillis(
          now.toMillis() + RATE_WINDOW_MS * 2
        ),
      });
    }
  });
}

function escapeHtml(s: string): string {
  const map: Record<string, string> = {
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;",
  };
  return s.replace(/[&<>"']/g, (c) => map[c]);
}

// ─────────────────────────────────────────────────────────────────────────────
// submitDemoRequest — marketing-site "Book a Demo" form. Mirrors
// createOnboardingRequest() in admin/src/lib/firestore/onboarding.ts field for
// field, so submissions land in the exact same super-admin Onboarding
// Pipeline as the Flutter app's existing demo-request screen. Fields with no
// column in that pipeline (region/role/preferredTime/intent) are packed into
// metadata.notes, which the pipeline's Follow-up panel already renders.
// ─────────────────────────────────────────────────────────────────────────────

interface DemoRequestInput {
  schoolName: string;
  contactPerson: string;
  contactEmail: string;
  region?: string;
  role?: string;
  preferredTime?: string;
  intent: "demo" | "info";
  message?: string;
  contactPhone?: string;
  referralSource?: string;
  estimatedStudentCount?: number;
  estimatedTeacherCount?: number;
}

export const submitDemoRequest = onCall(
  marketingRuntime({timeoutSeconds: 30, memory: "256MiB"}),
  async (request) => {
    const data = (request.data ?? {}) as Partial<DemoRequestInput>;

    const schoolName = limitedString(data.schoolName, "School name", 160, true);
    const contactPerson = limitedString(data.contactPerson, "Your name", 100, true);
    const contactEmail = limitedString(data.contactEmail, "Email", 254, true);
    if (!contactEmail || !EMAIL_RE.test(contactEmail)) {
      throw new HttpsError("invalid-argument", "A valid email is required.");
    }
    if (data.intent !== "demo" && data.intent !== "info") {
      throw new HttpsError("invalid-argument", "A valid request type is required.");
    }
    const region = limitedString(data.region, "State", 32);
    const role = limitedString(data.role, "Role", 80);
    const preferredTime = limitedString(
      data.preferredTime,
      "Preferred time",
      80
    );
    const message = limitedString(data.message, "Message", 2000);
    const contactPhone = limitedString(data.contactPhone, "Phone", 40);
    const referralSource = limitedString(
      data.referralSource,
      "Referral source",
      100
    );
    const estimatedStudentCount = Number.isInteger(data.estimatedStudentCount) &&
      (data.estimatedStudentCount as number) >= 0 &&
      (data.estimatedStudentCount as number) <= 100000 ?
      data.estimatedStudentCount as number : 0;
    const estimatedTeacherCount = Number.isInteger(data.estimatedTeacherCount) &&
      (data.estimatedTeacherCount as number) >= 0 &&
      (data.estimatedTeacherCount as number) <= 10000 ?
      data.estimatedTeacherCount as number : 0;
    await enforceMarketingRateLimit("demo", request, contactEmail);

    const notesParts: string[] = [];
    notesParts.push(
      `Intent: ${data.intent === "info" ? "Info pack request" : "Live demo request"}`
    );
    if (region) notesParts.push(`State: ${region}`);
    if (role) notesParts.push(`Role: ${role}`);
    if (preferredTime) notesParts.push(`Preferred time: ${preferredTime}`);
    if (message) notesParts.push(`Message: ${message}`);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const doc: Record<string, unknown> = {
      schoolName,
      contactEmail,
      contactPerson,
      contactPhone: contactPhone ?? null,
      status: "demo",
      currentStep: "schoolInfo",
      completedSteps: [],
      estimatedStudentCount,
      estimatedTeacherCount,
      referralSource: referralSource ?? "Marketing site",
      createdAt: now,
      lastUpdatedAt: now,
      metadata: {notes: notesParts.join("\n")},
    };

    try {
      const ref = await admin.firestore().collection("schoolOnboarding").add(doc);
      return {id: ref.id};
    } catch (err) {
      functions.logger.error("submitDemoRequest: Firestore write failed", {
        errorCode: errorCodeForLog(err),
      });
      throw new HttpsError("internal", "Failed to submit request. Please try again.");
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// submitContactSalesInquiry — marketing-site "Contact Sales" form. Deliberately
// does NOT write to schoolOnboarding (per product decision: this is a plain
// inquiry, not a pipeline lead) — it just emails the sales inbox via the same
// SendGrid pattern already used elsewhere in this file (see index.ts).
// ─────────────────────────────────────────────────────────────────────────────

interface ContactSalesInput {
  name: string;
  email: string;
  school?: string;
  topic?: string;
  message: string;
}

export const submitContactSalesInquiry = onCall(
  {
    ...marketingRuntime({timeoutSeconds: 30, memory: "256MiB"}),
    secrets: [sendgridApiKey, sendgridSenderEmail],
  },
  async (request) => {
    const data = (request.data ?? {}) as Partial<ContactSalesInput>;

    const name = limitedString(data.name, "Your name", 100, true);
    const email = limitedString(data.email, "Email", 254, true);
    const message = limitedString(data.message, "Message", 4000, true);
    if (!email || !EMAIL_RE.test(email)) {
      throw new HttpsError("invalid-argument", "A valid email is required.");
    }
    const school = limitedString(data.school, "School", 160);
    const topic = limitedString(data.topic, "Topic", 100);
    await enforceMarketingRateLimit("contact", request, email);

    const key = sendgridApiKey.value();
    if (!key) {
      functions.logger.error("submitContactSalesInquiry: SENDGRID_API_KEY not configured");
      throw new HttpsError("failed-precondition", "Email is not configured.");
    }
    sgMail.setApiKey(key);
    const senderEmail = sendgridSenderEmail.value() || "noreply@lumi-reading.app";

    const html = [
      "<p><strong>New sales inquiry from the marketing site</strong></p>",
      "<p>",
      `<strong>Name:</strong> ${escapeHtml(name)}<br/>`,
      `<strong>Email:</strong> ${escapeHtml(email)}<br/>`,
      school ? `<strong>School:</strong> ${escapeHtml(school)}<br/>` : "",
      topic ? `<strong>Topic:</strong> ${escapeHtml(topic)}<br/>` : "",
      "</p>",
      `<p>${escapeHtml(message).replace(/\n/g, "<br/>")}</p>`,
    ].join("");

    try {
      await sgMail.send({
        to: "support@lumi-reading.com",
        from: {email: senderEmail, name: "Lumi Marketing Site"},
        replyTo: email,
        subject: `New sales inquiry: ${(school || name).replace(/[\r\n]+/g, " ")}`,
        html,
      });
      return {success: true};
    } catch (err) {
      functions.logger.error("submitContactSalesInquiry: send failed", {
        errorCode: errorCodeForLog(err),
      });
      throw new HttpsError("internal", "Failed to send your message. Please try again or email us directly.");
    }
  }
);
