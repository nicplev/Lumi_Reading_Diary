/* eslint-disable max-len */
import * as QRCode from "qrcode";
import {LUMI_MASCOT_CONTENT_ID} from "./email_assets";

// ─── Lumi email design tokens ─────────────────────────────────────────────
// The New Lumi Design Guide look, hard-coded as hex (email can't use CSS vars).
// Red is the brand anchor; cream canvas; Nunito display + Inter body.
// IMPORTANT: keep this template in sync with its twin
// school-admin-web/src/lib/email-template.ts (used for the in-portal preview).
const FONT_DISPLAY = "'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
const FONT_BODY = "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
const FONT_MONO = "'Courier New', Courier, monospace";

const RED = "#EC4544";
const RED_DARK = "#C5302F";
const RED_GRADIENT = "linear-gradient(135deg, #F2615F 0%, #EC4544 55%, #C5302F 100%)";
const YELLOW = "#FFCB05";
const CREAM = "#F7F5F0";
const PAPER = "#FFFFFF";
const INK = "#1A1A1A";
const INK_SOFT = "#2A2A2A";
const MUTED = "#6B6B6B";
const RULE = "#E5E2DC";
const CARD_TINT = "#FAF6F0";
const NOTE_BG = "#FEF6D8";
const NOTE_LABEL = "#8A6D00";

// Interpolated request fields (contactPerson/schoolName) are attacker-controlled
// via the public marketing form, so escape everything spliced into the HTML.
// Mirrors escapeHtml in marketing_leads.ts.
function escapeHtml(s: string): string {
  const map: Record<string, string> = {
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;",
  };
  return s.replace(/[&<>"']/g, (c) => map[c]);
}

interface OnboardingEmailEntry {
  studentName: string;
  linkCode: string;
}

export interface OnboardingEmailAttachment {
  content: string;
  filename: string;
  type: string;
  disposition: "inline";
  content_id: string;
}

export function onboardingQrContentId(linkCode: string): string {
  return `onboarding-qr-${linkCode}`;
}

export async function buildOnboardingQrAttachments(
  entries: OnboardingEmailEntry[]
): Promise<OnboardingEmailAttachment[]> {
  return Promise.all(
    entries.map(async (entry) => {
      const buffer = await QRCode.toBuffer(entry.linkCode, {
        width: 400,
        margin: 2,
        errorCorrectionLevel: "M",
      });
      return {
        content: buffer.toString("base64"),
        filename: `link-code-${entry.linkCode}.png`,
        type: "image/png",
        disposition: "inline",
        content_id: onboardingQrContentId(entry.linkCode),
      };
    })
  );
}

export function buildOnboardingEmail(params: {
  schoolName: string;
  entries: OnboardingEmailEntry[];
  customMessage?: string;
  appStoreUrl?: string;
  playStoreUrl?: string;
}): string {
  const {
    schoolName,
    entries,
    customMessage,
    appStoreUrl = "#",
    playStoreUrl = "#",
  } = params;

  const entryCards = entries
    .map((entry) =>
      renderEntryCard({
        studentName: entry.studentName,
        linkCode: entry.linkCode,
        qrSrc: `cid:${onboardingQrContentId(entry.linkCode)}`,
      })
    )
    .join("\n");

  return renderEmailShell({
    schoolName,
    customMessage,
    appStoreUrl,
    playStoreUrl,
    entryCards,
    mascotSrc: `cid:${LUMI_MASCOT_CONTENT_ID}`,
  });
}

interface EntryCardParams {
  studentName: string;
  linkCode: string;
  qrSrc: string;
}

export function renderEntryCard(params: EntryCardParams): string {
  const {linkCode, qrSrc} = params;
  // Student names reach us from the school roster — including a bulk SIS/CSV
  // import, where an attacker-supplied file could smuggle markup into a name.
  // This email goes to parents from the school's trusted sender, so an
  // unescaped name would be a ready-made phishing surface. Escaped at the leaf,
  // matching renderSchoolNoteBlock. linkCode/qrSrc are server-generated.
  const studentName = escapeHtml(params.studentName);
  return `
      <tr>
        <td style="padding: 0 24px 20px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CARD_TINT}; background-image: linear-gradient(180deg, ${CARD_TINT} 0%, ${PAPER} 78%); border-radius: 20px; border: 1px solid ${RULE};">
            <tr>
              <td style="padding: 32px 24px;">
                <p style="margin: 0 0 4px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; text-transform: uppercase; letter-spacing: 2px; text-align: center;">
                  Linking code for
                </p>
                <p style="margin: 0 0 24px 0; font-family: ${FONT_DISPLAY}; font-size: 22px; font-weight: 800; color: ${INK}; text-align: center; line-height: 1.2;">
                  ${studentName}
                </p>
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                  <tr>
                    <td style="background-color: ${PAPER}; border: 2px dashed ${RED}; border-radius: 14px; padding: 22px 36px;">
                      <span style="font-family: ${FONT_MONO}; font-size: 32px; font-weight: 700; color: ${RED}; letter-spacing: 6px;">
                        ${linkCode}
                      </span>
                    </td>
                  </tr>
                </table>
                <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top: 28px; margin-bottom: 20px;">
                  <tr>
                    <td style="border-top: 1px solid ${RULE}; line-height: 0; font-size: 0;">&nbsp;</td>
                    <td style="padding: 0 14px; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; letter-spacing: 2px; white-space: nowrap;">
                      OR SCAN
                    </td>
                    <td style="border-top: 1px solid ${RULE}; line-height: 0; font-size: 0;">&nbsp;</td>
                  </tr>
                </table>
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                  <tr>
                    <td style="padding: 14px; background-color: ${PAPER}; border-radius: 16px; border: 1px solid ${RULE};">
                      <img src="${qrSrc}" width="160" height="160" alt="QR code for ${linkCode}" style="display: block; width: 160px; height: 160px;" />
                    </td>
                  </tr>
                </table>
                <p style="margin: 16px 0 0 0; font-family: ${FONT_BODY}; font-size: 13px; color: ${MUTED}; text-align: center; line-height: 1.5;">
                  Open Lumi and point<br />your camera at the code
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>`;
}

interface EmailShellParams {
  schoolName: string;
  customMessage?: string;
  appStoreUrl: string;
  playStoreUrl: string;
  entryCards: string;
  mascotSrc: string;
}

// Optional "A note from your school" block. The message is admin-supplied
// free text, so it is HTML-escaped (like invoice_email) before it lands in an
// email sent from Lumi's address — a school admin must not be able to inject
// links, tracking pixels or spoofed markup into onboarding mail.
export function renderSchoolNoteBlock(customMessage?: string): string {
  if (!customMessage) return "";
  const safe = escapeHtml(customMessage).replace(/\n/g, "<br/>");
  return `
      <tr>
        <td style="padding: 0 24px 24px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${NOTE_BG}; border-radius: 14px;">
            <tr>
              <td style="padding: 18px 22px;">
                <p style="margin: 0 0 6px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${NOTE_LABEL}; text-transform: uppercase; letter-spacing: 2px;">
                  A note from your school
                </p>
                <p style="margin: 0; font-family: ${FONT_BODY}; font-size: 14px; color: ${INK}; line-height: 1.65;">
                  ${safe}
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>`;
}

export function renderEmailShell(params: EmailShellParams): string {
  const {customMessage, appStoreUrl, playStoreUrl, entryCards, mascotSrc} =
    params;
  // School display names are admin-editable, so escape before splicing.
  // entryCards is already-rendered (and escaped) HTML from renderEntryCard.
  const schoolName = escapeHtml(params.schoolName);

  const customMessageBlock = renderSchoolNoteBlock(customMessage);

  return `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <title>Welcome to Lumi Reading Diary</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Nunito:wght@700;800&family=Inter:wght@400;500&display=swap" rel="stylesheet">
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin: 0; padding: 0; background-color: ${CREAM}; -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CREAM};">
    <tr>
      <td align="center" style="padding: 32px 16px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width: 600px; width: 100%; background-color: ${PAPER}; border-radius: 24px; overflow: hidden; box-shadow: 0 8px 24px rgba(26,26,26,0.08);">

          <!-- Hero -->
          <tr>
            <td style="background-color: ${RED}; background-image: ${RED_GRADIENT}; padding: 44px 32px 40px; text-align: center;">
              <img src="${mascotSrc}" width="103" height="100" alt="Lumi" style="display: block; width: 103px; height: 100px; margin: 0 auto 14px;" />
              <h1 style="margin: 0 0 8px 0; font-family: ${FONT_DISPLAY}; font-size: 44px; font-weight: 800; color: ${PAPER}; letter-spacing: 1px; line-height: 1;">
                Lumi
              </h1>
              <p style="margin: 0 0 20px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${PAPER}; text-transform: uppercase; letter-spacing: 4px; opacity: 0.95;">
                Reading Diary
              </p>
              <p style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 15px; color: ${PAPER}; font-weight: 700;">
                ${schoolName}
              </p>
            </td>
          </tr>

          <!-- Welcome + lead -->
          <tr>
            <td style="padding: 40px 40px 8px 40px; text-align: center;">
              <h2 style="margin: 0 0 12px 0; font-family: ${FONT_DISPLAY}; font-size: 26px; font-weight: 800; color: ${INK}; line-height: 1.25;">
                Welcome to Lumi
              </h2>
              <p style="margin: 0; font-family: ${FONT_BODY}; font-size: 15px; color: ${INK_SOFT}; line-height: 1.7;">
                <strong style="color: ${RED};">${schoolName}</strong> uses Lumi as their digital reading diary. You're a few taps from following your child's reading &mdash; download the app and use the code below to connect to their account.
              </p>
            </td>
          </tr>

          ${customMessageBlock}

          <tr><td style="height: 24px; line-height: 24px; font-size: 0;">&nbsp;</td></tr>

          ${entryCards}

          <!-- Section title -->
          <tr>
            <td style="padding: 32px 32px 4px;">
              <h3 style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 22px; font-weight: 800; color: ${INK}; text-align: center;">
                How it works
              </h3>
              <p style="margin: 6px 0 0 0; font-family: ${FONT_BODY}; font-size: 14px; color: ${MUTED}; text-align: center;">
                Four quick steps to get you set up
              </p>
            </td>
          </tr>

          <!-- Steps -->
          <tr>
            <td style="padding: 20px 32px 0;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                ${renderStep(1, "Download the Lumi app", "Available on the App Store and Google Play.")}
                ${renderStep(2, "Enter your link code", "Open Lumi and enter the code above, or scan the QR. It unlocks parent sign-up for your school.")}
                ${renderStep(3, "Create your parent account", "Sign up with your email address to finish setting up.")}
                ${renderStep(4, "Start tracking", "Log books, see streaks, and celebrate every milestone.")}
              </table>
            </td>
          </tr>

          <!-- App buttons -->
          <tr>
            <td style="padding: 36px 32px 16px; text-align: center;">
              <p style="margin: 0 0 16px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; text-transform: uppercase; letter-spacing: 3px;">
                Get the app
              </p>
              <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                <tr>
                  <td style="padding: 4px;">
                    <a href="${appStoreUrl}" target="_blank" style="display: inline-block; background-color: ${INK}; text-decoration: none; padding: 12px 22px; border-radius: 12px;">
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td style="text-align: left; padding-right: 4px;">
                            <span style="display: block; font-family: ${FONT_BODY}; font-size: 10px; font-weight: 500; color: rgba(255,255,255,0.75); letter-spacing: 0.5px; line-height: 1.2;">Download on the</span>
                            <span style="display: block; font-family: ${FONT_DISPLAY}; font-size: 18px; font-weight: 800; color: ${PAPER}; line-height: 1.2; margin-top: 2px;">App Store</span>
                          </td>
                        </tr>
                      </table>
                    </a>
                  </td>
                  <td style="padding: 4px;">
                    <a href="${playStoreUrl}" target="_blank" style="display: inline-block; background-color: ${INK}; text-decoration: none; padding: 12px 22px; border-radius: 12px;">
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td style="text-align: left; padding-right: 4px;">
                            <span style="display: block; font-family: ${FONT_BODY}; font-size: 10px; font-weight: 500; color: rgba(255,255,255,0.75); letter-spacing: 0.5px; line-height: 1.2;">Get it on</span>
                            <span style="display: block; font-family: ${FONT_DISPLAY}; font-size: 18px; font-weight: 800; color: ${PAPER}; line-height: 1.2; margin-top: 2px;">Google Play</span>
                          </td>
                        </tr>
                      </table>
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: ${CREAM}; padding: 32px 32px 28px; text-align: center; border-top: 1px solid ${RULE};">
              <p style="margin: 0 0 8px 0; font-family: ${FONT_DISPLAY}; font-size: 13px; font-weight: 800; color: ${INK};">
                Need help?
              </p>
              <p style="margin: 0 0 20px 0; font-family: ${FONT_BODY}; font-size: 13px; color: ${MUTED}; line-height: 1.65;">
                This email was sent by <strong style="color: ${INK};">${schoolName}</strong> via Lumi.<br />For questions about your child's account, contact your school directly.
              </p>
              <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto 10px;">
                <tr>
                  <td style="width: 4px; height: 4px; background-color: ${RED}; border-radius: 2px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 6px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 4px; height: 4px; background-color: ${YELLOW}; border-radius: 2px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 6px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 4px; height: 4px; background-color: ${RED}; border-radius: 2px; line-height: 0; font-size: 0;">&nbsp;</td>
                </tr>
              </table>
              <p style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 800; color: ${RED_DARK}; letter-spacing: 3px;">
                LUMI READING DIARY
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

// ─── Staff onboarding (temp password + login instructions) ────────────

export function buildStaffOnboardingEmail(params: {
  schoolName: string;
  staffName: string;
  role: "teacher" | "schoolAdmin";
  loginEmail: string;
  /** Sign-in password — included only when the admin created the account and
   *  the teacher hasn't signed in yet. Omitted for self-registered / active. */
  tempPassword?: string;
  /** School join code — shown to teachers so they can join in the Lumi app. */
  schoolCode?: string;
  portalUrl: string;
  appStoreUrl?: string;
  playStoreUrl?: string;
  customMessage?: string;
}): string {
  const {
    role,
    tempPassword,
    schoolCode,
    portalUrl,
    appStoreUrl = "#",
    playStoreUrl = "#",
    customMessage,
  } = params;
  // Roster-supplied values — a staff CSV import can carry markup in a name or
  // address — so escape before splicing into the HTML body. tempPassword,
  // schoolCode and portalUrl are server-generated.
  const schoolName = escapeHtml(params.schoolName);
  const staffName = escapeHtml(params.staffName);
  const loginEmail = escapeHtml(params.loginEmail);

  const isAdmin = role === "schoolAdmin";
  const roleLabel = isAdmin ? "Administrator" : "Teacher";
  const firstName = staffName.split(" ")[0] || staffName;
  const mascotSrc = `cid:${LUMI_MASCOT_CONTENT_ID}`;
  const hasTempPassword = !!tempPassword;
  // Show the school code only on the self-register path (no temp password).
  // Admin-created teachers log in directly with the password above, so the
  // join code would just be noise — keep that email focused on logging in.
  const showSchoolCode = !!schoolCode && !isAdmin && !hasTempPassword;

  const customMessageBlock = renderSchoolNoteBlock(customMessage);

  const credentialCard = hasTempPassword ? `
      <tr>
        <td style="padding: 0 24px 8px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CARD_TINT}; background-image: linear-gradient(180deg, ${CARD_TINT} 0%, ${PAPER} 78%); border-radius: 20px; border: 1px solid ${RULE};">
            <tr>
              <td style="padding: 28px 24px;">
                <p style="margin: 0 0 4px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; text-transform: uppercase; letter-spacing: 2px; text-align: center;">
                  Your sign-in email
                </p>
                <p style="margin: 0 0 20px 0; font-family: ${FONT_DISPLAY}; font-size: 18px; font-weight: 800; color: ${INK}; text-align: center; line-height: 1.3; word-break: break-all;">
                  ${loginEmail}
                </p>
                <p style="margin: 0 0 10px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; text-transform: uppercase; letter-spacing: 2px; text-align: center;">
                  Temporary password
                </p>
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                  <tr>
                    <td style="background-color: ${PAPER}; border: 2px dashed ${RED}; border-radius: 14px; padding: 18px 30px;">
                      <span style="font-family: ${FONT_MONO}; font-size: 26px; font-weight: 700; color: ${RED}; letter-spacing: 3px;">
                        ${tempPassword}
                      </span>
                    </td>
                  </tr>
                </table>
                <p style="margin: 16px 0 0 0; font-family: ${FONT_BODY}; font-size: 13px; color: ${MUTED}; text-align: center; line-height: 1.5;">
                  Please change your password after signing in.
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>` : "";

  const schoolCodeCard = showSchoolCode ? `
      <tr>
        <td style="padding: 0 24px 8px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CARD_TINT}; background-image: linear-gradient(180deg, ${CARD_TINT} 0%, ${PAPER} 78%); border-radius: 20px; border: 1px solid ${RULE};">
            <tr>
              <td style="padding: 28px 24px;">
                <p style="margin: 0 0 16px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; text-transform: uppercase; letter-spacing: 2px; text-align: center;">
                  Your school code
                </p>
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                  <tr>
                    <td style="background-color: ${PAPER}; border: 2px dashed ${RED}; border-radius: 14px; padding: 18px 34px;">
                      <span style="font-family: ${FONT_MONO}; font-size: 28px; font-weight: 700; color: ${RED}; letter-spacing: 5px;">
                        ${schoolCode}
                      </span>
                    </td>
                  </tr>
                </table>
                <p style="margin: 16px 0 0 0; font-family: ${FONT_BODY}; font-size: 13px; color: ${MUTED}; text-align: center; line-height: 1.5;">
                  Enter this in the Lumi app to join ${schoolName}.
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>` : "";

  // Steps adapt to how this person gets in: log in with a temp password
  // (admin-created), or join with the school code (self-register).
  const stepItems = isAdmin ?
    (hasTempPassword ?
      [
        renderStep(1, "Open the school portal", "Go to the Lumi school portal in your web browser."),
        renderStep(2, "Sign in", "Use the email and temporary password above."),
        renderStep(3, "Set your own password", "Update your password from your profile once you're in."),
      ] :
      [
        renderStep(1, "Open the school portal", "Go to the Lumi school portal in your web browser."),
        renderStep(2, "Sign in", "Use your email and password to log in."),
      ]) :
    (hasTempPassword ?
      [
        renderStep(1, "Download the Lumi app", "Available on the App Store and Google Play."),
        renderStep(2, "Log in", "Sign in with your email and the temporary password above."),
        renderStep(3, "Set your own password", "Update your password from your profile once you're in."),
      ] :
      [
        renderStep(1, "Download the Lumi app", "Available on the App Store and Google Play."),
        renderStep(2, "Enter your school code", "Use the code above to join your school in the app."),
        renderStep(3, "Create your account", "Sign up with your email address to finish setting up."),
      ]);
  const steps = stepItems.join("\n");

  const sectionTitle = hasTempPassword ? "How to sign in" : "How to get started";
  const welcomeLead = hasTempPassword ?
    `You've been added to <strong style="color: ${RED};">${schoolName}</strong> on Lumi as a ${roleLabel}. Here are your sign-in details.` :
    `You've been added to <strong style="color: ${RED};">${schoolName}</strong> on Lumi as a ${roleLabel}. Here's how to get set up.`;

  const ctaBlock = isAdmin ?
    `
          <!-- Portal button -->
          <tr>
            <td style="padding: 32px 32px 16px; text-align: center;">
              <a href="${portalUrl}" target="_blank" style="display: inline-block; background-color: ${RED}; background-image: ${RED_GRADIENT}; text-decoration: none; padding: 14px 32px; border-radius: 12px; font-family: ${FONT_DISPLAY}; font-size: 16px; font-weight: 800; color: ${PAPER};">
                Open the school portal
              </a>
            </td>
          </tr>` :
    `
          <!-- App buttons -->
          <tr>
            <td style="padding: 32px 32px 16px; text-align: center;">
              <p style="margin: 0 0 16px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; text-transform: uppercase; letter-spacing: 3px;">
                Get the app
              </p>
              <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                <tr>
                  <td style="padding: 4px;">
                    <a href="${appStoreUrl}" target="_blank" style="display: inline-block; background-color: ${INK}; text-decoration: none; padding: 12px 22px; border-radius: 12px; font-family: ${FONT_DISPLAY}; font-size: 15px; font-weight: 800; color: ${PAPER};">App Store</a>
                  </td>
                  <td style="padding: 4px;">
                    <a href="${playStoreUrl}" target="_blank" style="display: inline-block; background-color: ${INK}; text-decoration: none; padding: 12px 22px; border-radius: 12px; font-family: ${FONT_DISPLAY}; font-size: 15px; font-weight: 800; color: ${PAPER};">Google Play</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>`;

  return `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <title>Your Lumi staff account</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Nunito:wght@700;800&family=Inter:wght@400;500&display=swap" rel="stylesheet">
</head>
<body style="margin: 0; padding: 0; background-color: ${CREAM}; -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CREAM};">
    <tr>
      <td align="center" style="padding: 32px 16px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width: 600px; width: 100%; background-color: ${PAPER}; border-radius: 24px; overflow: hidden; box-shadow: 0 8px 24px rgba(26,26,26,0.08);">

          <!-- Hero -->
          <tr>
            <td style="background-color: ${RED}; background-image: ${RED_GRADIENT}; padding: 44px 32px 40px; text-align: center;">
              <img src="${mascotSrc}" width="103" height="100" alt="Lumi" style="display: block; width: 103px; height: 100px; margin: 0 auto 14px;" />
              <h1 style="margin: 0 0 8px 0; font-family: ${FONT_DISPLAY}; font-size: 44px; font-weight: 800; color: ${PAPER}; letter-spacing: 1px; line-height: 1;">
                Lumi
              </h1>
              <p style="margin: 0 0 20px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${PAPER}; text-transform: uppercase; letter-spacing: 4px; opacity: 0.95;">
                Reading Diary
              </p>
              <p style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 15px; color: ${PAPER}; font-weight: 700;">
                ${schoolName}
              </p>
            </td>
          </tr>

          <!-- Welcome -->
          <tr>
            <td style="padding: 40px 40px 12px 40px; text-align: center;">
              <h2 style="margin: 0 0 12px 0; font-family: ${FONT_DISPLAY}; font-size: 26px; font-weight: 800; color: ${INK}; line-height: 1.25;">
                Welcome to the team, ${firstName}!
              </h2>
              <p style="margin: 0; font-family: ${FONT_BODY}; font-size: 15px; color: ${INK_SOFT}; line-height: 1.7;">
                ${welcomeLead}
              </p>
            </td>
          </tr>

          ${customMessageBlock}

          <tr><td style="height: 20px; line-height: 20px; font-size: 0;">&nbsp;</td></tr>

          ${credentialCard}
          ${schoolCodeCard}

          <!-- Section title -->
          <tr>
            <td style="padding: 28px 32px 4px;">
              <h3 style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 22px; font-weight: 800; color: ${INK}; text-align: center;">
                ${sectionTitle}
              </h3>
            </td>
          </tr>

          <!-- Steps -->
          <tr>
            <td style="padding: 20px 32px 0;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                ${steps}
              </table>
            </td>
          </tr>

          ${ctaBlock}

          <!-- Footer -->
          <tr>
            <td style="background-color: ${CREAM}; padding: 32px 32px 28px; text-align: center; border-top: 1px solid ${RULE};">
              <p style="margin: 0 0 8px 0; font-family: ${FONT_DISPLAY}; font-size: 13px; font-weight: 800; color: ${INK};">
                Need help?
              </p>
              <p style="margin: 0 0 20px 0; font-family: ${FONT_BODY}; font-size: 13px; color: ${MUTED}; line-height: 1.65;">
                This email was sent by <strong style="color: ${INK};">${schoolName}</strong> via Lumi.<br />If you weren't expecting this, please contact your school.
              </p>
              <p style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 800; color: ${RED_DARK}; letter-spacing: 3px;">
                LUMI READING DIARY
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

// ─── Demo-day access (rolling credentials for a sales demo) ───────────

/**
 * A single "Label: value" credential row inside a demo card.
 * @param {string} label The row label (already plain text).
 * @param {string} value The already-escaped value to show in mono.
 * @return {string} The row HTML.
 */
function renderDemoCredentialRow(label: string, value: string): string {
  return `
                <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin: 0 0 8px 0;">
                  <tr>
                    <td style="font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${RED_DARK}; text-transform: uppercase; letter-spacing: 1.5px; padding-bottom: 2px;">
                      ${label}
                    </td>
                  </tr>
                  <tr>
                    <td style="font-family: ${FONT_MONO}; font-size: 16px; font-weight: 700; color: ${INK}; word-break: break-all;">
                      ${value}
                    </td>
                  </tr>
                </table>`;
}

export function buildDemoAccessEmail(params: {
  contactPerson: string;
  schoolName: string;
  /** Human date, e.g. "Friday 11 Jul", for the body copy. */
  dateLabel: string;
  password: string;
  adminEmail: string;
  teacherEmail: string;
  parentEmail: string;
  portalLoginUrl: string;
  marketingUrl: string;
  /** null ⇒ the email shows a "search for Lumi Reading" line, not a dead link. */
  appStoreUrl: string | null;
  playStoreUrl: string | null;
}): string {
  const {
    contactPerson,
    schoolName,
    dateLabel,
    password,
    adminEmail,
    teacherEmail,
    parentEmail,
    portalLoginUrl,
    marketingUrl,
    appStoreUrl,
    playStoreUrl,
  } = params;

  const firstName = contactPerson.trim().split(" ")[0] || "";
  const greeting = firstName ? `Hi ${escapeHtml(firstName)},` : "Hi there,";
  const forSchool = schoolName.trim() ?
    ` for today's session (<strong style="color: ${RED};">${escapeHtml(schoolName.trim())}</strong>)` :
    " for today's session";
  const pw = escapeHtml(password);

  // Store row: link buttons only when BOTH URLs exist; otherwise a plain
  // "search for Lumi Reading" line so we never ship dead `#` links.
  const bothStoreUrls = !!appStoreUrl && !!playStoreUrl;
  const storeBlock = bothStoreUrls ?
    `
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 6px auto 0;">
                  <tr>
                    <td style="padding: 4px;">
                      <a href="${appStoreUrl}" target="_blank" style="display: inline-block; background-color: ${INK}; text-decoration: none; padding: 10px 20px; border-radius: 12px; font-family: ${FONT_DISPLAY}; font-size: 14px; font-weight: 800; color: ${PAPER};">App Store</a>
                    </td>
                    <td style="padding: 4px;">
                      <a href="${playStoreUrl}" target="_blank" style="display: inline-block; background-color: ${INK}; text-decoration: none; padding: 10px 20px; border-radius: 12px; font-family: ${FONT_DISPLAY}; font-size: 14px; font-weight: 800; color: ${PAPER};">Google Play</a>
                    </td>
                  </tr>
                </table>` :
    `
                <p style="margin: 6px 0 0 0; font-family: ${FONT_BODY}; font-size: 14px; color: ${INK_SOFT}; text-align: center; line-height: 1.6;">
                  Search for <strong>&ldquo;Lumi Reading&rdquo;</strong> in the App Store or Google Play.
                </p>`;

  return `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <title>Your Lumi demo access</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Nunito:wght@700;800&family=Inter:wght@400;500&display=swap" rel="stylesheet">
</head>
<body style="margin: 0; padding: 0; background-color: ${CREAM}; -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CREAM};">
    <tr>
      <td align="center" style="padding: 32px 16px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width: 600px; width: 100%; background-color: ${PAPER}; border-radius: 24px; overflow: hidden; box-shadow: 0 8px 24px rgba(26,26,26,0.08);">

          <!-- Hero -->
          <tr>
            <td style="background-color: ${RED}; background-image: ${RED_GRADIENT}; padding: 44px 32px 40px; text-align: center;">
              <img src="cid:${LUMI_MASCOT_CONTENT_ID}" width="103" height="100" alt="Lumi" style="display: block; width: 103px; height: 100px; margin: 0 auto 14px;" />
              <h1 style="margin: 0 0 8px 0; font-family: ${FONT_DISPLAY}; font-size: 44px; font-weight: 800; color: ${PAPER}; letter-spacing: 1px; line-height: 1;">
                Lumi
              </h1>
              <p style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${PAPER}; text-transform: uppercase; letter-spacing: 4px; opacity: 0.95;">
                Demo access
              </p>
            </td>
          </tr>

          <!-- Welcome -->
          <tr>
            <td style="padding: 40px 40px 12px 40px; text-align: center;">
              <h2 style="margin: 0 0 12px 0; font-family: ${FONT_DISPLAY}; font-size: 26px; font-weight: 800; color: ${INK}; line-height: 1.25;">
                ${greeting}
              </h2>
              <p style="margin: 0; font-family: ${FONT_BODY}; font-size: 15px; color: ${INK_SOFT}; line-height: 1.7;">
                Thanks for booking a Lumi demo — here's everything you need${forSchool} on <strong>${escapeHtml(dateLabel)}</strong>.
              </p>
            </td>
          </tr>

          <tr><td style="height: 20px; line-height: 20px; font-size: 0;">&nbsp;</td></tr>

          <!-- School admin portal card -->
          <tr>
            <td style="padding: 0 24px 8px 24px;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CARD_TINT}; background-image: linear-gradient(180deg, ${CARD_TINT} 0%, ${PAPER} 78%); border-radius: 20px; border: 1px solid ${RULE};">
                <tr>
                  <td style="padding: 26px 24px;">
                    <p style="margin: 0 0 6px 0; font-family: ${FONT_DISPLAY}; font-size: 18px; font-weight: 800; color: ${INK};">
                      School admin portal
                    </p>
                    <p style="margin: 0 0 18px 0; font-family: ${FONT_BODY}; font-size: 14px; color: ${MUTED}; line-height: 1.6;">
                      Works in any browser. Go to <a href="${marketingUrl}" target="_blank" style="color: ${RED}; font-weight: 700; text-decoration: none;">${marketingUrl}</a> and click <strong>Log in</strong> (top right), or go straight to <a href="${portalLoginUrl}" target="_blank" style="color: ${RED}; font-weight: 700; text-decoration: none;">the portal login</a>.
                    </p>
                    ${renderDemoCredentialRow("Email", escapeHtml(adminEmail))}
                    ${renderDemoCredentialRow("Password", pw)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Lumi app card -->
          <tr>
            <td style="padding: 0 24px 8px 24px;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CARD_TINT}; background-image: linear-gradient(180deg, ${CARD_TINT} 0%, ${PAPER} 78%); border-radius: 20px; border: 1px solid ${RULE};">
                <tr>
                  <td style="padding: 26px 24px;">
                    <p style="margin: 0 0 6px 0; font-family: ${FONT_DISPLAY}; font-size: 18px; font-weight: 800; color: ${INK};">
                      The Lumi app
                    </p>
                    <p style="margin: 0 0 18px 0; font-family: ${FONT_BODY}; font-size: 14px; color: ${MUTED}; line-height: 1.6;">
                      How teachers &amp; parents use Lumi day-to-day. Both logins use the <strong>same password</strong> as above.
                    </p>
                    ${renderDemoCredentialRow("Teacher login", escapeHtml(teacherEmail))}
                    ${renderDemoCredentialRow("Parent login (mobile app only)", escapeHtml(parentEmail))}
                    ${storeBlock}
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Expiry + data-hygiene note -->
          <tr>
            <td style="padding: 16px 24px 8px 24px;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${NOTE_BG}; border-radius: 14px;">
                <tr>
                  <td style="padding: 18px 22px;">
                    <p style="margin: 0 0 6px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${NOTE_LABEL}; text-transform: uppercase; letter-spacing: 2px;">
                      Good to know
                    </p>
                    <p style="margin: 0; font-family: ${FONT_BODY}; font-size: 14px; color: ${INK}; line-height: 1.65;">
                      These logins are live <strong>today only</strong> and expire at midnight (AEST/AEDT) — ask us for fresh access any time. This is a shared demo environment with sample students, so please don't enter real student data.
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: ${CREAM}; padding: 32px 32px 28px; text-align: center; border-top: 1px solid ${RULE};">
              <p style="margin: 0 0 8px 0; font-family: ${FONT_DISPLAY}; font-size: 13px; font-weight: 800; color: ${INK};">
                Questions?
              </p>
              <p style="margin: 0 0 20px 0; font-family: ${FONT_BODY}; font-size: 13px; color: ${MUTED}; line-height: 1.65;">
                Just reply to this email — we're happy to help you get the most out of your demo.
              </p>
              <p style="margin: 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 800; color: ${RED_DARK}; letter-spacing: 3px;">
                LUMI READING DIARY
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function renderStep(num: number, title: string, body: string): string {
  return `
                <tr>
                  <td style="padding-bottom: 10px;">
                    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${CREAM}; border-radius: 14px; border-left: 4px solid ${RED};">
                      <tr>
                        <td style="padding: 14px 16px; vertical-align: top; width: 44px;">
                          <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                              <td style="width: 34px; height: 34px; background-color: ${RED}; background-image: linear-gradient(135deg, #F2615F 0%, ${RED} 100%); border-radius: 17px; text-align: center; font-family: ${FONT_DISPLAY}; font-size: 15px; font-weight: 800; color: ${PAPER}; line-height: 34px;">
                                ${num}
                              </td>
                            </tr>
                          </table>
                        </td>
                        <td style="padding: 14px 18px 14px 4px;">
                          <p style="margin: 0 0 2px 0; font-family: ${FONT_DISPLAY}; font-size: 15px; font-weight: 700; color: ${INK}; line-height: 1.3;">
                            ${title}
                          </p>
                          <p style="margin: 0; font-family: ${FONT_BODY}; font-size: 13px; color: ${MUTED}; line-height: 1.5;">
                            ${body}
                          </p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>`;
}
