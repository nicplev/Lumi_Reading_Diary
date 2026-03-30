import { adminDb } from '@/lib/firebase/admin';
import { adminAuth } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { SchoolUser, UserRole } from '@/lib/types';

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
    phone: data.phone,
  };
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

export async function updateUser(
  schoolId: string,
  userId: string,
  data: Partial<Pick<SchoolUser, 'fullName' | 'role' | 'phone' | 'classIds'>>
): Promise<void> {
  const update: Record<string, unknown> = {};
  if (data.fullName !== undefined) update.fullName = data.fullName;
  if (data.role !== undefined) update.role = data.role;
  if (data.phone !== undefined) update.phone = data.phone;
  if (data.classIds !== undefined) update.classIds = data.classIds;

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

export async function resetUserPassword(userId: string): Promise<string> {
  const user = await adminAuth.getUser(userId);
  if (!user.email) throw new Error('User has no email address');
  const link = await adminAuth.generatePasswordResetLink(user.email);
  return link;
}
