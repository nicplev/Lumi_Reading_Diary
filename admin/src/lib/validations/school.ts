import { z } from "zod";

export const createSchoolSchema = z.object({
  name: z.string().min(1, "School name is required"),
  contactEmail: z.string().optional(),
  contactPhone: z.string().optional(),
  address: z.string().optional(),
  timezone: z.string().min(1, "Timezone is required"),
  subscriptionPlan: z.string().optional(),
  logoUrl: z.string().url().optional().or(z.literal("")),
  primaryColor: z.string().optional(),
  secondaryColor: z.string().optional(),
  displayName: z.string().max(100).optional(),
  levelSchema: z
    .enum(["none", "aToZ", "pmBenchmark", "lexile", "custom"])
    .optional(),
  customLevels: z.array(z.string()).optional(),
});

export const updateSchoolSchema = createSchoolSchema.partial();

export type CreateSchoolInput = z.infer<typeof createSchoolSchema>;
export type UpdateSchoolInput = z.infer<typeof updateSchoolSchema>;
