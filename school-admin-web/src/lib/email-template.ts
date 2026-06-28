import QRCode from "qrcode";
import { LUMI_MASCOT_DATA_URI } from "./email-assets";

// ─── Lumi email design tokens ─────────────────────────────────────────────
// In-portal preview of the parent onboarding email. This is a synced twin of
// the real template at functions/src/email_templates.ts — keep the two in sync
// (cross-package import isn't available). Differences are intentional: the
// preview embeds the QR + mascot as data-URIs (no email attachments).
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

interface OnboardingEmailEntry {
  studentName: string;
  linkCode: string;
}

export async function buildOnboardingEmailPreview(params: {
  schoolName: string;
  entries: OnboardingEmailEntry[];
  customMessage?: string;
  appStoreUrl?: string;
  playStoreUrl?: string;
}): Promise<string> {
  const {
    schoolName,
    entries,
    customMessage,
    appStoreUrl = "#",
    playStoreUrl = "#",
  } = params;

  const entryCards = (
    await Promise.all(
      entries.map(async (entry) => {
        const qrDataUri = await QRCode.toDataURL(entry.linkCode, {
          width: 400,
          margin: 2,
          errorCorrectionLevel: "M",
        });
        return renderEntryCard({
          studentName: entry.studentName,
          linkCode: entry.linkCode,
          qrSrc: qrDataUri,
        });
      })
    )
  ).join("\n");

  return renderEmailShell({
    schoolName,
    customMessage,
    appStoreUrl,
    playStoreUrl,
    entryCards,
    mascotSrc: LUMI_MASCOT_DATA_URI,
  });
}

interface EntryCardParams {
  studentName: string;
  linkCode: string;
  qrSrc: string;
}

function renderEntryCard(params: EntryCardParams): string {
  const { studentName, linkCode, qrSrc } = params;
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

function renderEmailShell(params: EmailShellParams): string {
  const { schoolName, customMessage, appStoreUrl, playStoreUrl, entryCards, mascotSrc } =
    params;

  const customMessageBlock = customMessage
    ? `
      <tr>
        <td style="padding: 0 24px 24px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: ${NOTE_BG}; border-radius: 14px;">
            <tr>
              <td style="padding: 18px 22px;">
                <p style="margin: 0 0 6px 0; font-family: ${FONT_DISPLAY}; font-size: 11px; font-weight: 700; color: ${NOTE_LABEL}; text-transform: uppercase; letter-spacing: 2px;">
                  A note from your school
                </p>
                <p style="margin: 0; font-family: ${FONT_BODY}; font-size: 14px; color: ${INK}; line-height: 1.65;">
                  ${customMessage}
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>`
    : "";

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
              <img src="${mascotSrc}" width="88" height="110" alt="Lumi" style="display: block; width: 88px; height: 110px; margin: 0 auto 14px;" />
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
                ${renderStep(2, "Create your parent account", "Sign up with your email or use Google / Apple sign-in.")}
                ${renderStep(3, "Enter your link code", "Use the code above, or scan the QR with the app.")}
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
