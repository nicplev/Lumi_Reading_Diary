import { initializeApp, getApps, getApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getFunctions } from 'firebase/functions';
import {
  initializeAppCheck,
  ReCaptchaEnterpriseProvider,
} from 'firebase/app-check';
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

// App Check — opt-in via NEXT_PUBLIC_APP_CHECK_ENABLED=true. Attestation is
// silent until the server flips IMPERSONATION_APP_CHECK_ENFORCED on the
// functions, so enabling here is safe ahead of the server flip.
//
// Browser-only init: the Admin SDK bypasses App Check by design and this
// module is imported from server components where `window` is undefined.
// Guard both conditions.
if (
  typeof window !== 'undefined' &&
  process.env.NEXT_PUBLIC_APP_CHECK_ENABLED === 'true' &&
  process.env.NEXT_PUBLIC_APP_CHECK_RECAPTCHA_KEY
) {
  try {
    // In local dev, set window.FIREBASE_APPCHECK_DEBUG_TOKEN = true BEFORE
    // this module loads to get a console debug token to register.
    initializeAppCheck(app, {
      provider: new ReCaptchaEnterpriseProvider(
        process.env.NEXT_PUBLIC_APP_CHECK_RECAPTCHA_KEY,
      ),
      isTokenAutoRefreshEnabled: true,
    });
  } catch (e) {
    // Never break page rendering over an attestation problem.
    // eslint-disable-next-line no-console
    console.warn('[AppCheck] activation failed:', e);
  }
}
