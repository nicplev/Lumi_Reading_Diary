import { z } from "zod";

export const updateOnboardingStatusSchema = z.object({
  action: z.literal("updateStatus"),
  status: z.enum([
    "demo",
    "interested",
    "registered",
    "setupInProgress",
    "active",
    "suspended",
  ]),
});

export const advanceOnboardingStepSchema = z.object({
  action: z.literal("advanceStep"),
});

export const linkOnboardingToSchoolSchema = z.object({
  action: z.literal("linkSchool"),
  schoolId: z.string().min(1, "School ID is required"),
});

export const onboardingActionSchema = z.discriminatedUnion("action", [
  updateOnboardingStatusSchema,
  advanceOnboardingStepSchema,
  linkOnboardingToSchoolSchema,
]);

export type OnboardingActionInput = z.infer<typeof onboardingActionSchema>;
