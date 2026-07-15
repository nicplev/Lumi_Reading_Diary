import "server-only";
import { getApps, initializeApp, type App } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage, type Storage } from "firebase-admin/storage";

let _app: App | undefined;

function getApp(): App {
  if (_app) return _app;
  if (getApps().length > 0) {
    _app = getApps()[0];
    return _app;
  }

  // Use the runtime's attached service account in Cloud Run/Functions. Local
  // development should use `gcloud auth application-default login`. Keeping a
  // base64 JSON key in Next build configuration copies a permanent private
  // key into the deployment bundle and is unnecessary on Google Cloud.
  _app = initializeApp({
    projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? "lumi-ninc-au",
    // Default bucket so no-arg storage.bucket() resolves — the
    // @lumi/server-ops comprehension-audio delete paths rely on it.
    storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  });
  return _app;
}

let _auth: Auth | undefined;
let _db: Firestore | undefined;
let _storage: Storage | undefined;

export function getAdminAuth(): Auth {
  if (!_auth) _auth = getAuth(getApp());
  return _auth;
}

export function getAdminDb(): Firestore {
  if (!_db) _db = getFirestore(getApp());
  return _db;
}

export function getAdminStorage(): Storage {
  if (!_storage) _storage = getStorage(getApp());
  return _storage;
}
