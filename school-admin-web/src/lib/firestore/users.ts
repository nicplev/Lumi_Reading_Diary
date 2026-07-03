import { adminDb } from '@/lib/firebase/admin';
import { adminAuth } from '@/lib/firebase/admin';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { SchoolUser, UserRole } from '@/lib/types';
import { generateTempPassword } from '@/lib/utils/temp-password';

function toUser(doc: FirebaseFirestore.DocumentSnapshot): SchoolUser {
  const data = doc.data()!;
  return {
    id: doc.id,
    email: data.email ?? '',
    fullName: data.fullName ?? '',
    role: (data.role as UserRole) ?? 'teacher',
    schoolId: data.schoolId ?? '',
    classIds: data.classIds ?? [],
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    lastLoginAt: data.lastLoginAt?.toDate(),
    profileImageUrl: data.profileImageUrl,
    characterId: data.characterId,
    phone: data.phone,
    pendingDeletion: data.pendingDeletion ?? false,
    scheduledDeletionAt: data.scheduledDeletionAt?.toDate(),
    mustChangePassword: data.mustChangePassword ?? false,
    tempPasswordCreatedAt: data.tempPasswordCreatedAt?.toDate(),
  };
}

/** True while a temp password is still relevant — i.e. issued and the staff
 *  member hasn't logged in since. Lets the UI indicator self-clear on first
 *  login without any extra write. */
function isTempPasswordPending(
  tempPasswordCreatedAt?: Date,
  lastLoginAt?: Date
): boolean {
  if (!tempPasswordCreatedAt) return false;
  return !lastLoginAt || lastLoginAt < tempPasswordCreatedAt;
}

export async function getUsers(schoolId: string, filters?: { role?: UserRole }): Promise<SchoolUser[]> {
  let query: FirebaseFirestore.Query = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users');

  if (filters?.role) {
    query = query.where('role', '==', filters.role);
  }

  const snap = await query.get();
  return snap.docs.map(toUser);
}

export async function getUser(schoolId: string, userId: string): Promise<SchoolUser | null> {
  const doc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(userId)
    .get();
  if (!doc.exists) return null;
  return toUser(doc);
}

export async function createUser(
  schoolId: string,
  data: { email: string; fullName: string; role: UserRole; password: string; createdBy: string }
): Promise<string> {
  // Create Firebase Auth user
  const authUser = await adminAuth.createUser({
    email: data.email,
    password: data.password,
    displayName: data.fullName,
  });

  // Create Firestore user doc
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(authUser.uid)
    .set({
      email: data.email,
      fullName: data.fullName,
      role: data.role,
      schoolId,
      classIds: [],
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: data.createdBy,
    });

  return authUser.uid;
}

// ─── Bulk staff import ───────────────────────────────────────────────

export interface StaffImportRow {
  fullName: string;
  email: string;
  role: string; // raw value from CSV; normalised by parseRole
}

export interface CreatedStaff {
  uid: string;
  email: string;
  fullName: string;
  role: UserRole;
  tempPassword: string;
}

export interface StaffImportResult {
  successCount: number;
  errorCount: number;
  errors: { row: number; message: string }[];
  created: CreatedStaff[];
}

/** Normalise a free-text CSV role into a stored UserRole. Blank → teacher. */
export function parseRole(raw: string | undefined): UserRole | null {
  const v = (raw ?? '').toLowerCase().trim();
  if (!v) return 'teacher';
  if (['teacher', 'teach', 'staff'].includes(v)) return 'teacher';
  if (['admin', 'administrator', 'school admin', 'schooladmin'].includes(v)) {
    return 'schoolAdmin';
  }
  return null;
}

/**
 * Bulk-create staff accounts from imported CSV rows. Each row creates a
 * Firebase Auth user with an auto-generated temp password + a Firestore user
 * doc, and stores the plaintext temp password in the Admin-SDK-only
 * `staffCredentials` subcollection. Processed sequentially because Auth
 * createUser isn't batchable; per-row failures are collected, not fatal.
 */
export async function importStaff(
  schoolId: string,
  rows: StaffImportRow[],
  createdBy: string
): Promise<StaffImportResult> {
  const result: StaffImportResult = {
    successCount: 0,
    errorCount: 0,
    errors: [],
    created: [],
  };

  const usersRef = adminDb.collection('schools').doc(schoolId).collection('users');
  const credsRef = adminDb.collection('schools').doc(schoolId).collection('staffCredentials');

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const rowIndex = i + 1;

    const fullName = row.fullName?.trim();
    const email = row.email?.trim().toLowerCase();
    const role = parseRole(row.role);

    if (!fullName || !email) {
      result.errors.push({ row: rowIndex, message: 'Missing name or email' });
      result.errorCount++;
      continue;
    }
    if (!role) {
      result.errors.push({ row: rowIndex, message: `Invalid role "${row.role}" (use teacher or admin)` });
      result.errorCount++;
      continue;
    }

    const tempPassword = generateTempPassword();
    let uid: string | null = null;

    try {
      const authUser = await adminAuth.createUser({
        email,
        password: tempPassword,
        displayName: fullName,
      });
      uid = authUser.uid;

      try {
        await usersRef.doc(uid).set({
          email,
          fullName,
          role,
          schoolId,
          classIds: [],
          isActive: true,
          createdAt: FieldValue.serverTimestamp(),
          createdBy,
          mustChangePassword: true,
          tempPasswordCreatedAt: FieldValue.serverTimestamp(),
        });
        await credsRef.doc(uid).set({
          tempPassword,
          createdAt: FieldValue.serverTimestamp(),
          createdBy,
          consumedAt: null,
        });
      } catch (writeErr) {
        // Roll back the Auth user so we don't leave an orphan account.
        try {
          await adminAuth.deleteUser(uid);
        } catch {
          // best-effort
        }
        throw writeErr;
      }

      result.created.push({ uid, email, fullName, role, tempPassword });
      result.successCount++;
    } catch (err) {
      const code = (err as { code?: string })?.code;
      const message =
        code === 'auth/email-already-exists'
          ? 'Email already in use'
          : code === 'auth/invalid-email'
            ? 'Invalid email'
            : err instanceof Error
              ? err.message
              : 'Failed to create account';
      result.errors.push({ row: rowIndex, message });
      result.errorCount++;
    }
  }

  return result;
}

/**
 * Fetch a staff member's temp password for admin viewing/resending. Returns
 * null if there's no credential or it's already been consumed (the staff
 * member has logged in since it was issued).
 */
export async function getStaffCredential(
  schoolId: string,
  userId: string
): Promise<{ tempPassword: string; createdAt: Date } | null> {
  const [credSnap, user] = await Promise.all([
    adminDb.collection('schools').doc(schoolId).collection('staffCredentials').doc(userId).get(),
    getUser(schoolId, userId),
  ]);
  if (!credSnap.exists || !user) return null;
  const data = credSnap.data()!;
  const createdAt: Date = data.createdAt?.toDate() ?? user.tempPasswordCreatedAt ?? new Date();
  if (!isTempPasswordPending(createdAt, user.lastLoginAt)) return null;
  return { tempPassword: data.tempPassword as string, createdAt };
}

export async function updateUser(
  schoolId: string,
  userId: string,
  data: Partial<Pick<SchoolUser, 'fullName' | 'role' | 'phone' | 'classIds' | 'characterId'>>
): Promise<void> {
  const update: Record<string, unknown> = {};
  if (data.fullName !== undefined) update.fullName = data.fullName;
  if (data.role !== undefined) update.role = data.role;
  if (data.phone !== undefined) update.phone = data.phone;
  if (data.classIds !== undefined) update.classIds = data.classIds;
  if (data.characterId !== undefined) update.characterId = data.characterId;

  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(userId)
    .update(update);

  // Sync displayName to Firebase Auth if name changed
  if (data.fullName) {
    try {
      await adminAuth.updateUser(userId, { displayName: data.fullName });
    } catch {
      // Auth update is best-effort
    }
  }
}

export async function deactivateUser(schoolId: string, userId: string): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(userId)
    .update({ isActive: false });

  try {
    await adminAuth.updateUser(userId, { disabled: true });
  } catch {
    // Auth update is best-effort
  }
}

export async function reactivateUser(schoolId: string, userId: string): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(userId)
    .update({ isActive: true });

  try {
    await adminAuth.updateUser(userId, { disabled: false });
  } catch {
    // Auth update is best-effort
  }
}

export async function resetUserPassword(userId: string, schoolId?: string): Promise<string> {
  // Tenant scoping: when an admin resets another user (schoolId supplied), the
  // target MUST be a member of that admin's school. Without this, a global
  // adminAuth.getUser(userId) + generatePasswordResetLink lets any admin mint a
  // working reset link for any user in any school (cross-tenant account
  // takeover). The self-serve path (profile/reset-password) forces
  // userId === session.uid and passes no schoolId, so it stays safe.
  if (schoolId) {
    const memberDoc = await adminDb
      .collection('schools')
      .doc(schoolId)
      .collection('users')
      .doc(userId)
      .get();
    if (!memberDoc.exists) {
      throw new Error('User not found in this school');
    }
  }

  const user = await adminAuth.getUser(userId);
  if (!user.email) throw new Error('User has no email address');
  const link = await adminAuth.generatePasswordResetLink(user.email);

  // The previously-issued temp password (if any) is now stale — drop it so it
  // stops showing on the Users screen.
  if (schoolId) {
    try {
      await adminDb
        .collection('schools')
        .doc(schoolId)
        .collection('staffCredentials')
        .doc(userId)
        .delete();
      await adminDb
        .collection('schools')
        .doc(schoolId)
        .collection('users')
        .doc(userId)
        .update({ mustChangePassword: false });
    } catch {
      // best-effort cleanup
    }
  }

  return link;
}

export async function markUserForDeletion(schoolId: string, userId: string): Promise<void> {
  const scheduledDeletionAt = Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000));

  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(userId)
    .update({ pendingDeletion: true, scheduledDeletionAt });

  await adminDb.collection('pendingUserDeletions').doc(userId).set({
    userId,
    schoolId,
    scheduledDeletionAt,
  });
}

export async function undoMarkUserForDeletion(schoolId: string, userId: string): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(userId)
    .update({
      pendingDeletion: FieldValue.delete(),
      scheduledDeletionAt: FieldValue.delete(),
    });

  await adminDb.collection('pendingUserDeletions').doc(userId).delete();
}
