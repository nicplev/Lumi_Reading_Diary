import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

// Super-admin-side access granting. When a school is activated (a comp/paid
// subscription is set), students who were IMPORTED but never provisioned have
// no `access` record, so the fail-closed rules would still block their parents.
// This provisions those students. Suspended/expired students are deliberately
// left alone — the onSchoolSubscriptionWrite cascade restores them and the
// renewals flow owns year-to-year decisions, so this never clobbers that state.
//
// Mirrors the access-model math in functions/src/access.ts (keep in sync).

const DEFAULT_TZ = "Australia/Sydney";

function timezoneOffsetMs(d: Date): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: DEFAULT_TZ,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
  });
  const map: Record<string, number> = {};
  for (const p of dtf.formatToParts(d)) {
    if (p.type !== "literal") map[p.type] = Number(p.value);
  }
  const asUtc = Date.UTC(
    map.year, map.month - 1, map.day,
    map.hour === 24 ? 0 : map.hour, map.minute, map.second
  );
  return asUtc - d.getTime();
}

/** Absolute hard-expiry: end of 31 Jan of the following year, local time. */
export function hardExpiryFor(academicYear: number): Date {
  const naiveUtc = Date.UTC(academicYear + 1, 0, 31, 23, 59, 59);
  return new Date(naiveUtc - timezoneOffsetMs(new Date(naiveUtc)));
}

/**
 * Grant `book_pack_assumed` access for `academicYear` to every active student
 * in the school that has NO access record yet. Grant-only and idempotent
 * (students with any existing access map are skipped — the cascade/renewals
 * own those). Chunked into 400-write batches. Returns the number granted.
 */
export async function provisionUnprovisionedStudents(
  schoolId: string,
  academicYear: number,
  grantedBy: string
): Promise<number> {
  const db = getAdminDb();
  const snap = await db
    .collection("schools").doc(schoolId).collection("students")
    .where("isActive", "==", true)
    .get();

  const targets = snap.docs.filter((d) => d.data().access == null);
  if (targets.length === 0) return 0;

  const expiresAt = hardExpiryFor(academicYear);
  for (let i = 0; i < targets.length; i += 400) {
    const chunk = targets.slice(i, i + 400);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        access: {
          status: "active",
          academicYear,
          expiresAt,
          source: "book_pack_assumed",
          grantedAt: FieldValue.serverTimestamp(),
          grantedBy,
        },
      });
    }
    await batch.commit();
  }
  return targets.length;
}
