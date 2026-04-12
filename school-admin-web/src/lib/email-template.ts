interface OnboardingEmailEntry {
  studentName: string;
  linkCode: string;
}

export function buildOnboardingEmailPreview(params: {
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
    .map(
      (entry) => `
      <tr>
        <td style="padding: 0 24px 16px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #FFFFFF; border-radius: 12px; border: 1px solid #E0E0E0;">
            <tr>
              <td style="padding: 24px; text-align: center;">
                <p style="margin: 0 0 12px 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C;">
                  Your link code for <strong>${entry.studentName}</strong>:
                </p>
                <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                  <tr>
                    <td style="background-color: #FFF0F3; border: 2px dashed #E91E63; border-radius: 8px; padding: 16px 32px;">
                      <span style="font-family: 'Courier New', Courier, monospace; font-size: 28px; font-weight: 700; color: #E91E63; letter-spacing: 3px;">
                        ${entry.linkCode}
                      </span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </td>
      </tr>`
    )
    .join("\n");

  const customMessageBlock = customMessage
    ? `
      <tr>
        <td style="padding: 0 24px 24px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #FAFAFA; border-left: 4px solid #E91E63; border-radius: 4px;">
            <tr>
              <td style="padding: 16px 20px;">
                <p style="margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; color: #555555; font-style: italic; line-height: 1.6;">
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
<body style="margin: 0; padding: 0; background-color: #F5F5F5; -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #F5F5F5;">
    <tr>
      <td align="center" style="padding: 32px 16px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width: 600px; width: 100%; background-color: #FFFFFF; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.06);">

          <!-- Header -->
          <tr>
            <td style="background-color: #E91E63; padding: 32px 24px; text-align: center;">
              <h1 style="margin: 0 0 4px 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 36px; font-weight: 700; color: #FFFFFF; letter-spacing: 1px;">
                Lumi
              </h1>
              <p style="margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; color: rgba(255,255,255,0.85);">
                ${schoolName}
              </p>
            </td>
          </tr>

          <!-- Greeting -->
          <tr>
            <td style="padding: 32px 24px 8px 24px; text-align: center;">
              <h2 style="margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 22px; font-weight: 600; color: #2C2C2C;">
                Welcome to Lumi Reading Tracker!
              </h2>
            </td>
          </tr>

          <!-- Custom message -->
          ${customMessageBlock}

          <!-- Explanation -->
          <tr>
            <td style="padding: 16px 24px 24px 24px;">
              <p style="margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C; line-height: 1.6; text-align: center;">
                ${schoolName} uses <strong>Lumi</strong> as their digital reading diary. To get started, download the app and enter the link code below to connect to your child's account.
              </p>
            </td>
          </tr>

          <!-- Entry cards -->
          ${entryCards}

          <!-- Setup steps -->
          <tr>
            <td style="padding: 24px 24px 8px 24px;">
              <h3 style="margin: 0 0 16px 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 17px; font-weight: 600; color: #2C2C2C; text-align: center;">
                Getting Started
              </h3>
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="padding: 8px 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C; line-height: 1.5;">
                    <table cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="vertical-align: top; padding-right: 12px;">
                          <span style="display: inline-block; width: 28px; height: 28px; background-color: #E91E63; color: #FFFFFF; border-radius: 50%; text-align: center; line-height: 28px; font-size: 14px; font-weight: 600;">1</span>
                        </td>
                        <td style="vertical-align: middle; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C;">
                          Download Lumi from the App Store or Google Play
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 8px 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C; line-height: 1.5;">
                    <table cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="vertical-align: top; padding-right: 12px;">
                          <span style="display: inline-block; width: 28px; height: 28px; background-color: #E91E63; color: #FFFFFF; border-radius: 50%; text-align: center; line-height: 28px; font-size: 14px; font-weight: 600;">2</span>
                        </td>
                        <td style="vertical-align: middle; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C;">
                          Create your account
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 8px 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C; line-height: 1.5;">
                    <table cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="vertical-align: top; padding-right: 12px;">
                          <span style="display: inline-block; width: 28px; height: 28px; background-color: #E91E63; color: #FFFFFF; border-radius: 50%; text-align: center; line-height: 28px; font-size: 14px; font-weight: 600;">3</span>
                        </td>
                        <td style="vertical-align: middle; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C;">
                          Enter your link code when prompted
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 8px 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C; line-height: 1.5;">
                    <table cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="vertical-align: top; padding-right: 12px;">
                          <span style="display: inline-block; width: 28px; height: 28px; background-color: #E91E63; color: #FFFFFF; border-radius: 50%; text-align: center; line-height: 28px; font-size: 14px; font-weight: 600;">4</span>
                        </td>
                        <td style="vertical-align: middle; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; color: #2C2C2C;">
                          Start tracking your child's reading journey!
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- App store buttons -->
          <tr>
            <td style="padding: 24px 24px 32px 24px; text-align: center;">
              <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                <tr>
                  <td style="padding-right: 8px;">
                    <a href="${appStoreUrl}" target="_blank" style="display: inline-block; background-color: #2C2C2C; color: #FFFFFF; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; font-weight: 600; text-decoration: none; padding: 12px 24px; border-radius: 8px;">
                      App Store
                    </a>
                  </td>
                  <td style="padding-left: 8px;">
                    <a href="${playStoreUrl}" target="_blank" style="display: inline-block; background-color: #2C2C2C; color: #FFFFFF; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; font-weight: 600; text-decoration: none; padding: 12px 24px; border-radius: 8px;">
                      Google Play
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #F5F5F5; padding: 24px; text-align: center; border-top: 1px solid #E0E0E0;">
              <p style="margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 12px; color: #888888; line-height: 1.5;">
                This email was sent by ${schoolName} via Lumi Reading Tracker. If you have questions, please contact your school directly.
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
