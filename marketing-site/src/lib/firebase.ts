import { initializeApp, getApps, getApp } from "firebase/app";
import { getFunctions, httpsCallable } from "firebase/functions";

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY!,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN!,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID!,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET!,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID!,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID!,
};

const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApp();
const functions = getFunctions(app, "australia-southeast1");

export interface DemoRequestPayload {
  schoolName: string;
  contactPerson: string;
  contactEmail: string;
  region?: string;
  role?: string;
  preferredTime?: string;
  intent: "demo" | "info";
  message?: string;
}

export interface ContactSalesPayload {
  name: string;
  email: string;
  school?: string;
  topic?: string;
  message: string;
}

export const submitDemoRequest = httpsCallable<DemoRequestPayload, { id: string }>(
  functions,
  "submitDemoRequest"
);

export const submitContactSalesInquiry = httpsCallable<ContactSalesPayload, { success: boolean }>(
  functions,
  "submitContactSalesInquiry"
);
