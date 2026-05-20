import type { Firestore } from "firebase-admin/firestore";

// The resolved super-admin identity performing an operation. Server-ops
// functions require this explicitly so they can never run without a known
// actor — the calling route is responsible for authenticating it.
export interface Actor {
  uid: string;
  email?: string;
}

export interface AuditLogInput {
  action: string;
  performedBy: string;
  performedByEmail?: string;
  targetType: string;
  targetId: string;
  schoolId?: string;
  after?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

// Thrown for caller-supplied input that fails validation. Routes map this to
// HTTP 400; anything else is an unexpected 500.
export class ServerOpsValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ServerOpsValidationError";
  }
}

export async function logAuditEvent(
  db: Firestore,
  entry: AuditLogInput
): Promise<void> {
  await db.collection("adminAuditLog").add({
    ...entry,
    createdAt: new Date(),
  });
}
