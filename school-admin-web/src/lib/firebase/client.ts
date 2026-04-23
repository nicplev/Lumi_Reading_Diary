import { initializeApp, getApps, getApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getFunctions } from 'firebase/functions';
import { firebaseConfig } from './config';

// Node 21+ exposes a built-in `localStorage` that is non-functional without
// --localstorage-file.  Firebase Auth detects it and tries to call getItem(),
// which throws.  Remove the broken global so Firebase falls back gracefully.
if (typeof window === 'undefined' && typeof globalThis.localStorage !== 'undefined') {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (globalThis as any).localStorage = undefined;
}

const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApp();
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app);
