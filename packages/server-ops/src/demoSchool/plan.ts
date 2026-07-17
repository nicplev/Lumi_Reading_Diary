import {
  buildDemoSchoolPlanData,
  DEMO_SCHOOL_CONSTANTS,
} from "./planData.js";

export interface DemoPlanDocument {
  id: string;
  data: Record<string, any>;
}

export interface DemoAuthUser {
  key: string;
  email: string;
  fullName: string;
  role: "schoolAdmin" | "teacher" | "parent";
  uid: string;
}

export interface DemoSchoolPlan {
  authUsers: DemoAuthUser[];
  school: DemoPlanDocument;
  users: DemoPlanDocument[];
  parents: DemoPlanDocument[];
  classes: DemoPlanDocument[];
  students: Array<DemoPlanDocument & { key: string }>;
  books: DemoPlanDocument[];
  logs: DemoPlanDocument[];
  comments: Array<DemoPlanDocument & { logId: string }>;
  allocations: DemoPlanDocument[];
  linkCodes: DemoPlanDocument[];
  indexEntries: DemoPlanDocument[];
}

export interface DemoSchoolConstants {
  schoolId: string;
  schoolName: string;
  timezone: string;
  retiredIndexEmails: string[];
}

/**
 * Builds the entire demo tenant without accessing Firebase, Storage, secrets,
 * the network or process-global state. The same instant produces the same ids
 * and content, making retries and parity checks deterministic.
 */
export function buildDemoSchoolPlan(now = new Date()): DemoSchoolPlan {
  return buildDemoSchoolPlanData(now) as DemoSchoolPlan;
}

export const demoSchoolConstants =
  DEMO_SCHOOL_CONSTANTS as DemoSchoolConstants;
