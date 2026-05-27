import QRCode from "qrcode";

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
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #FFF5F8; background-image: linear-gradient(180deg, #FFF5F8 0%, #FFFFFF 80%); border-radius: 20px; border: 1px solid #FCE4EC;">
            <tr>
              <td style="padding: 32px 24px;">
                <p style="margin: 0 0 4px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 11px; font-weight: 700; color: #AD1457; text-transform: uppercase; letter-spacing: 2px; text-align: center;">
                  Linking code for
                </p>
                <p style="margin: 0 0 24px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 22px; font-weight: 800; color: #1A1A2E; text-align: center; line-height: 1.2;">
                  ${studentName}
                </p>
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                  <tr>
                    <td style="background-color: #FFFFFF; border: 2px dashed #E91E63; border-radius: 14px; padding: 22px 36px;">
                      <span style="font-family: 'Courier New', Courier, monospace; font-size: 32px; font-weight: 700; color: #E91E63; letter-spacing: 6px;">
                        ${linkCode}
                      </span>
                    </td>
                  </tr>
                </table>
                <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top: 28px; margin-bottom: 20px;">
                  <tr>
                    <td style="border-top: 1px solid #FCE4EC; line-height: 0; font-size: 0;">&nbsp;</td>
                    <td style="padding: 0 14px; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 11px; font-weight: 700; color: #AD1457; letter-spacing: 2px; white-space: nowrap;">
                      OR SCAN
                    </td>
                    <td style="border-top: 1px solid #FCE4EC; line-height: 0; font-size: 0;">&nbsp;</td>
                  </tr>
                </table>
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                  <tr>
                    <td style="padding: 14px; background-color: #FFFFFF; border-radius: 16px; border: 1px solid #FCE4EC;">
                      <img src="${qrSrc}" width="160" height="160" alt="QR code for ${linkCode}" style="display: block; width: 160px; height: 160px;" />
                    </td>
                  </tr>
                </table>
                <p style="margin: 16px 0 0 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 13px; color: #6B7280; text-align: center; line-height: 1.5;">
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
}

function renderEmailShell(params: EmailShellParams): string {
  const { schoolName, customMessage, appStoreUrl, playStoreUrl, entryCards } =
    params;

  const customMessageBlock = customMessage
    ? `
      <tr>
        <td style="padding: 0 24px 24px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #FFF8E1; border-radius: 12px;">
            <tr>
              <td style="padding: 18px 22px;">
                <p style="margin: 0 0 6px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 11px; font-weight: 700; color: #B45309; text-transform: uppercase; letter-spacing: 2px;">
                  A note from your school
                </p>
                <p style="margin: 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; color: #1A1A2E; line-height: 1.65;">
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
  <title>Welcome to Lumi Reading Tracker</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800&display=swap" rel="stylesheet">
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
<body style="margin: 0; padding: 0; background-color: #F4EEF1; -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #F4EEF1;">
    <tr>
      <td align="center" style="padding: 32px 16px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width: 600px; width: 100%; background-color: #FFFFFF; border-radius: 20px; overflow: hidden; box-shadow: 0 4px 24px rgba(173,20,87,0.10);">

          <!-- Hero -->
          <tr>
            <td style="background-color: #E91E63; background-image: linear-gradient(135deg, #FF4D8D 0%, #E91E63 50%, #AD1457 100%); padding: 52px 32px 44px; text-align: center;">
              <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto 22px;">
                <tr>
                  <td style="width: 28px; height: 2px; background-color: #FFD54F; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 10px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 6px; height: 6px; background-color: #FFD54F; border-radius: 3px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 10px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 28px; height: 2px; background-color: #FFD54F; line-height: 0; font-size: 0;">&nbsp;</td>
                </tr>
              </table>
              <h1 style="margin: 0 0 10px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 48px; font-weight: 800; color: #FFFFFF; letter-spacing: 2px; line-height: 1;">
                Lumi
              </h1>
              <p style="margin: 0 0 22px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 11px; font-weight: 700; color: #FFFFFF; text-transform: uppercase; letter-spacing: 4px; opacity: 0.95;">
                Reading Diary
              </p>
              <p style="margin: 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #FFFFFF; font-weight: 700;">
                ${schoolName}
              </p>
            </td>
          </tr>

          <!-- Welcome -->
          <tr>
            <td style="padding: 44px 32px 12px 32px; text-align: center;">
              <h2 style="margin: 0 0 12px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 26px; font-weight: 800; color: #1A1A2E; line-height: 1.25;">
                Welcome to Lumi
              </h2>
              <p style="margin: 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #6B7280; line-height: 1.65;">
                You're a few taps away from following your<br />child's reading journey, all in one place.
              </p>
            </td>
          </tr>

          ${customMessageBlock}

          <!-- Explanation -->
          <tr>
            <td style="padding: 20px 40px 28px 40px;">
              <p style="margin: 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C; line-height: 1.7; text-align: center;">
                <strong style="color: #E91E63;">${schoolName}</strong> uses Lumi as their digital reading diary. Download the app and use the link code below to connect with your child's account.
              </p>
            </td>
          </tr>

          ${entryCards}

          <!-- Section title -->
          <tr>
            <td style="padding: 32px 32px 4px;">
              <h3 style="margin: 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 22px; font-weight: 800; color: #1A1A2E; text-align: center;">
                How it works
              </h3>
              <p style="margin: 6px 0 0 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; color: #6B7280; text-align: center;">
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
              <p style="margin: 0 0 16px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 11px; font-weight: 700; color: #AD1457; text-transform: uppercase; letter-spacing: 3px;">
                Get the app
              </p>
              <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                <tr>
                  <td style="padding: 4px;">
                    <a href="${appStoreUrl}" target="_blank" style="display: inline-block; background-color: #1A1A2E; text-decoration: none; padding: 12px 22px; border-radius: 12px;">
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td style="text-align: left; padding-right: 4px;">
                            <span style="display: block; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 10px; font-weight: 600; color: rgba(255,255,255,0.75); letter-spacing: 0.5px; line-height: 1.2;">Download on the</span>
                            <span style="display: block; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 18px; font-weight: 800; color: #FFFFFF; line-height: 1.2; margin-top: 2px;">App Store</span>
                          </td>
                        </tr>
                      </table>
                    </a>
                  </td>
                  <td style="padding: 4px;">
                    <a href="${playStoreUrl}" target="_blank" style="display: inline-block; background-color: #1A1A2E; text-decoration: none; padding: 12px 22px; border-radius: 12px;">
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td style="text-align: left; padding-right: 4px;">
                            <span style="display: block; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 10px; font-weight: 600; color: rgba(255,255,255,0.75); letter-spacing: 0.5px; line-height: 1.2;">Get it on</span>
                            <span style="display: block; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 18px; font-weight: 800; color: #FFFFFF; line-height: 1.2; margin-top: 2px;">Google Play</span>
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
            <td style="background-color: #FAFAFA; padding: 32px 32px 28px; text-align: center; border-top: 1px solid #F0E8EE;">
              <p style="margin: 0 0 8px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 13px; font-weight: 800; color: #1A1A2E;">
                Need help?
              </p>
              <p style="margin: 0 0 20px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 13px; color: #6B7280; line-height: 1.65;">
                This email was sent by <strong style="color: #1A1A2E;">${schoolName}</strong> via Lumi.<br />For questions about your child's account, contact your school directly.
              </p>
              <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto 10px;">
                <tr>
                  <td style="width: 4px; height: 4px; background-color: #E91E63; border-radius: 2px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 6px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 4px; height: 4px; background-color: #E91E63; border-radius: 2px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 6px; line-height: 0; font-size: 0;">&nbsp;</td>
                  <td style="width: 4px; height: 4px; background-color: #E91E63; border-radius: 2px; line-height: 0; font-size: 0;">&nbsp;</td>
                </tr>
              </table>
              <p style="margin: 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 11px; font-weight: 800; color: #AD1457; letter-spacing: 3px;">
                LUMI READING TRACKER
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
                    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #FAFAFA; border-radius: 12px; border-left: 4px solid #E91E63;">
                      <tr>
                        <td style="padding: 14px 16px; vertical-align: top; width: 44px;">
                          <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                              <td style="width: 34px; height: 34px; background-color: #E91E63; background-image: linear-gradient(135deg, #FF4D8D 0%, #E91E63 100%); border-radius: 17px; text-align: center; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; font-weight: 800; color: #FFFFFF; line-height: 34px;">
                                ${num}
                              </td>
                            </tr>
                          </table>
                        </td>
                        <td style="padding: 14px 18px 14px 4px;">
                          <p style="margin: 0 0 2px 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; font-weight: 700; color: #1A1A2E; line-height: 1.3;">
                            ${title}
                          </p>
                          <p style="margin: 0; font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 13px; color: #6B7280; line-height: 1.5;">
                            ${body}
                          </p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>`;
}
