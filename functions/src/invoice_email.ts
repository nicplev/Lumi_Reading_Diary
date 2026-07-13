import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import sgMail from "@sendgrid/mail";

const sendgridApiKey = defineSecret("SENDGRID_API_KEY");
const sendgridSenderEmail = defineSecret("SENDGRID_SENDER_EMAIL");

function escapeHtml(s: string): string {
  const map: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  };
  return s.replace(/[&<>"']/g, (c) => map[c]);
}

/**
 * Send a Lumi invoice by email. The super-admin portal writes a queue doc to
 * `invoiceEmails/{id}` with the client-generated PDF (base64); this trigger
 * attaches it and sends via SendGrid — mirroring processDemoAccessEmail.
 */
export const processInvoiceEmail = onDocumentCreated(
  {
    document: "invoiceEmails/{id}",
    secrets: [sendgridApiKey, sendgridSenderEmail],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.status && data.status !== "queued") return;

    // Claim the job so a retry can't double-send.
    await snap.ref.update({status: "processing"});

    try {
      const to = data.to as string | undefined;
      const pdfBase64 = data.pdfBase64 as string | undefined;
      if (!to || !pdfBase64) throw new Error("Missing recipient or PDF");

      const key = sendgridApiKey.value();
      if (!key) throw new Error("SENDGRID_API_KEY not configured");
      sgMail.setApiKey(key);
      const sender = sendgridSenderEmail.value() || "noreply@lumi-reading.app";

      const subject = (data.subject as string) || "Your Lumi invoice";
      const message =
        (data.message as string) ||
        "Please find your Lumi invoice attached. Thank you.";

      await sgMail.send({
        to,
        from: {email: sender, name: "Lumi"},
        replyTo: "support@lumi-reading.com",
        subject,
        html: `<p>${escapeHtml(message).replace(/\n/g, "<br/>")}</p>`,
        attachments: [
          {
            content: pdfBase64,
            filename: (data.filename as string) || "invoice.pdf",
            type: "application/pdf",
            disposition: "attachment",
          },
        ],
      });

      await snap.ref.update({
        status: "sent",
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (data.invoiceId) {
        await admin
          .firestore()
          .collection("invoices")
          .doc(data.invoiceId as string)
          .set(
            {
              lastEmailedAt: admin.firestore.FieldValue.serverTimestamp(),
              lastEmailedTo: to,
            },
            {merge: true}
          );
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      functions.logger.error("processInvoiceEmail failed", {error: msg});
      await snap.ref.update({status: "failed", error: msg});
    }
  }
);
