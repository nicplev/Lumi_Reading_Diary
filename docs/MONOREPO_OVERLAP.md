# Monorepo Overlap Audit

> **Phase 2 artifact** of the monorepo migration. See [MONOREPO_MIGRATION.md](./MONOREPO_MIGRATION.md) for the overall plan and STATUS.
> Produced by Explore-agent scan of `admin/src/app/api/**`, `admin/src/lib/`, `lib/data/models/`, and `functions/src/`.
> This doc drives Phases 3 (shared types), 4 (auth unification), and 5 (business-logic migration).

---

## How to use this doc

- **Finding 1** is the canonical map of which admin routes touch which Firestore collections. Reference it when Phase 5 prioritizes which routes to move into Cloud Functions.
- **Finding 2** lists the type drift between TypeScript (admin) and Dart (Flutter). Phase 3 (`packages/types`) only consolidates the TS side — Dart stays separate. Use the **Drift** subsections to confirm no admin code is depending on a TS-only field.
- **Finding 3** is the prioritized Phase 5 candidate list. Do *not* migrate the "Low Priority" rows.
- **Finding 4** is the Phase 4 implementation sketch + the bootstrap risk you must mitigate before flipping the auth path.
- **Surprises** at the end are non-obvious facts about the codebase that future sessions should know.

---

## Finding 1 — Firestore Collection Access Map

| Route | HTTP | Reads | Writes | Tx/Batch |
|-------|------|-------|--------|----------|
| `/analytics` | GET | `schools`, `schoolOnboarding` | — | — |
| `/auth` | POST, DELETE | — | — | — |
| `/bulk/students` | POST | `schools/{schoolId}/classes`, `schools/{schoolId}/students` | `schools/{schoolId}/students`, `adminAuditLog` | ✓ batch (500 docs) |
| `/community-books/deletion-requests` | GET | `community_books/{isbn}/deletionRequests` (collectionGroup) | — | — |
| `/community-books/deletion-requests/[id]/resolve` | POST | `community_books/{isbn}/deletionRequests`, `schools/{schoolId}/books` | `community_books/{isbn}`, deletionRequests, `schools/{schoolId}/books`, `adminAuditLog`, Storage (community_books/covers/) | ✓ batch |
| `/dev-access` | GET, POST | `devAccessEmails` | `devAccessEmails`, `adminAuditLog` | — |
| `/dev-access/[id]` | PATCH, DELETE | — | `devAccessEmails`, `adminAuditLog` | — |
| `/export` | GET | `schools/{schoolId}/students`, classes, readingLogs, allocations | — | — |
| `/feedback/[id]/status` | POST | — | `feedback` | — |
| `/impersonation-audit/sessions/[sessionId]/events` | GET | `devImpersonationAudit` | — | — |
| `/impersonation-audit/sessions/[sessionId]/export` | GET | `devImpersonationSessions`, `devImpersonationAudit` | `devImpersonationAudit` | — |
| `/impersonation-audit/sessions/[sessionId]/revoke` | POST | `devImpersonationSessions` | `devImpersonationSessions`, `devImpersonationAudit`, `adminAuditLog` | — |
| `/link-codes` | POST | — | `linkCodes`, `adminAuditLog` | — |
| `/link-codes/[id]` | DELETE | — | `linkCodes`, `adminAuditLog` | — |
| `/offboard` | POST | `schools/{schoolId}` + 7 subcollections | `schools/{schoolId}` + all subcollections (isActive=false), `adminAuditLog` | ✓ batch per subcollection |
| `/onboarding/[id]` | PATCH | — | `schoolOnboarding`, `adminAuditLog` | — |
| `/school-codes` | POST | `schools/{schoolId}` | `schoolCodes`, `adminAuditLog` | — |
| `/school-codes/[id]` | DELETE | — | `schoolCodes`, `adminAuditLog` | — |
| `/schools` | POST | — | `schools`, `adminAuditLog` | — |
| `/schools/[schoolId]` | PATCH, DELETE | `schools/{schoolId}` | `schools`, `adminAuditLog` | — |
| `/schools/[schoolId]/allocations` | POST | — | `schools/{schoolId}/allocations`, `adminAuditLog` | — |
| `/schools/[schoolId]/allocations/[allocationId]` | PATCH, DELETE | — | `schools/{schoolId}/allocations`, `adminAuditLog` | — |
| `/schools/[schoolId]/analytics` | GET | `schools/{schoolId}/readingLogs`, students, classes | — | — |
| `/schools/[schoolId]/books` | POST | — | `schools/{schoolId}/books`, `adminAuditLog` | — |
| `/schools/[schoolId]/books/[bookId]` | PATCH, DELETE | — | `schools/{schoolId}/books`, `adminAuditLog` | — |
| `/schools/[schoolId]/classes` | POST | — | `schools/{schoolId}/classes`, `adminAuditLog` | — |
| `/schools/[schoolId]/classes/[classId]` | PATCH, DELETE | — | `schools/{schoolId}/classes`, `adminAuditLog` | — |
| `/schools/[schoolId]/logo` | POST | `schools/{schoolId}` | `schools`, `adminAuditLog`, Storage (schools/{schoolId}/logo.*) | — |
| `/schools/[schoolId]/reading-logs` | GET | `schools/{schoolId}/readingLogs` | — | — |
| `/schools/[schoolId]/students` | POST | — | `schools/{schoolId}/students`, `adminAuditLog` | — |
| `/schools/[schoolId]/students/[studentId]` | PATCH, DELETE | — | `schools/{schoolId}/students`, `adminAuditLog` | — |
| `/schools/[schoolId]/students/[studentId]/reading-level` | POST | — | `schools/{schoolId}/students` (level + levelHistory), `adminAuditLog` | — |
| `/schools/[schoolId]/users` | POST | Firebase Auth, `schools/{schoolId}/users` | Firebase Auth, `schools/{schoolId}/users`, `adminAuditLog` | — |
| `/schools/[schoolId]/users/[userId]` | PATCH, DELETE | — | `schools/{schoolId}/users`, `adminAuditLog` | — |
| `/schools/[schoolId]/users/[userId]/auth` | POST | Firebase Auth | Firebase Auth, `adminAuditLog` | — |

### Group-level summary

- **schools** + subcollections (students, parents, classes, allocations, books, readingLogs, users): primary write surface
- **community_books** + `deletionRequests` subcollection: approval flow + cascade delete
- **schoolOnboarding**: funnel-stage updates
- **devAccessEmails / linkCodes / schoolCodes**: admin-managed allowlists
- **adminAuditLog**: append-only audit trail (every write route logs to it; admin routes never read from it — see Surprise #5)
- **devImpersonationSessions / devImpersonationAudit**: admin can read + revoke
- **Firebase Auth**: user create / enable-disable / password reset via Admin SDK
- **Storage**: school logos + community-book covers

---

## Finding 2 — Type ↔ Dart Model Mapping

### School

**TS** (`admin/src/lib/types/school.ts`):
```typescript
interface School {
  id: string;
  name: string;
  logoUrl?: string;
  primaryColor?: string;
  secondaryColor?: string;
  levelSchema: ReadingLevelSchema;          // 'aToZ' | 'pmBenchmark' | 'lexile' | 'custom'
  customLevels?: string[];
  termDates: Record<string, FirestoreTimestamp>;
  quietHours: Record<string, string>;
  timezone: string;
  address?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  createdBy: string;
  settings?: Record<string, unknown>;
  studentCount: number;
  teacherCount: number;
  parentCount: number;                       // TS-only
  subscriptionPlan?: string;
  subscriptionExpiry?: FirestoreTimestamp;
}
```

**Dart** (`lib/data/models/school_model.dart`): same fields **except** `parentCount` (computed in analytics), plus Dart-only:
- `levelColors?: Map<String, String>` — UI rendering hint
- ReadingLevelSchema enum has extra UI variants (`none`, `numbered`, `namedLevels`, `colouredLevels`) the admin doesn't surface

**Drift summary:** admin writes everything except `parentCount` and `levelColors`. Both are read-only / aggregate fields — no integrity risk.

---

### Student

**TS** (`admin/src/lib/types/student.ts`): standard fields + `levelHistory: ReadingLevelHistory[]`, `stats?: StudentStats`.

**Dart** (`lib/data/models/student_model.dart`) adds:
- `characterId?: string` (Flutter UI personalization)
- `enrollmentStatus?: string` (`'book_pack' | 'direct_purchase'` etc.)
- `parentEmail?: string` (denormalized for parent-linking flow)

**Drift summary:** Admin writes students without these three Dart-only fields. Flutter must tolerate them being undefined on student docs created by admin — confirm this on the Dart side before Phase 5 work on student creation routes.

---

### SchoolUser

**TS** (`admin/src/lib/types/school-user.ts`): role-based (parent/teacher/schoolAdmin), `linkedChildren`, `classIds`, `fcmToken`.

**Dart** (`lib/data/models/user_model.dart`) adds:
- `phoneNumber?: string` (E.164, SMS MFA)
- `phoneVerified: bool`

**Drift summary:** Admin doesn't manage phone-auth fields. Routes that PATCH a user must not overwrite `phoneNumber` / `phoneVerified` with undefined — verify the merge semantics in `/schools/[schoolId]/users/[userId]` PATCH before Phase 4 lands.

---

### ReadingLog, Allocation, Class, Book, Achievement

All admin-side types are subsets or near-mirrors of the Dart equivalents. No fields appear in TS that are missing in Dart. Enums (`LogStatus`, `ReadingFeeling`, `AllocationType`, `AllocationCadence`) match wire format on both sides.

**No admin-only fields found across any type.** This is good news for Phase 3 — the shared `@lumi/types` package can be a clean superset for admin without needing exclusion shims.

---

## Finding 3 — Phase 5 Candidates (Business-Logic Routes)

### High priority — multi-write / cascading / cross-system

| Route | Why | Suggested CF |
|-------|-----|--------------|
| `POST /bulk/students` | 500-doc batch + class resolution + audit | `bulkImportStudents` (onCall) |
| `POST /community-books/deletion-requests/[id]/resolve` | Multi-collection batch delete + Storage cleanup | `resolveCommunityBookDeletion` (onCall) |
| `POST /offboard` | Cascading soft-deactivate across 7 subcollections | `offboardSchool` (onCall, step-wise) |
| `POST /schools/[schoolId]/users` | Firebase Auth + Firestore in one logical op | `createSchoolUser` (onCall) |
| `POST /schools/[schoolId]/students/[studentId]/reading-level` | Updates student + levelHistory; coordinates with existing stats aggregator | `updateStudentReadingLevel` (onCall) |
| `POST /impersonation-audit/sessions/[sessionId]/revoke` | Security-critical; session state + audit + client notification | `revokeImpersonationSession` (onCall) |

### Medium priority — sensitive, but lower complexity

| Route | Why | Suggested CF |
|-------|-----|--------------|
| `POST /schools` | School creation should trigger onboarding pipeline + welcome | `createSchool` (onCall) |
| `POST /schools/[schoolId]/users/[userId]/auth` | Auth mutations (disable/enable/reset); audit-critical | `manageSchoolUserAuth` (onCall) |
| `POST /dev-access` | Grants dev access; should be audited centrally | `grantDevAccess` (onCall) |

### Low priority — leave as direct Admin SDK writes

All remaining routes are single-doc CRUD on collections that don't trigger downstream logic. Do **not** migrate these; they'd be busywork.

---

## Finding 4 — Auth Model Diff

### Current admin auth check

`admin/src/app/api/auth/route.ts:5-28`:

```typescript
const allowedEmails = process.env.ADMIN_EMAILS;
if (allowedEmails) {
  const emailList = allowedEmails.split(",").map((e) => e.trim().toLowerCase());
  if (!decoded.email || !emailList.includes(decoded.email.toLowerCase())) {
    return NextResponse.json({ error: "Unauthorized email" }, { status: 403 });
  }
}
// ... auth_time freshness check ...
```

### Main app super-admin check

`functions/src/super_admin.ts:19-31`:

```typescript
export async function isSuperAdmin(uid: string | undefined | null): Promise<boolean> {
  if (!uid) return false;

  const db = admin.firestore();
  const doc = await db.collection("superAdmins").doc(uid).get();
  if (doc.exists) return true;

  const envList = (process.env.SUPER_ADMIN_UIDS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  return envList.includes(uid);
}
```

### Environment variables

| Side | Var | Format | Purpose |
|------|-----|--------|---------|
| admin | `ADMIN_EMAILS` | comma-sep emails | allowlist (to be retired) |
| functions | `SUPER_ADMIN_UIDS` | comma-sep UIDs | bootstrap fallback for `/superAdmins/{uid}` |
| both | `FIREBASE_SERVICE_ACCOUNT_KEY` | base64 JSON | Admin SDK creds |

### Proposed Phase 4 patch

New file `admin/src/lib/auth-firestore.ts`:

```typescript
import "server-only";
import { getAdminDb } from "./firebase-admin";

/**
 * Mirrors functions/src/super_admin.ts#isSuperAdmin.
 * Duplicated locally to avoid a Cloud Function call at auth time.
 * Primary: /superAdmins/{uid}. Fallback: SUPER_ADMIN_UIDS env (bootstrap only).
 */
export async function isSuperAdminViaFirestore(uid: string | undefined | null): Promise<boolean> {
  if (!uid) return false;
  const db = getAdminDb();
  const doc = await db.collection("superAdmins").doc(uid).get();
  if (doc.exists) return true;
  const envList = (process.env.SUPER_ADMIN_UIDS ?? "")
    .split(",").map((s) => s.trim()).filter((s) => s.length > 0);
  return envList.includes(uid);
}
```

Updated `admin/src/app/api/auth/route.ts` (auth gate replaced; `auth_time` freshness check retained):

```typescript
import { isSuperAdminViaFirestore } from "@/lib/auth-firestore";
// ...
const decoded = await getAdminAuth().verifyIdToken(idToken);
const ok = await isSuperAdminViaFirestore(decoded.uid);
if (!ok) {
  return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
}
// ... existing auth_time check unchanged ...
```

### Bootstrap risk

**Problem:** if `/superAdmins/{uid}` has no doc for the current admin and `SUPER_ADMIN_UIDS` isn't set, **no one can log in**.

**Mitigation (run before merging Phase 4):**
1. Seed `/superAdmins/{uid}` docs for every current admin (use the Firebase console or a one-shot script).
2. Keep `SUPER_ADMIN_UIDS` env var populated on the admin deploy as a temporary escape hatch.
3. Verify by signing in *as a non-admin* (should 403) and *as a seeded admin* (should succeed) in a staging environment before prod cutover.

A safer two-step rollout: Phase 4a deploys with **both** the old email allowlist AND the new Firestore check active (OR logic); after seeding is verified, Phase 4b removes the email allowlist code path and the `ADMIN_EMAILS` env var.

---

## Surprises (non-obvious findings)

1. **`deletionRequests` via collectionGroup query.** The admin lists pending community-book deletion requests with `db.collectionGroup("deletionRequests")` (not scoped to a single book). Requires a collectionGroup index — confirm it's in `firestore.indexes.json` before any related work in this area. Reference: `admin/src/lib/firestore/community-books.ts:69`.

2. **`parentCount` is read-only on the wire.** TS defines it on the `School` interface but admin never writes it — it's computed by a Cloud Function aggregation. Don't add a write of this field in any new admin code.

3. **Impersonation collections are write-restricted by rules.** `devImpersonationSessions` / `devImpersonationAudit` accept writes only from Cloud Functions and the admin revoke endpoint; Flutter clients are read-only. Phase 5 work on impersonation should keep this asymmetry.

4. **No top-level `users` collection.** All users live under `schools/{schoolId}/users`. Any future "find user by email globally" feature would need a `collectionGroup` query or an index doc — don't assume a flat `users` collection exists.

5. **`adminAuditLog` is append-only and never read by routes.** Admin code only writes to it. If we want an admin UI to view the audit log later, that's a new query path — flag it for the team rather than assuming it already works.

6. **`feedback` collection helper is opaque.** `/feedback/[id]/status` calls `updateFeedbackStatus()` but the helper hides the collection shape. Schema isn't documented elsewhere. If Phase 5 ever touches feedback, audit the helper first.
