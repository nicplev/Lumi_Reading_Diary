import { initializeApp, getApps, cert, App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { readFileSync } from 'fs';

let app: App;

if (getApps().length === 0) {
  const serviceAccountPath = process.env.FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH;
  // Default bucket so no-arg adminStorage.bucket() resolves — the
  // comprehension-audio bulk delete relies on it.
  const storageBucket = process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET;
  if (serviceAccountPath) {
    const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf-8'));
    app = initializeApp({ credential: cert(serviceAccount), storageBucket });
  } else {
    // Falls back to GOOGLE_APPLICATION_CREDENTIALS or default credentials
    app = initializeApp({ projectId: 'lumi-ninc-au', storageBucket });
  }
} else {
  app = getApps()[0];
}

export const adminAuth = getAuth(app);
export const adminDb = getFirestore(app);
export const adminStorage = getStorage(app);
