import { initializeApp, getApps, App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

let app: App;

if (getApps().length === 0) {
  // Default bucket so no-arg adminStorage.bucket() resolves — the
  // comprehension-audio bulk delete relies on it.
  const storageBucket = process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET;
  // Always use Application Default Credentials. Reading a JSON key path here
  // caused local private-key material to be copied into Next/Webpack build
  // caches. Cloud Run/Functions should use its attached service account; local
  // development should use `gcloud auth application-default login`.
  app = initializeApp({ projectId: 'lumi-ninc-au', storageBucket });
} else {
  app = getApps()[0];
}

export const adminAuth = getAuth(app);
export const adminDb = getFirestore(app);
export const adminStorage = getStorage(app);
