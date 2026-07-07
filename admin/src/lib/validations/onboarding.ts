import { z } from "zod";

const onboardingStatusEnum = z.enum([
  "demo",
  "interested",
  "registered",
  "setupInProgress",
  "active",
  "suspended",
]);

// --- Create (intake) ---

export const createOnboardingSchema = z.object({
  schoolName: z.string().min(1, "School name is required"),
  contactEmail: z.string().email("A valid contact email is required"),
  contactPerson: z.string().optional(),
  contactPhone: z.string().optional(),
  estimatedStudentCount: z.coerce.number().int().min(0).default(0),
  estimatedTeacherCount: z.coerce.number().int().min(0).default(0),
  referralSource: z.string().optional(),
  status: onboardingStatusEnum.default("demo"),
  notes: z.string().optional(),
});
export type CreateOnboardingInput = z.infer<typeof createOnboardingSchema>;

// --- Existing triage actions ---

export const updateOnboardingStatusSchema = z.object({
  action: z.literal("updateStatus"),
  status: onboardingStatusEnum,
});

export const advanceOnboardingStepSchema = z.object({
  action: z.literal("advanceStep"),
});

export const linkOnboardingToSchoolSchema = z.object({
  action: z.literal("linkSchool"),
  schoolId: z.string().min(1, "School ID is required"),
});

// --- New actions ---

// Follow-up / CRM edit (contact fields + demo date + metadata notes). Every
// field optional — only the supplied keys are patched.
export const updateOnboardingDetailsSchema = z.object({
  action: z.literal("updateDetails"),
  contactPerson: z.string().optional(),
  contactEmail: z.string().email().optional(),
  contactPhone: z.string().optional(),
  estimatedStudentCount: z.coerce.number().int().min(0).optional(),
  estimatedTeacherCount: z.coerce.number().int().min(0).optional(),
  referralSource: z.string().optional(),
  // ISO strings; empty string clears the value.
  demoScheduledAt: z.string().optional(),
  nextStepAt: z.string().optional(),
  nextStepNote: z.string().optional(),
  notes: z.string().optional(),
});

export const goLiveOnboardingSchema = z.object({
  action: z.literal("goLive"),
});

export const onboardingActionSchema = z.discriminatedUnion("action", [
  updateOnboardingStatusSchema,
  advanceOnboardingStepSchema,
  linkOnboardingToSchoolSchema,
  updateOnboardingDetailsSchema,
  goLiveOnboardingSchema,
]);

export type OnboardingActionInput = z.infer<typeof onboardingActionSchema>;

// --- Provision (create the school + admin + subscription from a request) ---

export const provisionSchoolSchema = z.object({
  timezone: z.string().min(1).default("Australia/Sydney"),
  adminEmail: z.string().email("A valid admin email is required"),
  adminFullName: z.string().min(1, "Admin name is required"),
  subscriptionStatus: z.enum(["comp", "paid", "trial"]).default("comp"),
  createJoinCode: z.boolean().default(false),
});
export type ProvisionSchoolInput = z.infer<typeof provisionSchoolSchema>;
