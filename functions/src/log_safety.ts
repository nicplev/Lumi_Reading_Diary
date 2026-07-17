/**
 * Returns a bounded, non-message error classification suitable for logs.
 *
 * Error messages can contain document paths, email addresses, phone numbers,
 * provider payloads or other personal data. Operational logs need the failure
 * class, not the raw message; full authorised workflow detail belongs in the
 * relevant protected audit/job record.
 * @param {unknown} error Error-like value to classify.
 * @return {string} A bounded code or `unknown`.
 */
export function errorCodeForLog(error: unknown): string {
  if (error && typeof error === "object") {
    const code = (error as {code?: unknown}).code;
    if (typeof code === "string" && /^[A-Za-z0-9._/-]{1,80}$/.test(code)) {
      return code;
    }
    const status = (error as {status?: unknown}).status;
    if (typeof status === "number" && Number.isInteger(status)) {
      return `http_${status}`;
    }
  }

  if (error instanceof Error && /^[A-Za-z0-9._-]{1,80}$/.test(error.name)) {
    return error.name;
  }
  return "unknown";
}
